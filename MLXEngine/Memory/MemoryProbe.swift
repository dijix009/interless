import Foundation
import Shared

/// Process- and system-level unified-memory probe (ARCHITECTURE.md §13).
///
/// Imports **no MLX**: the GPU allocator counters come from the backend seam
/// (`InferenceBackend.gpuMemory()`). This type only reads the process footprint
/// and the machine's total physical memory.
public enum MemoryProbe {

    /// The process's physical memory footprint (`phys_footprint`) in bytes — the
    /// same figure the OS uses to gauge memory pressure. Returns 0 on failure.
    public static func processFootprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint)
    }

    /// Total unified memory on this machine, in bytes.
    public static func totalUnifiedBytes() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory)
    }

    /// A `MemoryFootprint` combining the process footprint and the system total.
    public static func footprint() -> MemoryFootprint {
        MemoryFootprint(
            processFootprintBytes: processFootprintBytes(),
            totalUnifiedBytes: totalUnifiedBytes()
        )
    }
}
