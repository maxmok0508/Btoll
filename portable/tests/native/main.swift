import Foundation
import Darwin
let resource=URL(fileURLWithPath:CommandLine.arguments[1])
let home=URL(fileURLWithPath:CommandLine.arguments[2])
let one=try BsstollBridgeFiles.install(resource:resource,home:home,uid:getuid(),bootstrap:false)
precondition(one.firstInstall && one.changed)
let root=home.appendingPathComponent("Library/Application Support/AtollCodexBridge")
let sentinel=root.appendingPathComponent("dashboard.json")
try Data("{\"sentinel\":true}".utf8).write(to:sentinel)
let two=try BsstollBridgeFiles.install(resource:resource,home:home,uid:getuid(),bootstrap:false)
precondition(!two.firstInstall && !two.changed)
let saved=try String(contentsOf:sentinel,encoding:.utf8)
precondition(saved=="{\"sentinel\":true}")
let plist=home.appendingPathComponent("Library/LaunchAgents/local.codex.atoll-status.plist")
let config=try PropertyListSerialization.propertyList(from:Data(contentsOf:plist),format:nil) as! [String:Any]
let args=config["ProgramArguments"] as! [String]
precondition(args.first==root.appendingPathComponent("node").path)
precondition(FileManager.default.isExecutableFile(atPath:args[0]))
let p=Process();let pipe=Pipe();p.executableURL=URL(fileURLWithPath:args[0]);p.arguments=["--version"];p.standardOutput=pipe;try p.run();p.waitUntilExit();precondition(p.terminationStatus==0)
print("PASS: clean user home, spaces in path, bundled runtime, idempotent upgrade, preserved user snapshot, generated LaunchAgent")
