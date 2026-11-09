import Foundation
import Darwin

struct BsstollBridgeFiles {
    struct Result: Sendable { let firstInstall: Bool; let changed: Bool }
    static func install(resource: URL, home: URL, uid: UInt32, bootstrap: Bool = true) throws -> Result {
        let fm=FileManager.default
        let manifest=try Data(contentsOf:resource.appendingPathComponent("manifest.json"))
        let info=try JSONSerialization.jsonObject(with:manifest) as? [String:Any]
        guard let build=info?["buildID"] as? String,let files=info?["files"] as? [String] else { throw CocoaError(.fileReadCorruptFile) }
        let root=home.appendingPathComponent("Library/Application Support/AtollCodexBridge")
        let first = !fm.fileExists(atPath:root.appendingPathComponent("bridge.mjs").path)
        let marker=root.appendingPathComponent("installed-manifest.json")
        let changed=(try? Data(contentsOf:marker)) != manifest
        try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        if changed {
            for name in files {
                guard !name.hasPrefix("/"), !name.split(separator:"/").contains("..") else { throw CocoaError(.fileReadCorruptFile) }
                let destination=root.appendingPathComponent(name)
                try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
                let temporary=destination.appendingPathExtension("installing")
                try? fm.removeItem(at:temporary)
                try fm.copyItem(at:resource.appendingPathComponent(name),to:temporary)
                let executable=["node","temperature-reader","metadata-reader"].contains(name)
                try fm.setAttributes([.posixPermissions:executable ? 0o755 : 0o600],ofItemAtPath:temporary.path)
                guard rename(temporary.path,destination.path)==0 else { throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO) }
            }
        }
        let logs=home.appendingPathComponent("Library/Logs/AtollCodexBridge")
        try fm.createDirectory(at:logs,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let log=logs.appendingPathComponent("bridge.log")
        if !fm.fileExists(atPath:log.path) { fm.createFile(atPath:log.path,contents:Data(),attributes:[.posixPermissions:0o600]) }
        let agents=home.appendingPathComponent("Library/LaunchAgents")
        try fm.createDirectory(at:agents,withIntermediateDirectories:true)
        let plist=agents.appendingPathComponent("local.codex.atoll-status.plist")
        let configuration:[String:Any]=[
            "Label":"local.codex.atoll-status",
            "ProgramArguments":[root.appendingPathComponent("node").path,root.appendingPathComponent("bridge.mjs").path],
            "WorkingDirectory":root.path,
            "EnvironmentVariables":["PATH":root.path+":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"],
            "RunAtLoad":true,"KeepAlive":true,"ThrottleInterval":10,"ProcessType":"Background",
            "StandardOutPath":log.path,"StandardErrorPath":log.path
        ]
        let data=try PropertyListSerialization.data(fromPropertyList:configuration,format:.xml,options:0)
        let existingAgent=(try? Data(contentsOf:plist)).flatMap { try? PropertyListSerialization.propertyList(from:$0,options:[],format:nil) } as? NSDictionary
        let agentChanged=existingAgent?.isEqual(to:configuration) != true
        if agentChanged { try data.write(to:plist,options:.atomic) }
        if bootstrap {
            let domain="gui/\(uid)";let job=domain+"/local.codex.atoll-status"
            if changed || agentChanged { _=try? launchctl(["bootout",job]) }
            if launchctlOrFailure(["print",job]) != 0 {
                guard try launchctl(["bootstrap",domain,plist.path])==0 else { throw CocoaError(.executableRuntimeMismatch) }
            }
        }
        if changed { try manifest.write(to:marker,options:.atomic) }
        _=build
        return Result(firstInstall:first,changed:changed)
    }
    private static func launchctlOrFailure(_ args:[String])->Int32 { (try? launchctl(args)) ?? -1 }
    private static func launchctl(_ args:[String]) throws -> Int32 {
        let p=Process();p.executableURL=URL(fileURLWithPath:"/bin/launchctl");p.arguments=args
        p.standardOutput=FileHandle.nullDevice;p.standardError=FileHandle.nullDevice
        try p.run();p.waitUntilExit();return p.terminationStatus
    }
}
