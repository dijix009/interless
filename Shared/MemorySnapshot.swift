import Foundation

/// MLX GPU allocator counters (ARCHITECTURE.md §13). Produced behind the backend
/// seam so this `Shared` type carries no MLX dependency.
public struct GPUMemory: Sendable, Equatable {
    public var activeBytes: Int
    public var cacheBytes: Int
    public var peakBytes: Int

    public init(activeBytes: Int = 0, cacheBytes: Int = 0, peakBytes: Int = 0) {
        self.activeBytes = activeBytes
        self.cacheBytes = cacheBytes
        self.peakBytes = peakBytes
    }
}

/// Process- and system-level unified-memory usage. `processFootprintBytes` is the
/// `phys_footprint` the OS itself uses to gauge pressure; `totalUnifiedBytes` is
/// the machine's physical memory.
public struct MemoryFootprint: Sendable, Equatable {
    public var processFootprintBytes: Int
    public var totalUnifiedBytes: Int

    public init(processFootprintBytes: Int, totalUnifiedBytes: Int) {
        self.processFootprintBytes = processFootprintBytes
        self.totalUnifiedBytes = totalUnifiedBytes
    }

    /// Fraction of unified memory in use, in `0...`. Drives the §8 watermarks.
    public var usedFraction: Double {
        guard totalUnifiedBytes > 0 else { return 0 }
        return Double(processFootprintBytes) / Double(totalUnifiedBytes)
    }
}

/// A point-in-time view of memory used by the memory-pressure policy and metrics
/// (ARCHITECTURE.md §7 `currentMemoryUsage`, §8, §13).
public struct MemorySnapshot: Sendable, Equatable {
    public var footprint: MemoryFootprint
    public var gpu: GPUMemory
    public var loadedRoles: Set<ModelRole>
    /// Estimated KV-cache bytes per role (best-effort; may be empty).
    public var kvCacheBytes: [ModelRole: Int]

    public init(
        footprint: MemoryFootprint,
        gpu: GPUMemory = GPUMemory(),
        loadedRoles: Set<ModelRole> = [],
        kvCacheBytes: [ModelRole: Int] = [:]
    ) {
        self.footprint = footprint
        self.gpu = gpu
        self.loadedRoles = loadedRoles
        self.kvCacheBytes = kvCacheBytes
    }

    /// Convenience: the unified-memory usage fraction the watermarks key off.
    public var usedFraction: Double { footprint.usedFraction }

    /// Number of models currently resident.
    public var activeModelCount: Int { loadedRoles.count }
}
