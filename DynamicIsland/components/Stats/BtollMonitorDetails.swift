import SwiftUI
import AppKit

struct BtollEnergyCard: View {
    let snapshot: BtollSystemSnapshot
    let coreTemperature: Double?
    private let mint=Color(red:0.39,green:0.87,blue:0.68)
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("电源与温度").font(.system(size:12,weight:.semibold)).foregroundStyle(mint)
            HStack(spacing:20) {
                BtollTemperatureRing(title:"CPU 核心平均",value:coreTemperature,size:72)
                if snapshot.power.present { BtollTemperatureRing(title:"电池温度",value:snapshot.power.temperature,size:72) }
            }
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:14) {
                metric("系统热压力",thermalText)
                metric("低电量模式",ProcessInfo.processInfo.isLowPowerModeEnabled ? "已开启" : "关闭")
                if snapshot.power.present {
                    metric("电量",snapshot.power.percentage.map { String(format:"%.0f%%",$0) } ?? "—")
                    metric("供电",snapshot.power.pluggedIn ? (snapshot.power.charging ? "充电中" : "外接电源") : "使用电池")
                    metric("电池端功率",snapshot.power.batteryWatts.map { String(format:"%.1f W",abs($0)) } ?? "不可用")
                    metric("电池健康",snapshot.power.health.map { String(format:"%.0f%%",$0) } ?? "不可用")
                    metric("循环次数",snapshot.power.cycles.map(String.init) ?? "不可用")
                }
            }
            if snapshot.power.present {
                Text("电池端功率是电池充放电功率，不代表整机或插座功耗。").font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
            }
            Divider().overlay(.white.opacity(0.08))
            HStack {
                Text("正在阻止休眠").font(.system(size:12,weight:.semibold))
                Spacer()
                Text(snapshot.awakeAvailable ? "\(snapshot.awake.count) 项" : "等待采集").font(.system(size:10)).foregroundStyle(.white.opacity(0.45))
            }
            if snapshot.awakeAvailable && snapshot.awake.isEmpty {
                Text("未发现阻止闲置休眠的进程").font(.system(size:11)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(snapshot.awake) { item in
                HStack(alignment:.top,spacing:10) {
                    Image(nsImage:NSRunningApplication(processIdentifier:item.pid)?.icon ?? NSImage(systemSymbolName:"app",accessibilityDescription:nil)!).resizable().frame(width:24,height:24)
                    VStack(alignment:.leading,spacing:3) {
                        Text(item.name).font(.system(size:11,weight:.medium))
                        Text(item.reason).font(.system(size:10)).foregroundStyle(.white.opacity(0.45)).lineLimit(2).help(item.reason)
                    }
                    Spacer(minLength:4)
                    Text("PID \(item.pid)").font(.system(size:9)).foregroundStyle(.white.opacity(0.35))
                }
            }
        }.padding(16).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
    }
    private var thermalText:String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:return "正常"
        case .fair:return "升高"
        case .serious:return "较高"
        case .critical:return "严重"
        @unknown default:return "不可用"
        }
    }
    private func metric(_ title:String,_ value:String)->some View {
        VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:10)).foregroundStyle(.white.opacity(0.45));Text(value).font(.system(size:13,weight:.medium,design:.rounded)).monospacedDigit() }.frame(maxWidth:.infinity,alignment:.leading)
    }
}

struct BtollProcessList: View {
    let processes: [ProcessStats]
    @State private var query=""
    var initialSorting=0
    @State private var sorting=0
    @State private var limit=20
    private var filtered: [ProcessStats] {
        let filtered=processes.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.pid).contains(query) }
        return filtered.sorted { sorting == 1 ? $0.memoryUsage > $1.memoryUsage : $0.cpuUsage > $1.cpuUsage }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("所有进程").font(.system(size:12,weight:.semibold))
                Text("\(processes.count)").font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Picker("排序",selection:$sorting) { Text("CPU").tag(0);Text("内存").tag(1) }.pickerStyle(.segmented).labelsHidden().frame(width:130)
            }
            TextField("搜索应用、进程或 PID",text:$query).textFieldStyle(.roundedBorder).font(.system(size:11))
            HStack { Text("进程");Spacer();Text("CPU").frame(width:65,alignment:.trailing);Text("内存").frame(width:78,alignment:.trailing) }.font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
            LazyVStack(spacing:10) {
                ForEach(Array(filtered.prefix(limit)),id:\.pid) { process in
                    HStack(spacing:9) {
                        Image(nsImage:process.icon ?? NSImage(systemSymbolName:"app",accessibilityDescription:nil)!).resizable().frame(width:24,height:24)
                        VStack(alignment:.leading,spacing:2) {
                            Text(process.name).font(.system(size:11,weight:.medium)).lineLimit(1).help(process.name)
                            Text("PID \(process.pid)").font(.system(size:9)).foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer(minLength:4)
                        Text(process.cpuUsageString).frame(width:65,alignment:.trailing)
                        Text(process.memoryUsageString).frame(width:78,alignment:.trailing)
                    }.font(.system(size:11,design:.rounded)).monospacedDigit()
                }
            }
            if filtered.isEmpty { Text(query.isEmpty ? "等待进程采样…" : "没有匹配的进程").font(.system(size:11)).foregroundStyle(.white.opacity(0.45)) }
            if filtered.count>limit { Button("显示更多（剩余 \(filtered.count-limit)）") { limit += 50 }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(.mint) }
            Text("进程 CPU 以单核 100% 计，多线程进程可以超过 100%。内存按可读取的驻留内存统计。").font(.system(size:10)).foregroundStyle(.white.opacity(0.35))
        }.padding(16).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
            .onAppear { sorting=initialSorting }
            .onChange(of:query) { _,_ in limit=20 }.onChange(of:sorting) { _,_ in limit=20 }
    }
}

struct BtollTrafficList: View {
    let title:String
    let items:[BtollTraffic]
    let processes:[ProcessStats]
    let network:Bool
    let available:Bool
    @State private var expanded=false
    private struct AppRow:Identifiable {
        let id:String;let name:String;let icon:NSImage?;var incoming:Double?;var outgoing:Double?;var count:Int
    }
    private var rows:[AppRow] {
        let metadata=Dictionary(processes.map { ($0.pid,$0) },uniquingKeysWith:{ a,_ in a })
        var grouped:[String:AppRow]=[:]
        for item in items {
            let process=metadata[item.pid]
            let name=process?.name ?? item.name
            let key=name
            if var row=grouped[key] {
                if let n=item.incoming { row.incoming=(row.incoming ?? 0)+n }
                if let n=item.outgoing { row.outgoing=(row.outgoing ?? 0)+n }
                row.count += 1;grouped[key]=row
            } else { grouped[key]=AppRow(id:key,name:name,icon:process?.icon,incoming:item.incoming,outgoing:item.outgoing,count:1) }
        }
        return grouped.values.sorted { a,b in
            let x=network ? (a.incoming ?? 0)+(a.outgoing ?? 0) : a.outgoing ?? 0
            let y=network ? (b.incoming ?? 0)+(b.outgoing ?? 0) : b.outgoing ?? 0
            return x==y ? a.name.localizedStandardCompare(b.name) == .orderedAscending : x>y
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text(title).font(.system(size:12,weight:.semibold));Spacer();Text("按应用汇总").font(.system(size:10)).foregroundStyle(.white.opacity(0.4)) }
            HStack { Text("应用");Spacer();Text(network ? "下载" : "读取").frame(width:90,alignment:.trailing);Text(network ? "上传" : "写入").frame(width:90,alignment:.trailing) }.font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
            if !available { Text(network ? "网络进程数据不可用或正在首次采样" : "等待两次磁盘采样，部分进程可能受系统权限限制").font(.system(size:11)).foregroundStyle(.white.opacity(0.45)) }
            ForEach(Array(rows.prefix(expanded ? rows.count : 6))) { item in
                HStack(spacing:9) {
                    Image(nsImage:item.icon ?? NSImage(systemSymbolName:"app",accessibilityDescription:nil)!).resizable().frame(width:24,height:24)
                    Text(item.name).font(.system(size:11)).lineLimit(1).help(item.name)
                    if item.count>1 { Text("\(item.count)").font(.system(size:9)).foregroundStyle(.white.opacity(0.4)) }
                    Spacer(minLength:4)
                    Text(rate(item.incoming)).frame(width:90,alignment:.trailing)
                    Text(rate(item.outgoing)).frame(width:90,alignment:.trailing)
                }.font(.system(size:11,design:.rounded)).monospacedDigit()
            }
            if rows.count>6 { Button(expanded ? "收起" : "查看全部 \(rows.count) 个应用") { expanded.toggle() }.buttonStyle(.plain).font(.system(size:11)).foregroundStyle(.mint) }
            Text(network ? "应用流量约 10 秒更新。读取 macOS 网络进程计数；VPN、代理或系统进程会影响归属，不能与网卡流量直接相加。" : "按可读取的进程物理磁盘 I/O 计数采样，按写入速率排序；缓存写入与系统总量口径不同。").font(.system(size:10)).foregroundStyle(.white.opacity(0.35))
        }.padding(16).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
    }
    private func rate(_ value:Double?)->String { guard let value else { return "—" };return ByteCountFormatter.string(fromByteCount:Int64(min(Double(Int64.max),max(0,value))),countStyle:.file)+"/s" }
}

struct BtollPageHeightKey:PreferenceKey {
    static var defaultValue:[Int:CGFloat]=[:]
    static func reduce(value:inout [Int:CGFloat],nextValue:()->[Int:CGFloat]) { value.merge(nextValue(),uniquingKeysWith:{ _,new in new }) }
}
struct BtollPageMeasure:View {
    let page:Int
    var onHeight:((CGFloat)->Void)? = nil
    var body:some View {
        GeometryReader { geo in
            Color.clear.onAppear { onHeight?(geo.size.height) }
                .onChange(of:geo.size.height) { _,height in onHeight?(height) }
        }
    }
}
struct BtollTemperatureRing:View {
    let title:String
    let value:Double?
    var size:CGFloat=84
    var body:some View {
        let color:Color=(value ?? 0)>=90 ? .red : (value ?? 0)>=75 ? .orange : .mint
        VStack(spacing:10) {
            ZStack {
                Circle().stroke(.white.opacity(0.08),lineWidth:7)
                Circle().trim(from:0,to:min(1,max(0,(value ?? 0)/120))).stroke(color,style:StrokeStyle(lineWidth:7,lineCap:.round)).rotationEffect(.degrees(-90))
                VStack(spacing:1) {
                    Text(value.map { String(format:"%.1f",$0) } ?? "—").font(.system(size:size>70 ? 22 : 15,weight:.semibold,design:.rounded)).monospacedDigit()
                    Text("°C").font(.system(size:9)).foregroundStyle(.white.opacity(0.45))
                }
            }.frame(width:size,height:size).padding(4)
            Text(title).font(.system(size:10,weight:.medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(2).multilineTextAlignment(.center)
        }.frame(maxWidth:.infinity).help("温度环范围 0–120°C；数值为实测温度，不是占用率。 ").accessibilityLabel(title).accessibilityValue(value.map { String(format:"%.1f 摄氏度",$0) } ?? "不可用")
    }
}
