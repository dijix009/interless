import SwiftUI
import AppKit

struct WindowFullscreenObserver: NSViewRepresentable {
    @Binding var isFullscreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullscreen: $isFullscreen)
    }

    func makeNSView(context: Context) -> ProbeView {
        let probe = ProbeView()
        probe.onWindow = { window in
            context.coordinator.observe(window)
        }
        return probe
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        if let window = nsView.window {
            context.coordinator.observe(window)
        }
    }

    @MainActor
    final class Coordinator {
        private var isFullscreen: Binding<Bool>
        private weak var observedWindow: NSWindow?

        init(isFullscreen: Binding<Bool>) {
            self.isFullscreen = isFullscreen
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func observe(_ window: NSWindow) {
            if observedWindow !== window {
                NotificationCenter.default.removeObserver(self)
                observedWindow = window
                for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                    NotificationCenter.default.addObserver(
                        self,
                        selector: #selector(fullscreenDidChange(_:)),
                        name: name,
                        object: window)
                }
            }
            update(from: window)
        }

        private func update(from window: NSWindow) {
            isFullscreen.wrappedValue = window.styleMask.contains(.fullScreen)
        }

        @objc private func fullscreenDidChange(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            update(from: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.update(from: window)
            }
        }
    }

    final class ProbeView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow?(window)
            }
        }
    }
}

/// Native macOS vibrancy (the semi-blurred translucency used by sidebars).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}

/// Hosts SwiftUI content as a native title-bar accessory, so it aligns
/// pixel-perfectly with the native title-bar controls (e.g. the sidebar toggle).
///
/// IMPORTANT: it only re-hosts its content when `token` changes — NOT on every
/// SwiftUI body re-evaluation. During the sidebar collapse/expand animation the
/// body re-evaluates every frame; refreshing the title bar each frame makes it
/// relayout and fights the sidebar animation (a mid-animation "reverse" stutter).
/// Gating on `token` keeps the title bar still during animations.
struct WindowTitlebarAccessory<Content: View>: NSViewRepresentable {
    private let attribute: NSLayoutConstraint.Attribute
    private let token: String
    private let content: Content

    init(
        attribute: NSLayoutConstraint.Attribute = .right,
        token: String,
        @ViewBuilder content: () -> Content
    ) {
        self.attribute = attribute
        self.token = token
        self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ProbeView {
        let coordinator = context.coordinator
        coordinator.attribute = attribute
        coordinator.latest = AnyView(content)
        coordinator.token = token
        let probe = ProbeView()
        probe.onWindow = { window in coordinator.install(in: window) }
        return probe
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        let coordinator = context.coordinator
        guard coordinator.token != token else { return }   // skip per-frame churn
        coordinator.token = token
        coordinator.latest = AnyView(content)
        coordinator.refresh()
    }

    @MainActor
    final class Coordinator {
        var latest: AnyView = AnyView(EmptyView())
        var attribute: NSLayoutConstraint.Attribute = .right
        var token: String = ""
        private var hosting: NSHostingController<AnyView>?
        private var installed = false

        func install(in window: NSWindow) {
            guard !installed else { return }
            let host = NSHostingController(rootView: latest)
            host.view.setFrameSize(host.view.fittingSize)

            let accessory = NSTitlebarAccessoryViewController()
            accessory.layoutAttribute = attribute
            accessory.view = host.view
            window.addTitlebarAccessoryViewController(accessory)

            hosting = host
            installed = true
        }

        func refresh() {
            guard let hosting else { return }
            hosting.rootView = latest
            hosting.view.setFrameSize(hosting.view.fittingSize)
        }
    }

    /// Zero-size probe that reports when it lands in a window (main-actor safe).
    final class ProbeView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?
        private weak var observedWindow: NSWindow?
        private let observedNotifications: [NSNotification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResizeNotification,
            NSWindow.didMoveNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                observe(window)
                reapply(to: window)
            } else {
                NotificationCenter.default.removeObserver(self)
                observedWindow = nil
            }
        }

        override func layout() {
            super.layout()
            if let window {
                reapply(to: window)
            }
        }

        private func observe(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            NotificationCenter.default.removeObserver(self)
            observedWindow = window
            for name in observedNotifications {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidRelayout(_:)),
                    name: name,
                    object: window)
            }
        }

        private func reapply(to window: NSWindow) {
            onWindow?(window)
        }

        @objc private func windowDidRelayout(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            reapply(to: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.reapply(to: window)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
                guard let self, let window else { return }
                self.reapply(to: window)
            }
        }
    }
}

/// Adjusts the native macOS traffic-light group to align with the custom
/// in-content titlebar controls used by `WorkspaceView`.
struct TrafficLightAlignmentProbe: NSViewRepresentable {
    var horizontalOffset: CGFloat
    var verticalOffset: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ProbeView {
        context.coordinator.horizontalOffset = horizontalOffset
        context.coordinator.verticalOffset = verticalOffset
        let probe = ProbeView()
        probe.onWindow = { window in
            context.coordinator.scheduleApply(to: window)
        }
        return probe
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.horizontalOffset = horizontalOffset
        context.coordinator.verticalOffset = verticalOffset
        if let window = nsView.window {
            context.coordinator.scheduleApply(to: window)
        }
    }

    @MainActor
    final class Coordinator {
        var horizontalOffset: CGFloat = 0
        var verticalOffset: CGFloat = 0
        private weak var currentWindow: NSWindow?
        private var baseFrames: [NSWindow.ButtonType: CGRect] = [:]

        func scheduleApply(to window: NSWindow) {
            if currentWindow !== window {
                currentWindow = window
                baseFrames.removeAll()
            }
            apply(to: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.apply(to: window)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
                guard let self, let window else { return }
                self.apply(to: window)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak window] in
                guard let self, let window else { return }
                self.apply(to: window)
            }
        }

        func apply(to window: NSWindow) {
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(type) else { continue }
                var base = baseFrames[type] ?? button.frame
                let expectedOrigin = CGPoint(
                    x: base.origin.x + horizontalOffset,
                    y: base.origin.y - verticalOffset)
                if baseFrames[type] != nil,
                   abs(button.frame.origin.x - expectedOrigin.x) > 0.5 ||
                   abs(button.frame.origin.y - expectedOrigin.y) > 0.5 {
                    base = button.frame
                }
                baseFrames[type] = base

                var frame = base
                frame.origin.x += horizontalOffset
                frame.origin.y -= verticalOffset
                button.setFrameOrigin(frame.origin)
            }
        }
    }

    final class ProbeView: NSView {
        var onWindow: (@MainActor (NSWindow) -> Void)?
        private weak var observedWindow: NSWindow?
        private let observedNotifications: [NSNotification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResizeNotification,
            NSWindow.didMoveNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                observe(window)
                reapply(to: window)
            } else {
                NotificationCenter.default.removeObserver(self)
                observedWindow = nil
            }
        }

        override func layout() {
            super.layout()
            if let window {
                reapply(to: window)
            }
        }

        private func observe(_ window: NSWindow) {
            guard observedWindow !== window else { return }
            NotificationCenter.default.removeObserver(self)
            observedWindow = window
            for name in observedNotifications {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidRelayout(_:)),
                    name: name,
                    object: window)
            }
        }

        private func reapply(to window: NSWindow) {
            onWindow?(window)
        }

        @objc private func windowDidRelayout(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }
            reapply(to: window)
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window else { return }
                self.reapply(to: window)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak window] in
                guard let self, let window else { return }
                self.reapply(to: window)
            }
        }
    }
}
