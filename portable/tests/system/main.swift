import Foundation
import Darwin
@main struct MonitorTests {
    static func main() async throws {
        let rows=BtollSystemSampler.parseNetwork(",bytes_out,bytes_in,\nnode.helper.123,100,200,\nmissing.pid,1,2,\nChrome.456,700,900,\n")
        precondition(rows.count==2 && rows[0].pid==123 && rows[0].read==200 && rows[0].write==100 && rows[0].name=="node.helper")
        precondition(BtollSystemSampler.parseNetwork("permission denied").isEmpty)
        let assertions="""
        pid 12(Player): [0x1234] 01:00:01 NoIdleSleepAssertion named: "Playing music"
        pid 15(WindowServer): [0x1235] 00:00:00 UserIsActive named: "Keyboard"
        pid 17(powerd): [0x1236] 01:00:00 PreventUserIdleDisplaySleep named: "Display awake"
        """
        let reasons=BtollSystemSampler.parseAssertions(assertions)
        precondition(reasons.count==2 && reasons[0].pid==12 && reasons[0].reason=="Playing music")
        let sampler=BtollSystemSampler()
        let first=await sampler.sample(processes:[(getpid(),"MonitorTests")])
        precondition(first.disk.isEmpty) // First counters are a baseline, not a made-up rate.
        let second=await sampler.sample(processes:[(getpid(),"MonitorTests")])
        precondition(second.observed>first.observed)
        precondition(second.disk.allSatisfy { $0.incoming != nil && $0.outgoing != nil && $0.incoming! >= 0 && $0.outgoing! >= 0 })
        print("PASS: reordered network columns, dotted process names, invalid data, sleep assertion filtering, live read-only sampling and rate warm-up")
        print("Live sources: network=\(second.networkAvailable), assertions=\(second.awakeAvailable), battery=\(second.power.present), disk readable=\(!second.disk.isEmpty)")
    }
}
