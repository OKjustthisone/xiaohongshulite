import Foundation
import Darwin

public enum MemoryProfiler {
    /// Returns the exact physical memory footprint (in MB) of the current macOS process,
    /// matching the "Memory" column reported by macOS Activity Monitor.
    public static func currentProcessFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / (1024.0 * 1024.0)
    }

    /// Samples memory usage of the app process plus any direct child processes (if present).
    public static func sample(isHibernated: Bool) -> MemorySnapshot {
        let appMB = currentProcessFootprintMB()
        let childStats = childProcessRSSStats()
        return MemorySnapshot(
            appFootprintMB: appMB,
            webContentFootprintMB: childStats.totalMB,
            webProcessCount: childStats.count,
            isHibernated: isHibernated,
            timestamp: Date()
        )
    }

    private static func childProcessRSSStats() -> (totalMB: Double, count: Int) {
        let myPid = getpid()
        var childPids = [pid_t](repeating: 0, count: 64)
        let bytes = proc_listchildpids(myPid, &childPids, Int32(childPids.count * MemoryLayout<pid_t>.size))
        guard bytes > 0 else { return (0, 0) }
        let count = Int(bytes) / MemoryLayout<pid_t>.size
        var totalBytes: UInt64 = 0
        var activeCount = 0

        for i in 0..<count {
            let pid = childPids[i]
            guard pid > 0 else { continue }
            var taskInfo = proc_taskinfo()
            let size = proc_pidinfo(
                pid,
                PROC_PIDTASKINFO,
                0,
                &taskInfo,
                Int32(MemoryLayout<proc_taskinfo>.size)
            )
            if size == MemoryLayout<proc_taskinfo>.size {
                totalBytes += taskInfo.pti_resident_size
                activeCount += 1
            }
        }
        return (Double(totalBytes) / (1024.0 * 1024.0), activeCount)
    }
}
