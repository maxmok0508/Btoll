import Foundation
import Darwin

let socketPath = "/var/run/bsstoll-fan.sock"
struct FanError: Error, CustomStringConvertible { let description: String; init(_ text: String) { description=text } }
func raw(_ key: String) throws -> SMCVal_t {
    var value=SMCVal_t(key)
    guard SMC.shared.read(&value) == KERN_SUCCESS, value.dataSize > 0 else { throw FanError("SMC 读取失败：\(key)") }
    return value
}
func number(_ key: String) throws -> Double {
    let v=try raw(key)
    switch v.dataType {
    case "ui8 ": return Double(v.bytes[0])
    case "flt ": return Double(Float(v.bytes)!)
    case "fpe2": return Double(Int(fromFPE2:(v.bytes[0],v.bytes[1])))
    default: throw FanError("不支持的数据类型：\(key)")
    }
}
func writeNumber(_ key: String, _ n: Double) throws {
    var v=try raw(key)
    switch v.dataType {
    case "ui8 ": v.bytes[0]=UInt8(n)
    case "flt ": v.bytes.replaceSubrange(0..<4, with:Float(n).bytes)
    case "fpe2": let x=Int(n*4); v.bytes[0]=UInt8(x>>8); v.bytes[1]=UInt8(x&255)
    default: throw FanError("不支持的数据类型：\(key)")
    }
    guard SMC.shared.write(v) == KERN_SUCCESS else { throw FanError("SMC 写入失败：\(key)") }
}
struct Fan {
    let id: Int
    var prefix: String { "F\(id)" }
    let modeKey: String
    let minimum: Double
    let maximum: Double
    init(_ id: Int) throws {
        self.id=id
        let p="F\(id)"
        guard let mode=[p+"md",p+"Md"].first(where:{(try? raw($0)) != nil}) else { throw FanError("未发现风扇控制接口") }
        modeKey=mode; minimum=try number(p+"Mn"); maximum=try number(p+"Mx")
        guard minimum >= 0, maximum > minimum, maximum < 20000 else { throw FanError("风扇转速范围无效") }
    }
    func automatic() throws { try writeNumber(modeKey,0) }
    func set(_ rpm: Double) throws {
        guard rpm.isFinite, rpm >= minimum, rpm <= maximum else { throw FanError("转速超出硬件范围") }
        do { try writeNumber(modeKey,1) }
        catch {
            guard (try? raw("Ftst")) != nil else { throw error }
            try writeNumber("Ftst",1)
            try writeNumber(modeKey,1)
        }
        if (try number(modeKey)) != 1, (try? raw("Ftst")) != nil {
            try writeNumber("Ftst",1); try writeNumber(modeKey,1)
        }
        guard try number(modeKey) == 1 else { throw FanError("硬件未进入手动模式") }
        try writeNumber(prefix+"Tg",rpm)
        Thread.sleep(forTimeInterval:0.3)
        guard abs((try number(prefix+"Tg"))-rpm) < max(120,rpm*0.05) else { throw FanError("硬件未接受目标转速") }
    }
    func status() -> [String:Any] {
        ["id":id,"modeKey":modeKey,"minimum":minimum,"maximum":maximum,"actual":(try? number(prefix+"Ac")) ?? NSNull(),"target":(try? number(prefix+"Tg")) ?? NSNull(),"manual":(try? number(modeKey)) == 1]
    }
}
func address() -> sockaddr_un {
    var a=sockaddr_un(); a.sun_family=sa_family_t(AF_UNIX); a.sun_len=UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of:&a.sun_path) { buffer in buffer.copyBytes(from:Array(socketPath.utf8)+[0]) }
    return a
}
func withAddress<T>(_ body:(UnsafePointer<sockaddr>,socklen_t)->T) -> T {
    var a=address()
    return withUnsafePointer(to:&a) { $0.withMemoryRebound(to:sockaddr.self,capacity:1) { body($0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
}
func json(_ v:[String:Any]) -> Data { (try? JSONSerialization.data(withJSONObject:v)) ?? Data("{}".utf8) }
func readRequest(_ fd:Int32) -> Data? {
    var timeout=timeval(tv_sec:2,tv_usec:0); setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
    var bytes=[UInt8](repeating:0,count:4096)
    let n=Darwin.read(fd,&bytes,bytes.count)
    return n>0 ? Data(bytes.prefix(n)) : nil
}
func sendData(_ fd:Int32,_ data:Data) { data.withUnsafeBytes { _ = Darwin.write(fd,$0.baseAddress,data.count) } }
let args=CommandLine.arguments
if args.count >= 3, args[1] == "client" {
    let fd=socket(AF_UNIX,SOCK_STREAM,0); defer { close(fd) }
    guard withAddress({connect(fd,$0,$1)}) == 0 else { print("{\"ok\":false,\"message\":\"需要安装 Btoll 风扇控制服务\",\"unavailable\":true}"); exit(2) }
    sendData(fd,Data(args[2].utf8))
    if let reply=readRequest(fd) { print(String(decoding:reply,as:UTF8.self)) } else { print("{\"ok\":false,\"message\":\"风扇服务响应超时\"}"); exit(3) }
    exit(0)
}
if args.count == 2, args[1] == "probe" {
    print(String(decoding:json(["fans":(0..<Int(SMC.shared.getValue("FNum") ?? 0)).compactMap{try? Fan($0).status()}]),as:UTF8.self)); exit(0)
}
guard args.count == 3, args[1] == "serve", let allowedUID=UInt32(args[2]), allowedUID > 0, geteuid() == 0 else { exit(64) }
signal(SIGPIPE,SIG_IGN)
private var shouldStop: sig_atomic_t = 0
private func stopSignal(_ signal: Int32) { shouldStop = 1 }
signal(SIGTERM,stopSignal); signal(SIGINT,stopSignal)
let count=Int(SMC.shared.getValue("FNum") ?? 0)
guard count>0,count<=4 else { exit(0) }
let fans: [Fan]
do { fans=try (0..<count).map{try Fan($0)} } catch { print(error); exit(0) }
func restore() throws {
    var failed=false
    for f in fans { do { try f.automatic() } catch { failed=true } }
    if (try? raw("Ftst")) != nil { do { try writeNumber("Ftst",0) } catch { failed=true } }
    guard !failed, fans.allSatisfy({(try? number($0.modeKey)) == 0}) else { throw FanError("恢复自动失败，将继续重试") }
}
// Always recover automatic control after a helper restart.
do { try restore() } catch { print(error) }
let fd=socket(AF_UNIX,SOCK_STREAM,0)
guard fd>=0 else { exit(67) }
unlink(socketPath)
guard withAddress({bind(fd,$0,$1)}) == 0 else { exit(68) }
chown(socketPath,allowedUID,0); chmod(socketPath,0o600)
guard listen(fd,8) == 0 else { exit(69) }
var deadline:Double?; var mode="auto"; var target:Double?
while shouldStop == 0 {
    if let until=deadline,Date().timeIntervalSince1970>=until {
        do { try restore(); deadline=nil; target=nil; mode="auto" } catch { print(error) }
    }
    var pollFD=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
    guard poll(&pollFD,1,500)>0 else { continue }
    let client=accept(fd,nil,nil); guard client>=0 else { continue }
    defer { close(client) }
    var uid:uid_t=0; var gid:gid_t=0
    guard getpeereid(client,&uid,&gid) == 0,uid==allowedUID || uid==0 else { continue }
    guard let data=readRequest(client),let request=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],let command=request["command"] as? String else { continue }
    do {
        switch command {
        case "status": break
        case "auto": try restore(); deadline=nil; target=nil; mode="auto"
        case "boost","manual":
            guard let seconds=request["seconds"] as? Double,seconds.isFinite,seconds>=1,seconds<=600 else { throw FanError("手动控制时间必须在 1 至 600 秒内") }
            let rpm=request["rpm"] as? Double
            if command == "manual" { guard let rpm,rpm.isFinite,fans.allSatisfy({rpm >= $0.minimum && rpm <= $0.maximum}) else { throw FanError("转速超出硬件范围") } }
            // Deadline is owned by root helper, independent of GUI process survival.
            deadline=Date().timeIntervalSince1970+seconds
            do { for f in fans { try f.set(command == "boost" ? f.maximum : rpm!) } }
            catch { try? restore(); deadline=Date().timeIntervalSince1970; throw error }
            mode=command; target=command == "boost" ? fans.first?.maximum : rpm
        default: throw FanError("不支持的控制命令")
        }
        var reply:[String:Any]=["ok":true,"mode":mode,"fans":fans.map{$0.status()},"backend":"bsstoll-smc","minimum":fans.map(\.minimum).max() ?? 0,"maximum":fans.map(\.maximum).min() ?? 0,"until":deadline.map{$0*1000} ?? NSNull()]
        if let target { reply["target"]=target }
        sendData(client,json(reply))
    } catch { sendData(client,json(["ok":false,"message":String(describing:error)])) }
}

try? restore()
close(fd)
unlink(socketPath)
