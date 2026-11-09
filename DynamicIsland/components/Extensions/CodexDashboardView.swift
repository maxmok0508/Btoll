import SwiftUI
import AppKit

private struct DashboardData: Decodable {
    struct Quota: Decodable { let used: Double; let reset: Double?; let observed: Double }
    struct Cards: Decodable { let count: Int; let observed: Double }
    struct Session: Decodable, Identifiable { let id: String; let title: String; let project: String; let updated: Double; let status: String; let tool: String }
    struct Thermal: Decodable { let values: [String: Double]; let observed: Double }
    struct Usage: Decodable {
        struct Summary: Decodable { let lifetimeTokens: Double?; let peakDailyTokens: Double?; let longestRunningTurnSec: Double?; let currentStreakDays: Int?; let longestStreakDays: Int? }
        struct Day: Decodable { let startDate: String; let tokens: Double }
        let summary: Summary; let dailyUsageBuckets: [Day]?; let observed: Double
    }
    struct CoreTemperatures: Decodable {
        struct Sensor: Decodable, Identifiable { let key: String; let name: String; let group: String; let value: Double; var id: String { key } }
        let cpuAverage: Double?; let cpuMaximum: Double?; let gpuAverage: Double?; let sensors: [Sensor]
    }
    let coreTemperatures: CoreTemperatures?
    struct FanControl: Decodable { let mode: String; let until: Double?; let message: String?; let unavailable: Bool?; let backend: String?; let target: Double?; let minimum: Double?; let maximum: Double? }
    let fanControl: FanControl?
    let updated: Double
    let quota: Quota?
    let resetCards: Cards?
    let activeCount: Int
    let uncertainCount: Int
    let sessions: [Session]
    let temperatures: Thermal?
    let profile: Usage?
}

struct CodexDashboardView: View {
    var temperatureOnly = false
    var onHorizontalHover: ((Bool) -> Void)? = nil
    @State private var manualRPM: Double = 5000
    @State private var selectedPage: Int? = 0
    @State private var data: DashboardData?
    @State private var error: String?
    private let mint = Color(red: 0.39, green: 0.87, blue: 0.68)
    private var stale: Bool { guard let data else { return true }; return Date().timeIntervalSince1970 * 1000 - data.updated > 30000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(temperatureOnly ? "温度" : "Codex")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer()
                Circle().fill(stale ? Color.orange : mint).frame(width: 5, height: 5)
                Text(stale ? "数据待刷新" : "实时同步").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
            HStack(spacing: 16) {
                ForEach(Array((temperatureOnly ? ["温度概览", "核心明细", "风扇控制"] : ["概览", "活动", "会话"]).enumerated()), id: \.offset) { index, title in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedPage = index }
                    } label: {
                        VStack(spacing: 5) {
                            Text(title).font(.system(size: 12, weight: selectedPage == index ? .semibold : .regular))
                                .foregroundStyle(selectedPage == index ? .white : .white.opacity(0.4))
                            Capsule().fill(selectedPage == index ? mint : .clear).frame(height: 2)
                        }.fixedSize(horizontal: true, vertical: false)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("左右滑动切换").font(.system(size: 10)).foregroundStyle(.white.opacity(0.3))
            }
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 0) {
                        if temperatureOnly {
                            temperatureOverview.frame(width:geo.size.width,alignment:.topLeading).id(0)
                            coreSensorsPanel.frame(width:geo.size.width,alignment:.topLeading).id(1)
                            fanPanel.frame(width:geo.size.width,alignment:.topLeading).id(2)
                        } else {
                            VStack(alignment:.leading,spacing:12) {
                                quotaPanel
                                Text("额度、重置卡与重置时间均来自当前账户。").font(.system(size:10)).foregroundStyle(.white.opacity(0.35))
                            }.frame(width:geo.size.width,alignment:.topLeading).id(0)
                            activityPanel.frame(width:geo.size.width,alignment:.topLeading).id(1)
                            ScrollView(.vertical) { sessionsPanel }.scrollIndicators(.hidden).frame(width:geo.size.width,height:geo.size.height).id(2)
                        }
                    }.scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id:$selectedPage)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.black)
        .environment(\.colorScheme, .dark)
        .onHover { onHorizontalHover?($0) }
        .onDisappear { onHorizontalHover?(false) }
        .task {
            while !Task.isCancelled {
                load()
                do { try await Task.sleep(for: .seconds(3)) } catch { break }
            }
        }
    }

    private func load() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AtollCodexBridge/dashboard.json")
        do { data = try JSONDecoder().decode(DashboardData.self, from: Data(contentsOf: url)); error = nil }
        catch { self.error = "等待监控服务同步" }
    }

    private var quotaPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    caption("每周额度剩余")
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(data?.quota.map { String(Int((100 - $0.used).rounded())) } ?? "—").font(.system(size: 38, weight: .semibold, design: .rounded))
                        Text("%").font(.system(size: 17)).foregroundStyle(.white.opacity(0.5))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    caption("额度重置")
                    Text(resetDate).font(.system(size: 15, weight: .medium)).monospacedDigit()
                    Text(countdown).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    caption("重置卡")
                    Text(data?.resetCards.map { "\($0.count) 张" } ?? "待同步").font(.system(size: 23, weight: .semibold, design: .rounded))
                    Text("账户可用数量").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(quotaColor).frame(width: geo.size.width * remaining)
                }
            }.frame(height: 5)
            HStack {
                Text("\(data?.activeCount ?? 0) 个会话工作中").foregroundStyle(mint)
                if let count = data?.uncertainCount, count > 0 { Text("· \(count) 个状态待确认").foregroundStyle(.orange) }
                Spacer()
                Text(data?.quota.map { "额度更新于 " + time($0.observed) } ?? (error ?? "额度待同步")).foregroundStyle(.white.opacity(0.35))
            }.font(.system(size: 10))
        }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }

    private var activityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("账户活动").font(.system(size: 12, weight: .semibold)); Spacer(); Text("Codex 个人资料").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)) }
            if let profile = data?.profile, let days = profile.dailyUsageBuckets {
                ActivityGrid(days: days.map { ($0.startDate, $0.tokens) })
                HStack(spacing: 22) {
                    stat("累计 Token", compact(profile.summary.lifetimeTokens))
                    stat("单日峰值", compact(profile.summary.peakDailyTokens))
                    stat("当前连续", profile.summary.currentStreakDays.map { "\($0) 天" } ?? "—")
                    stat("最长连续", profile.summary.longestStreakDays.map { "\($0) 天" } ?? "—")
                    stat("最长任务", profile.summary.longestRunningTurnSec.map { "\(Int($0 / 3600)) 时 \(Int($0.truncatingRemainder(dividingBy: 3600) / 60)) 分" } ?? "—")
                }
            } else {
                Text("个人资料数据暂不可用").font(.system(size: 12)).foregroundStyle(.white.opacity(0.4)).padding(.vertical, 16)
            }
        }
    }

    private var sessionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("最近会话").font(.system(size: 12, weight: .semibold)); Spacer(); Text("本机 · 最近 12 个").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)) }
            ForEach(data?.sessions ?? []) { session in
                HStack(spacing: 10) {
                    Circle().fill(session.status == "已完成" ? Color.white.opacity(0.25) : session.status == "未运行" ? Color.white.opacity(0.15) : session.status == "状态待确认" ? Color.orange : mint).frame(width: 5, height: 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(session.project + (session.tool.isEmpty ? "" : " · " + session.tool)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Text(session.status).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                    Text(time(session.updated)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.3)).frame(width: 42, alignment: .trailing)
                }.padding(.vertical, 7)
                Rectangle().fill(.white.opacity(0.06)).frame(height: 0.5)
            }
        }
    }

    private var temperatureOverview: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 20) {
                thermalStat("CPU 核心平均", data?.coreTemperatures?.cpuAverage)
                thermalStat("CPU 核心最高", data?.coreTemperatures?.cpuMaximum)
                thermalStat("GPU 平均", data?.coreTemperatures?.gpuAverage)
            }
            HStack {
                Image(systemName: "fanblades").foregroundStyle(mint)
                Text(data?.temperatures?.values["F0Ac"].map { "风扇  \(Int($0)) RPM" } ?? "风扇转速待同步").font(.system(size: 13)).monospacedDigit()
                Spacer()
                Text("AppleSMC · 实时采集").font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
            }
            Text("核心平均与最高值由本机核心区域传感器的实时读数计算。").font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
        }.padding(18).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
    }

    private var coreSensorsPanel: some View {
        VStack(alignment:.leading,spacing:10) {
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:6),spacing:8) {
                ForEach(data?.coreTemperatures?.sensors.filter { $0.group == "CPU" } ?? []) { sensor in
                    VStack(alignment:.leading,spacing:5) {
                        Text(sensorLabel(sensor.name)).font(.system(size:10)).foregroundStyle(.white.opacity(0.45))
                        Text(String(format:"%.1f°",sensor.value)).font(.system(size:20,weight:.medium,design:.rounded)).monospacedDigit()
                    }.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:9)).help(sensor.name + " · " + sensor.key)
                }
            }
            Text("本机 SMC 实测 · 一个核心区域可能有多个温度传感器").font(.system(size:10)).foregroundStyle(.white.opacity(0.35))
        }
    }

    private var fanPanel: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Image(systemName:"fanblades").font(.system(size:26)).foregroundStyle(mint)
                Text(data?.temperatures?.values["F0Ac"].map { "\(Int($0))" } ?? "—").font(.system(size:38,weight:.semibold,design:.rounded)).monospacedDigit()
                Text("RPM").font(.system(size:13)).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Text(fanStatus).font(.system(size:11)).foregroundStyle(mint)
            }
            HStack(spacing:10) {
                Button("系统自动") { setFan("auto") }.buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal,12).padding(.vertical,7).background(Color.white.opacity(0.1),in:RoundedRectangle(cornerRadius:8))
                Button("强力散热 10 分钟") { setFan("boost") }.buttonStyle(.plain).foregroundStyle(mint).padding(.horizontal,12).padding(.vertical,7).background(mint.opacity(0.12),in:RoundedRectangle(cornerRadius:8))
                Spacer()
                if data?.fanControl?.backend != "bsstoll-smc" || data?.fanControl?.unavailable == true {
                    Button("安装控制服务") { Task { await BsstollFanController.install() } }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
                }
            }
            VStack(alignment:.leading,spacing:9) {
                HStack {
                    Text("自定义转速").font(.system(size:12,weight:.semibold))
                    Text("\(Int(fanMinimum))–\(Int(fanMaximum)) RPM").font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
                    Spacer()
                    if data?.fanControl?.mode == "manual", let target=data?.fanControl?.target {
                        Text("当前目标 \(Int(target)) RPM").font(.system(size:10)).foregroundStyle(mint)
                    }
                }
                HStack(spacing:8) {
                    fanPreset("半速",fraction:0.5)
                    fanPreset("3/4 转速",fraction:0.75)
                    Spacer()
                }
                HStack(spacing:12) {
                    Slider(value:Binding(get:{ min(fanMaximum,max(fanMinimum,manualRPM)) },set:{ manualRPM=$0 }),in:fanMinimum...fanMaximum,step:50).tint(mint)
                    TextField("RPM",value:$manualRPM,format:.number.grouping(.never).precision(.fractionLength(0)))
                        .textFieldStyle(.plain).font(.system(size:13,design:.monospaced)).multilineTextAlignment(.trailing)
                        .frame(width:60).padding(.horizontal,9).padding(.vertical,7)
                        .background(.white.opacity(0.08),in:RoundedRectangle(cornerRadius:7))
                        .onSubmit { applyCustomFan() }
                        .accessibilityLabel("自定义风扇转速")
                    Text("RPM").font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
                    Button("应用自定义转速") { applyCustomFan() }
                        .buttonStyle(.plain).font(.system(size:11,weight:.medium)).foregroundStyle(customRPMIsValid ? mint : .gray)
                        .padding(.horizontal,12).padding(.vertical,8).background(mint.opacity(customRPMIsValid ? 0.12 : 0.03),in:RoundedRectangle(cornerRadius:8))
                        .disabled(!customRPMIsValid)
                }
            }
            Text("自定义转速保持 10 分钟后恢复系统自动；可随时点击“系统自动”提前结束。").font(.system(size:10)).foregroundStyle(.white.opacity(0.35))
        }.padding(16).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
            .disabled(data?.temperatures?.values["FNum"] == 0)
            .overlay(alignment:.bottom) {
                if data?.temperatures?.values["FNum"] == 0 {
                    Text("本机为无风扇机型，无需风扇控制").font(.system(size:11)).padding(10).background(.black,in:Capsule())
                }
            }
    }

    private func fanPreset(_ title:String,fraction:Double) -> some View {
        let rpm=max(fanMinimum,min(fanMaximum,(fanMaximum*fraction).rounded()))
        let selected=data?.fanControl?.mode == "manual" && abs((data?.fanControl?.target ?? -1)-rpm) < 1
        return Button {
            manualRPM=rpm
            applyCustomFan()
        } label: {
            HStack(spacing:6) {
                Text(title).font(.system(size:11,weight:.medium))
                Text("\(Int(rpm)) RPM").font(.system(size:10,design:.monospaced)).opacity(0.6)
            }.padding(.horizontal,12).padding(.vertical,7)
                .foregroundStyle(selected ? mint : .white)
                .background(selected ? mint.opacity(0.15) : .white.opacity(0.07),in:RoundedRectangle(cornerRadius:8))
        }.buttonStyle(.plain)
    }
    private var customRPMIsValid: Bool { manualRPM.isFinite && manualRPM >= fanMinimum && manualRPM <= fanMaximum }
    private func applyCustomFan() {
        guard customRPMIsValid else { return }
        Task { await BsstollFanController.setFan("manual",rpm:manualRPM.rounded()) }
    }
    private var fanMinimum: Double { data?.fanControl?.minimum ?? data?.temperatures?.values["F0Mn"] ?? 2000 }
    private var fanMaximum: Double { max(fanMinimum+1,data?.fanControl?.maximum ?? data?.temperatures?.values["F0Mx"] ?? 8250) }

    private func sensorLabel(_ name: String) -> String {
        name.replacingOccurrences(of:"CPU super core ",with:"超核区 ").replacingOccurrences(of:"CPU performance core ",with:"性能区 ").replacingOccurrences(of:"CPU efficiency core ",with:"能效区 ")
    }
    private var fanStatus: String {
        guard let state=data?.fanControl else { return "系统自动控制 · 可随时手动切换" }
        if state.mode == "error" { return state.message ?? "风扇控制失败" }
        if ["boost","manual"].contains(state.mode), let until=state.until {
            let minutes=max(0,Int(ceil((until/1000-Date().timeIntervalSince1970)/60)))
            return "\(state.mode == "boost" ? "强力散热" : "手动转速") · \(minutes) 分钟后恢复自动"
        }
        if state.mode == "starting" { return "正在切换风扇模式…" }
        return "系统自动控制"
    }
    private func setFan(_ mode: String) {
        Task { @MainActor in await BsstollFanController.setFan(mode) }
    }

    private func thermalStat(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) { caption(title); Text(value.map { String(format: "%.1f°", $0) } ?? "—").font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit() }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func mean(_ prefix: String) -> Double? { let values = data?.temperatures?.values.filter { $0.key.hasPrefix(prefix) && $0.value > 5 && $0.value < 125 }.map(\.value) ?? []; return values.isEmpty ? nil : values.reduce(0,+) / Double(values.count) }
    private func caption(_ text: String) -> some View { Text(text).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)) }
    private func stat(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 4) { Text(value).font(.system(size: 14, weight: .semibold, design: .rounded)); caption(title) }.frame(maxWidth: .infinity, alignment: .leading) }
    private var remaining: Double { max(0, min(1, 1 - (data?.quota?.used ?? 100) / 100)) }
    private var quotaColor: Color { remaining > 0.5 ? mint : remaining > 0.2 ? .orange : .red }
    private var resetDate: String { guard let reset = data?.quota?.reset else { return "待同步" }; let f = DateFormatter(); f.locale = Locale(identifier:"zh_CN"); f.timeZone = TimeZone(identifier:"Asia/Shanghai"); f.dateFormat = "M月d日 HH:mm"; return f.string(from: Date(timeIntervalSince1970:reset)) }
    private var countdown: String { guard let reset = data?.quota?.reset else { return "" }; let minutes = max(0, Int((reset-Date().timeIntervalSince1970)/60)); return "还有 \(minutes/1440) 天 \(minutes%1440/60) 时 \(minutes%60) 分" }
    private func time(_ milliseconds: Double) -> String { let f=DateFormatter(); f.dateFormat="HH:mm"; f.timeZone=TimeZone(identifier:"Asia/Shanghai"); return f.string(from:Date(timeIntervalSince1970:milliseconds/1000)) }
    private func compact(_ value: Double?) -> String { guard let value else { return "—" }; return value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) }
}

private struct ActivityGrid: View {
    let days: [(String, Double)]
    private let calendar: Calendar = { var c=Calendar(identifier:.gregorian); c.timeZone=TimeZone(identifier:"Asia/Shanghai")!; return c }()
    private var buckets: [String:Double] { Dictionary(days, uniquingKeysWith: max) }
    private var dates: [Date] {
        let today=calendar.startOfDay(for:Date()); let start=calendar.date(byAdding:.day,value:-363,to:today)!
        let aligned=calendar.date(byAdding:.day,value:-(calendar.component(.weekday,from:start)-1),to:start)!
        return (0..<371).compactMap { calendar.date(byAdding:.day,value:$0,to:aligned) }
    }
    private func key(_ date: Date) -> String { let c=calendar.dateComponents([.year,.month,.day],from:date); return String(format:"%04d-%02d-%02d",c.year ?? 0,c.month ?? 0,c.day ?? 0) }
    private func fill(_ date: Date, values: [String:Double], sorted: [Double]) -> Color {
        guard date <= Date() else { return .clear }
        guard let value=values[key(date)] else { return .white.opacity(0.055) }
        if value<=0 { return .white.opacity(0.075) }
        let rank=sorted.firstIndex(where: { $0 >= value }) ?? 0
        let bucket=min(3, rank * 4 / max(1,sorted.count))
        let level=Double(bucket+1) / 4
        return Color(red:0.18,green:0.78,blue:0.49).opacity(level)
    }
    var body: some View {
        let allDates=dates
        let values=buckets
        let sorted=days.map(\.1).filter { $0 > 0 }.sorted()
        VStack(alignment:.leading,spacing:5) {
            GeometryReader { geo in
                let cell=max(4,(geo.size.width-52*3)/53)
                HStack(alignment:.top,spacing:3) {
                    ForEach(0..<53,id:\.self) { week in
                        VStack(spacing:3) {
                            ForEach(0..<7,id:\.self) { day in
                                let date=allDates[week*7+day]
                                RoundedRectangle(cornerRadius:2).fill(fill(date,values:values,sorted:sorted)).frame(width:cell,height:cell)
                                    .help("\(key(date)) · \(values[key(date)].map{Int($0).formatted()} ?? "无返回记录") Token")
                            }
                        }
                    }
                }
            }.frame(height:105)
            HStack { Text("过去一年 · 按每日 Token 用量"); Spacer(); Text("少"); ForEach(0..<4) { i in RoundedRectangle(cornerRadius:1).fill(Color.green.opacity(Double(i+1)/4)).frame(width:8,height:8) }; Text("多") }.font(.system(size:9)).foregroundStyle(.white.opacity(0.35))
        }
    }
}

func customAtollDashboardHeight(id: String, bundleIdentifier: String) -> CGFloat? {
    guard bundleIdentifier == "local.codex.atoll-status" else { return nil }
    if id == "codex-monitor" { return 380 }
    if id == "hardware-temperature" { return 380 }
    return nil
}
