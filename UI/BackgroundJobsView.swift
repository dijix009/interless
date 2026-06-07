import SwiftUI

public struct BackgroundJobsView: View {
    public var jobs: [BackgroundToolJobViewState]
    public var onCancel: @MainActor (UUID) -> Void

    public init(
        jobs: [BackgroundToolJobViewState],
        onCancel: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        self.jobs = jobs
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space2) {
            ForEach(jobs) { job in
                HStack(spacing: .space2) {
                    if job.status == .running || job.status == .queued {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: symbol(for: job.status))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.title)
                            .lineLimit(1)
                        if !job.detail.isEmpty {
                            Text(job.detail)
                                .font(.metaMono)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(job.status.rawValue)
                        .foregroundStyle(.secondary)
                    if job.canCancel {
                        Button {
                            onCancel(job.id)
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Cancel job")
                    }
                }
                .font(.metaMono)
            }
        }
    }

    private func symbol(for status: BackgroundToolJobStatus) -> String {
        switch status {
        case .queued, .running: return "circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon"
        case .cancelled: return "xmark.circle"
        }
    }
}
