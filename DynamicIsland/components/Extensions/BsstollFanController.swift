import AppKit
import Foundation

@MainActor
enum BsstollFanController {
    private static var busy = false
    private static let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AtollCodexBridge")
    private static var stateURL: URL { root.appendingPathComponent("fan-state.json") }
    nonisolated private static let helper = "/Library/PrivilegedHelperTools/local.bsstoll.fan-helper"
    private static func write(_ value: [String:Any]) {
        guard let data=try? JSONSerialization.data(withJSONObject:value) else { return }
        try? data.write(to:stateURL,options:.atomic)
        try? FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:stateURL.path)
    }
    nonisolated private static func request(_ command: String, rpm:Double?, duration:Double) -> [String:Any] {
        guard FileManager.default.isExecutableFile(atPath:helper) else { return ["ok":false,"message":"点击安装风扇控制服务，首次需要管理员授权","unavailable":true] }
        var payload:[String:Any]=["command":command,"seconds":duration]
        if let rpm { payload["rpm"]=rpm }
        guard let data=try? JSONSerialization.data(withJSONObject:payload), let argument=String(data:data,encoding:.utf8) else { return ["ok":false,"message":"控制参数无效"] }
        let p=Process(); let pipe=Pipe()
        p.executableURL=URL(fileURLWithPath:helper); p.arguments=["client",argument]; p.standardOutput=pipe; p.standardError=FileHandle.nullDevice
        do {
            try p.run()
            let output=pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return (try? JSONSerialization.jsonObject(with:output)) as? [String:Any] ?? ["ok":false,"message":"控制服务返回无效数据"]
        } catch { return ["ok":false,"message":error.localizedDescription] }
    }
    static func setFan(_ mode:String,rpm:Double?=nil,duration:TimeInterval=600) async {
        guard !busy,["auto","boost","manual"].contains(mode) else { return }
        busy=true; defer { busy=false }
        write(["mode":"starting","backend":"bsstoll-smc","updated":Date().timeIntervalSince1970*1000])
        let reply=await Task.detached { request(mode,rpm:rpm,duration:duration) }.value
        var state=reply
        if reply["ok"] as? Bool != true { state["mode"]="error" }
        state["updated"]=Date().timeIntervalSince1970*1000
        write(state)
    }
    static func install() async {
        guard let package=Bundle.main.resourceURL?.appendingPathComponent("FanControl/bsstoll-fan-service.pkg") else { return }
        NSWorkspace.shared.open(package)
    }
    static func handle(_ url:URL) -> Bool {
        guard url.scheme == "bsstoll",url.host == "fan" else { return false }
        if url.path == "/install" { Task { await install() }; return true }
        if url.path == "/status" {
            Task {
                let reply=await Task.detached { request("status",rpm:nil,duration:600) }.value
                if let data=try? JSONSerialization.data(withJSONObject:reply) { try? data.write(to:root.appendingPathComponent("fan-service-status.json"),options:.atomic) }
            }; return true
        }
        return false
    }
    static func restoreForTermination() {
        // Hardware deadline is enforced by the independent privileged service.
        _=request("auto",rpm:nil,duration:600)
    }
}
