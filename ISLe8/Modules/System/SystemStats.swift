import Darwin
import Foundation

/// Activity Monitor in brief, for the System tab: CPU, memory, the startup disk, network
/// traffic and the processes using the most CPU. Sampled every two seconds, only while the
/// tab is on screen; nothing runs otherwise.
@Observable
final class SystemStats {
    nonisolated struct Process: Identifiable, Equatable, Sendable {
        let id: Int32
        let name: String
        /// Percent of one core, as Activity Monitor shows it; above 100 on several cores.
        let cpu: Double
        let memory: UInt64
    }

    nonisolated struct Sample: Equatable, Sendable {
        var cpu: Double
        var cores: Int
        var memoryUsed: UInt64
        var memoryTotal: UInt64
        var diskTotal: Int64
        var diskFree: Int64
        /// Bytes a second over Ethernet and Wi-Fi.
        var download: Double
        var upload: Double
        var top: [Process]
    }

    private(set) var sample: Sample?
    @ObservationIgnored private var isSampling = false

    /// Samples for as long as the calling task lives: the System tab's `.task`, which SwiftUI
    /// cancels when the tab goes away. A second caller waits its turn instead of sampling twice.
    func run() async {
        while isSampling {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }
        }
        isSampling = true
        defer { isSampling = false }
        let sampler = StatsSampler()
        while !Task.isCancelled {
            let next = await sampler.next()
            guard !Task.isCancelled else { break }
            sample = next
            try? await Task.sleep(for: .seconds(2))
        }
    }
}

/// Keeps the previous counters, so CPU and network use are measured over the last second.
private actor StatsSampler {
    private let host = mach_host_self()
    private var lastTicks: [UInt32]?
    private var lastNetwork: (received: UInt64, sent: UInt64, at: Date)?
    private var lastProcessTimes: [Int32: UInt64] = [:]
    private var lastProcessRead = Date.distantPast
    private var disk: (total: Int64, free: Int64) = (0, 0)
    private var diskReadAt = Date.distantPast
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    func next() -> SystemStats.Sample {
        let now = Date()
        if now.timeIntervalSince(diskReadAt) > 10 {
            disk = readDisk()
            diskReadAt = now
        }
        let memory = readMemory()
        let traffic = readNetwork(now)
        return SystemStats.Sample(
            cpu: readCPU(),
            cores: ProcessInfo.processInfo.activeProcessorCount,
            memoryUsed: memory,
            memoryTotal: ProcessInfo.processInfo.physicalMemory,
            diskTotal: disk.total,
            diskFree: disk.free,
            download: traffic.download,
            upload: traffic.upload,
            top: readTopProcesses(now)
        )
    }

    /// The share of all cores busy since the last sample.
    private func readCPU() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3] // user, system, idle, nice
        defer { lastTicks = ticks }
        guard let last = lastTicks else { return 0 }
        let delta = zip(ticks, last).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        return total > 0 ? (delta[0] + delta[1] + delta[3]) / total : 0
    }

    /// "Memory Used" as Activity Monitor counts it: app memory, wired and compressed.
    private func readMemory() -> UInt64 {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pages = UInt64(info.internal_page_count) &- UInt64(info.purgeable_count)
            &+ UInt64(info.wire_count) &+ UInt64(info.compressor_page_count)
        var pageSize: vm_size_t = 0
        host_page_size(host, &pageSize)
        return pages &* UInt64(pageSize)
    }

    private func readDisk() -> (Int64, Int64) {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return (0, 0) }
        return (Int64(values.volumeTotalCapacity ?? 0), values.volumeAvailableCapacityForImportantUsage ?? 0)
    }

    /// Bytes in and out of the en interfaces (Ethernet, Wi-Fi) since the last sample.
    private func readNetwork(_ now: Date) -> (download: Double, upload: Double) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (0, 0) }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  String(cString: interface.ifa_name).hasPrefix("en"),
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        defer { lastNetwork = (received, sent, now) }
        guard let last = lastNetwork, now > last.at, received >= last.received, sent >= last.sent else { return (0, 0) }
        let seconds = now.timeIntervalSince(last.at)
        return (Double(received - last.received) / seconds, Double(sent - last.sent) / seconds)
    }

    /// The user's own processes by CPU over the last sample; system ones can't be read
    /// without root, and Activity Monitor is the place for those.
    private func readTopProcesses(_ now: Date) -> [SystemStats.Process] {
        let capacity = Int(proc_listallpids(nil, 0)) + 64
        guard capacity > 64 else { return [] }
        var pids = [pid_t](repeating: 0, count: capacity)
        let found = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
        let seconds = now.timeIntervalSince(lastProcessRead)
        var times: [Int32: UInt64] = [:]
        var busy: [(pid: Int32, cpu: Double, memory: UInt64)] = []
        for pid in pids.prefix(max(found, 0)) where pid > 0 {
            var info = rusage_info_v2()
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard result == 0 else { continue }
            // Mach time units; nanoseconds after the timebase.
            let time = (info.ri_user_time &+ info.ri_system_time) &* timebase.numer / timebase.denom
            times[pid] = time
            if let last = lastProcessTimes[pid], time >= last, seconds > 0, seconds < 5 {
                busy.append((pid, Double(time - last) / (seconds * 1e9) * 100, info.ri_phys_footprint))
            }
        }
        lastProcessTimes = times
        lastProcessRead = now
        return busy.sorted { $0.cpu > $1.cpu }.prefix(5).map { process in
            SystemStats.Process(id: process.pid, name: Self.name(of: process.pid), cpu: process.cpu, memory: process.memory)
        }
    }

    /// The executable's file name in full; the kernel's short name when the file is gone
    /// (the path then reads "… (deleted)").
    private static func name(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
            let path = string(buffer)
            let name = (path as NSString).lastPathComponent
            if !path.hasSuffix("(deleted)"), !name.isEmpty, name != "deleted" { return name }
        }
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "\(pid)" }
        return string(buffer)
    }

    private static func string(_ buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
