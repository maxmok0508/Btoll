import Foundation
import IOKit
import Darwin

struct BtollTraffic: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let incoming: Double?
    let outgoing: Double?
    var id: Int32 { pid }
}
struct BtollAwakeReason: Identifiable, Sendable {
    let pid: Int32
    let name: String
    let kind: String
    let reason: String
    var id: String { "\(pid):\(kind):\(reason)" }
}
struct BtollPower: Sendable {
    var present = false
    var charging = false
    var pluggedIn = false
    var percentage: Double?
    var health: Double?
    var cycles: Int?
    var batteryWatts: Double?
    var temperature: Double?
    static func read() -> Self {
        var value = Self()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return value }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let p = properties?.takeRetainedValue() as? [String: Any] else { return value }
        let battery = p["BatteryData"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? { (p[key] as? NSNumber)?.doubleValue ?? (battery[key] as? NSNumber)?.doubleValue }
        value.present = true
        value.charging = p["IsCharging"] as? Bool ?? false
        value.pluggedIn = p["ExternalConnected"] as? Bool ?? false
        if let current=number("CurrentCapacity"),let capacity=number("MaxCapacity"),capacity>0 { value.percentage=min(100,max(0,current/capacity*100)) }
        if let full=number("AppleRawMaxCapacity") ?? number("NominalChargeCapacity"),let design=number("DesignCapacity"),design>0 { value.health=min(100,full/design*100) }
        value.cycles=number("CycleCount").map(Int.init)
        if let volts=number("Voltage"), let amp=(p["InstantAmperage"] as? NSNumber) ?? (p["Amperage"] as? NSNumber) {
            let watts=Double(amp.int64Value)*volts/1_000_000
            if watts.isFinite,abs(watts)<500 { value.batteryWatts=watts }
        }
        if let t=number("Temperature") ?? (IORegistryEntrySearchCFProperty(service,kIOServicePlane,"Temperature" as CFString,kCFAllocatorDefault,IOOptionBits(kIORegistryIterateRecursively)) as? NSNumber)?.doubleValue, t>0,t<10000 { value.temperature=t/100 }
        return value
    }
}
struct BtollSystemSnapshot: Sendable {
    var disk: [BtollTraffic] = []
    var network: [BtollTraffic] = []
    var awake: [BtollAwakeReason] = []
    var power = BtollPower()
    var networkAvailable = false
    var awakeAvailable = false
    var observed = Date.distantPast
}

/// Read-only sampling. No privileged tools, packet capture, process control or sleep assertions.
actor BtollSystemSampler {
    private struct Counter { let read: UInt64; let write: UInt64; let started: UInt64 }
    private var previousDisk: [Int32: Counter] = [:]
    private var previousNetwork: [Int32: Counter] = [:]
    private var previousDiskTime: TimeInterval?
    private var previousNetworkTime: TimeInterval?
    func sample(processes: [(Int32, String)]) -> BtollSystemSnapshot {
        var snapshot=BtollSystemSnapshot()
        snapshot.power=BtollPower.read()
        let time=ProcessInfo.processInfo.systemUptime
        var next: [Int32: Counter] = [:]
        for (pid,name) in processes {
            var usage=rusage_info_v2()
            let status=withUnsafeMutablePointer(to:&usage) { pointer in
                pointer.withMemoryRebound(to:rusage_info_t?.self,capacity:1) { proc_pid_rusage(pid,RUSAGE_INFO_V2,$0) }
            }
            guard status==0 else { continue }
            let c=Counter(read:usage.ri_diskio_bytesread,write:usage.ri_diskio_byteswritten,started:usage.ri_proc_start_abstime)
            next[pid]=c
            if let old=previousDisk[pid],old.started==c.started,let t=previousDiskTime,time>t,c.read>=old.read,c.write>=old.write {
                snapshot.disk.append(BtollTraffic(pid:pid,name:name,incoming:Double(c.read-old.read)/(time-t),outgoing:Double(c.write-old.write)/(time-t)))
            }
        }
        previousDisk=next;previousDiskTime=time
        snapshot.disk.sort { ($0.outgoing ?? 0) > ($1.outgoing ?? 0) }
        if let output=Self.command("/usr/bin/nettop",["-P","-L","1","-s","1","-x","-J","bytes_in,bytes_out"]) {
            let now=ProcessInfo.processInfo.systemUptime
            let rows=Self.parseNetwork(output)
            var counters: [Int32: Counter] = [:]
            let names=Dictionary(processes,uniquingKeysWith:{ first,_ in first })
            for row in rows {
                counters[row.pid]=Counter(read:row.read,write:row.write,started:next[row.pid]?.started ?? 0)
                var down: Double?;var up: Double?
                if let old=previousNetwork[row.pid],old.started==(next[row.pid]?.started ?? 0),let t=previousNetworkTime,now>t,row.read>=old.read,row.write>=old.write {
                    down=Double(row.read-old.read)/(now-t);up=Double(row.write-old.write)/(now-t)
                }
                snapshot.network.append(BtollTraffic(pid:row.pid,name:names[row.pid] ?? row.name,incoming:down,outgoing:up))
            }
            previousNetwork=counters;previousNetworkTime=now
            snapshot.networkAvailable=output.contains("bytes_in") && output.contains("bytes_out")
            snapshot.network.sort { ($0.incoming ?? 0)+($0.outgoing ?? 0) > ($1.incoming ?? 0)+($1.outgoing ?? 0) }
        } else { previousNetwork=[:];previousNetworkTime=nil }
        if let output=Self.command("/usr/bin/pmset",["-g","assertions"]) {
            snapshot.awake=Self.parseAssertions(output)
            snapshot.awakeAvailable=output.contains("Assertion status")
        }
        snapshot.observed=Date()
        return snapshot
    }
    struct NetworkRow: Sendable { let pid: Int32; let name: String; let read: UInt64; let write: UInt64 }
    nonisolated static func parseNetwork(_ text: String) -> [NetworkRow] {
        var indices: (Int,Int)?
        var rows: [NetworkRow] = []
        for line in text.split(separator:"\n") {
            let columns=line.split(separator:",",omittingEmptySubsequences:false).map(String.init)
            if let r=columns.firstIndex(of:"bytes_in"),let w=columns.firstIndex(of:"bytes_out") { indices=(r,w);continue }
            guard let (r,w)=indices, columns.count>max(r,w),let first=columns.first,
                  let dot=first.lastIndex(of:"."),let pid=Int32(first[first.index(after:dot)...]),
                  let read=UInt64(columns[r]),let write=UInt64(columns[w]) else { continue }
            rows.append(NetworkRow(pid:pid,name:String(first[..<dot]),read:read,write:write))
        }
        return rows
    }
    nonisolated static func parseAssertions(_ text: String) -> [BtollAwakeReason] {
        let pattern = #"pid\s+(\d+)\((.*?)\):\s+\[.*?\]\s+\S+\s+(\S+)\s+named:\s+\"(.*)\""#
        guard let regex=try? NSRegularExpression(pattern:pattern) else { return [] }
        let kinds:Set<String>=["PreventUserIdleSystemSleep","PreventSystemSleep","PreventUserIdleDisplaySleep","InternalPreventDisplaySleep","NoIdleSleepAssertion","NoDisplaySleepAssertion"]
        return text.split(separator:"\n").compactMap { raw in
            let line=String(raw)
            guard let match=regex.firstMatch(in:line,range:NSRange(line.startIndex...,in:line)) else { return nil }
            func group(_ index:Int)->String { Range(match.range(at:index),in:line).map {String(line[$0])} ?? "" }
            guard let pid=Int32(group(1)),kinds.contains(group(3)) else { return nil }
            return BtollAwakeReason(pid:pid,name:group(2),kind:group(3),reason:group(4))
        }
    }
    nonisolated private static func command(_ executable:String,_ args:[String])->String? {
        let process=Process();let pipe=Pipe()
        process.executableURL=URL(fileURLWithPath:executable);process.arguments=args
        process.standardOutput=pipe;process.standardError=FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout=DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+8,execute:timeout)
        let data=pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit();timeout.cancel()
        guard process.terminationStatus==0 else { return nil }
        return String(data:data,encoding:.utf8)
    }
}
