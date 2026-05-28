//
//  SwapMonitor.swift
//  Blinken
//
//  1Hz poll of swap usage via sysctlbyname("vm.swapusage") and memory
//  pressure via kern.memorystatus_vm_pressure_level (PRD §2.4).
//

import Foundation
import Darwin

/// Polls system swap usage and memory pressure once per second and publishes the
/// state for the menu bar's swap bar + Memory dropdown.
///
/// 1Hz, not 120Hz: swap is a *level* (state), not a flow — the kernel updates it
/// on the order of seconds, so higher sample rates would return the same value
/// over and over.
@MainActor
final class SwapMonitor: ObservableObject {

    /// Kernel memory-pressure level (`kern.memorystatus_vm_pressure_level`).
    /// Values match the `DISPATCH_MEMORYPRESSURE_*` constants.
    enum Pressure: Int32 {
        case normal = 1
        case warning = 2
        case critical = 4

        var label: String {
            switch self {
            case .normal:   return "Normal"
            case .warning:  return "Warning"
            case .critical: return "Critical"
            }
        }
    }

    /// Bytes currently swapped out.
    @Published private(set) var swapUsedBytes: UInt64 = 0
    /// Currently-allocated swap-file size. macOS grows swap files dynamically up
    /// to free disk space, so this isn't a hard cap — it's the size the kernel
    /// has allocated *right now*.
    @Published private(set) var swapTotalBytes: UInt64 = 0
    /// Latest kernel memory-pressure reading.
    @Published private(set) var pressure: Pressure = .normal

    /// Bytes of physical RAM currently in active use — approximates Activity
    /// Monitor's "Memory Used": (active + wired + compressed) × page size.
    @Published private(set) var ramUsedBytes: UInt64 = 0

    /// Total physical RAM (`hw.memsize`), captured once at init. The swap bar's
    /// stable denominator — the kernel-allocated swap pool grows on demand on
    /// macOS, so `used / pool` slides with usage; `used / RAM` is the real
    /// pressure signal.
    let systemRAMBytes: UInt64 = SwapMonitor.readPhysicalRAM()

    private var timer: Timer?

    /// Begins 1Hz polling. Idempotent.
    func start() {
        guard timer == nil else { return }
        sample() // first reading immediately so the menu isn't blank
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.sampling.debug("SwapMonitor started at 1Hz")
    }

    /// Stops polling.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        // vm.swapusage → struct xsw_usage { total, avail, used; pagesize; encrypted }.
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 {
            swapTotalBytes = usage.xsu_total
            swapUsedBytes = usage.xsu_used
        }

        // RAM "Memory Used" via host_statistics64 (active + wired + compressed pages).
        ramUsedBytes = Self.readRAMUsedBytes()

        // kern.memorystatus_vm_pressure_level → 1/2/4 (DISPATCH_MEMORYPRESSURE_*).
        var level: Int32 = 1
        var levelSize = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) == 0 {
            pressure = Pressure(rawValue: level) ?? .normal
        }
    }

    /// Reads `hw.memsize` — the canonical "installed RAM" value on macOS.
    /// We avoid `ProcessInfo.processInfo.physicalMemory`, which under-reports on
    /// Apple Silicon (returns the "usable" page-pool size, e.g. ~16 GiB on a
    /// 24 GB Mac).
    nonisolated private static func readPhysicalRAM() -> UInt64 {
        var bytes: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &bytes, &size, nil, 0) == 0, bytes > 0 {
            return bytes
        }
        return ProcessInfo.processInfo.physicalMemory
    }

    /// Approximates Activity Monitor's "Memory Used" — (wired + active + compressed)
    /// pages × page size — via `host_statistics64` with `HOST_VM_INFO64`. Excludes
    /// inactive/cached pages (which macOS keeps around as "free" buffers).
    nonisolated private static func readRAMUsedBytes() -> UInt64 {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        // `vm_kernel_page_size` is a mutable global → not concurrency-safe in
        // Swift 6 strict mode. `getpagesize()` is the POSIX equivalent (4096 on
        // Apple Silicon) and thread-safe.
        let pageSize = UInt64(getpagesize())
        let usedPages = UInt64(stats.wire_count)
            + UInt64(stats.active_count)
            + UInt64(stats.compressor_page_count)
        return usedPages * pageSize
    }
}
