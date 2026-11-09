/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import Defaults

// Graph data protocol for unified interface
protocol GraphData {
    var title: String { get }
    var color: Color { get }
    var icon: String { get }
    var type: GraphType { get }
    var rankingType: ProcessRankingType? { get }
}

enum GraphType {
    case single
    case dual
}

// Single value graph data
struct SingleGraphData: GraphData {
    let title: String
    let value: String
    let data: [Double]
    let color: Color
    let icon: String
    let type: GraphType = .single
    let rankingType: ProcessRankingType?
}

// Dual value graph data (for network/disk)
struct DualGraphData: GraphData {
    let title: String
    let positiveValue: String
    let negativeValue: String
    let positiveData: [Double]
    let negativeData: [Double]
    let positiveColor: Color
    let negativeColor: Color
    let color: Color // Primary color for the component
    let icon: String
    let type: GraphType = .dual
    let rankingType: ProcessRankingType?
}

struct NotchStatsView: View {
    @ObservedObject private var stats = StatsManager.shared
    @EnvironmentObject private var vm: DynamicIslandViewModel
    @State private var page: Int? = 0
    @State private var scrollToken = UUID()
    @State private var detail: ProcessRankingType = .cpu
    @State private var showingDetail = false
    @State private var systemSnapshot = BtollSystemSnapshot()
    @State private var sampler = BtollSystemSampler()
    private let mint = Color(red:0.39,green:0.87,blue:0.68)
    private let titles = ["概览", "处理器", "内存与 I/O"]
    private var ready: Bool { stats.lastUpdated != .distantPast }
    private var gpuValue: Double? { ready && stats.gpuDevices.contains(where: { $0.utilization != nil }) ? stats.gpuUsage : nil }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("性能").font(.system(size:16,weight:.semibold,design:.rounded))
                Spacer()
                Circle().fill(stats.isMonitoring ? mint : .orange).frame(width:5,height:5)
                Text(stats.isMonitoring ? "实时采集" : "等待采集").font(.system(size:10)).foregroundStyle(.white.opacity(0.45))
            }
            HStack(spacing:16) {
                ForEach(0..<3,id:\.self) { index in
                    Button { withAnimation(.easeInOut(duration:0.2)) { page=index } } label: {
                        VStack(spacing:5) {
                            Text(titles[index]).font(.system(size:12,weight:page == index ? .semibold : .regular)).foregroundStyle(.white.opacity(page == index ? 1 : 0.4))
                            Capsule().fill(page == index ? mint : .clear).frame(height:2)
                        }.fixedSize(horizontal:true,vertical:false)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Text("左右切页 · 上下查看详情").font(.system(size:10)).foregroundStyle(.white.opacity(0.3))
            }
            GeometryReader { geo in
                ScrollView(.horizontal) {
                    HStack(alignment:.top,spacing:0) {
                        ScrollView(.vertical) { overview }.scrollIndicators(.visible).frame(width:geo.size.width,height:geo.size.height).id(0)
                        ScrollView(.vertical) { processors }.scrollIndicators(.visible).frame(width:geo.size.width,height:geo.size.height).id(1)
                        ScrollView(.vertical) { memoryAndIO }.scrollIndicators(.visible).frame(width:geo.size.width,height:geo.size.height).id(2)
                    }.scrollTargetLayout()
                }.scrollIndicators(.hidden).scrollTargetBehavior(.paging).scrollPosition(id:$page)
            }
        }.foregroundStyle(.white).padding(16).background(.black)
            .task {
                while !Task.isCancelled {
                    if stats.isMonitoring {
                        let processes=stats.allProcesses.map { ($0.pid,$0.name) }
                        let snapshot=await sampler.sample(processes:processes)
                        if !Task.isCancelled { systemSnapshot=snapshot }
                    }
                    do { try await Task.sleep(for:.seconds(5)) } catch { return }
                }
            }
            .onHover { vm.setScrollGestureSuppression($0,token:scrollToken) }
            .onDisappear { vm.setScrollGestureSuppression(false,token:scrollToken); vm.isStatsPopoverActive = false; showingDetail = false }
            .onChange(of:showingDetail) { _, value in vm.isStatsPopoverActive = value }
            .popover(isPresented:$showingDetail) {
                RankedProcessPopover(rankingType:detail,onHoverChange:{ vm.isStatsPopoverActive = showingDetail || $0 })
                    .foregroundStyle(.primary)
            }
    }
    private var overview: some View {
        VStack(spacing:12) {
            HStack(spacing:12) {
                Button { openDetail(.cpu) } label: { gaugeCard("CPU",value:ready ? stats.cpuUsage : nil,color:mint,subtitle:"点击查看进程与负载") }.buttonStyle(.plain)
                Button { openDetail(.gpu) } label: { gaugeCard("GPU",value:gpuValue,color:.cyan,subtitle:"点击查看 GPU 详情") }.buttonStyle(.plain)
                Button { openDetail(.memory) } label: { gaugeCard("内存",value:ready ? stats.memoryUsage : nil,color:.purple,subtitle:"点击查看内存详情") }.buttonStyle(.plain)
            }
            HStack(spacing:12) {
                mini("逻辑核心",ready ? String(stats.cpuCoreUsage.count) : "—")
                mini("1 分钟负载",ready ? String(format:"%.2f",stats.cpuLoadAverage.oneMinute) : "—")
                mini("系统已运行",uptimeText)
            }.padding(14).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
            BtollEnergyCard(snapshot:systemSnapshot,coreTemperature:stats.cpuTemperature.celsius)
        }.padding(.bottom,6)
    }
    private var processors: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(spacing:12) {
                infoBlock("CPU 分配",rows:[("用户",percent(stats.cpuBreakdown.user)),("系统",percent(stats.cpuBreakdown.system)),("空闲",percent(stats.cpuBreakdown.idle))])
                infoBlock("平均负载 · 非百分比",rows:[("1 分钟",number(stats.cpuLoadAverage.oneMinute)),("5 分钟",number(stats.cpuLoadAverage.fiveMinutes)),("15 分钟",number(stats.cpuLoadAverage.fifteenMinutes))])
            }
            VStack(alignment:.leading,spacing:14) {
                HStack {
                    Text("CPU 核心实时占用").font(.system(size:12,weight:.semibold))
                    Spacer()
                    Text("\(stats.cpuCoreUsage.count) 个逻辑核心").font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
                }
                if stats.cpuCoreUsage.isEmpty {
                    Text("等待核心数据…").font(.system(size:11)).foregroundStyle(.white.opacity(0.4))
                } else {
                    LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:12),count:8),spacing:14) {
                        ForEach(stats.cpuCoreUsage) { core in
                            VStack(spacing:6) {
                                ring(core.usage,color:mint,size:48,lineWidth:5,fontSize:11)
                                Text("核心 \(core.id+1)").font(.system(size:9)).foregroundStyle(.white.opacity(0.45))
                            }
                        }
                    }.padding(.vertical,4)
                }
            }.padding(16).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
            infoBlock("CPU 频率",rows:[("整体",ghz(stats.cpuFrequency?.overallGHz)),("能效核心",ghz(stats.cpuFrequency?.eCoreGHz)),("性能核心",ghz(stats.cpuFrequency?.pCoreGHz))])
            if stats.gpuDevices.isEmpty {
                infoBlock("GPU",rows:[("采集状态","暂无设备明细")])
            } else {
                ForEach(stats.gpuDevices) { gpu in
                    infoBlock(gpu.formattedVendorModel,rows:[("占用率",gpu.utilization.map { String(format:"%.1f%%",$0) } ?? "暂无数据"),("渲染 / 平铺",optionalPercent(gpu.renderUtilization)+" / "+optionalPercent(gpu.tilerUtilization)),("核心 / 频率",(gpu.cores.map(String.init) ?? "—")+" / "+(gpu.coreClock.map { "\($0) MHz" } ?? "—"))])
                }
            }
            BtollProcessList(processes:stats.allProcesses)
            detailButton("处理器详细面板",type:.cpu)
        }.padding(.bottom,6)
    }
    private var memoryAndIO: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.top,spacing:12) {
                VStack(spacing:9) {
                    ring(ready ? stats.memoryUsage : nil,color:.purple,size:84,lineWidth:8,fontSize:22)
                    Text("内存使用").font(.system(size:12,weight:.semibold))
                    Text(bytes(stats.memoryBreakdown.usedBytes)+" / "+bytes(stats.memoryBreakdown.totalBytes)).font(.system(size:10)).foregroundStyle(.white.opacity(0.45))
                }.frame(maxWidth:.infinity).padding(16).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
                infoBlock("内存与交换",rows:[("内存压力",pressureText),("空闲",bytes(stats.memoryBreakdown.freeBytes)),("交换已用 / 总量",bytes(stats.memoryBreakdown.swap.usedBytes)+" / "+bytes(stats.memoryBreakdown.swap.totalBytes))])
            }
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                mini("应用内存",bytes(stats.memoryBreakdown.appBytes))
                mini("联动内存",bytes(stats.memoryBreakdown.wiredBytes))
                mini("压缩内存",bytes(stats.memoryBreakdown.compressedBytes))
                mini("文件缓存",bytes(stats.memoryBreakdown.cacheBytes))
                mini("活跃内存",bytes(stats.memoryBreakdown.activeBytes))
                mini("非活跃内存",bytes(stats.memoryBreakdown.inactiveBytes))
            }.padding(14).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
            detailButton("内存详细面板",type:.memory)
            Button { openDetail(.network) } label: {
                rateCard("网络 · 点击查看详情",left:"下载",leftValue:stats.networkDownloadString,right:"上传",rightValue:stats.networkUploadString)
            }.buttonStyle(.plain)
            BtollTrafficList(title:"应用网络流量",items:systemSnapshot.network,processes:stats.allProcesses,network:true,available:systemSnapshot.networkAvailable)
            infoBlock("网络采集累计",rows:[("下载",megabytes(stats.networkTotals.downloadedMB)),("上传",megabytes(stats.networkTotals.uploadedMB))])
            ForEach(stats.networkInterfaces.filter { $0.isActive }) { interface in
                infoBlock(interface.displayName+" · "+interface.name,rows:[("下载",StatsFormatting.throughput(interface.currentDownload)),("上传",StatsFormatting.throughput(interface.currentUpload))])
            }
            Button { openDetail(.disk) } label: {
                rateCard("磁盘 I/O · 点击查看详情",left:"读取",leftValue:stats.diskReadString,right:"写入",rightValue:stats.diskWriteString)
            }.buttonStyle(.plain)
            BtollTrafficList(title:"谁在写入磁盘",items:systemSnapshot.disk,processes:stats.allProcesses,network:false,available:!systemSnapshot.disk.isEmpty)
            infoBlock("磁盘采集累计",rows:[("读取",megabytes(stats.diskTotals.readMB)),("写入",megabytes(stats.diskTotals.writtenMB))])
            ForEach(stats.diskDevices) { disk in
                HStack(spacing:18) {
                    ring(disk.totalBytes > 0 ? disk.usagePercentage : nil,color:.cyan,size:56,lineWidth:5,fontSize:13)
                    infoBlock(disk.name,rows:[("已用 / 总量",bytes(disk.usedBytes)+" / "+bytes(disk.totalBytes)),("剩余",bytes(disk.freeBytes))])
                }.padding(10).background(.white.opacity(0.025),in:RoundedRectangle(cornerRadius:12))
            }
            Text("部分内存分类相互重叠，请勿直接相加。频率或 GPU 项目未公开时显示暂无数据。").font(.system(size:10)).foregroundStyle(.white.opacity(0.35))
        }.padding(.bottom,6)
    }
    private func openDetail(_ type:ProcessRankingType) { detail = type; vm.isStatsPopoverActive = true; showingDetail = true }
    private func detailButton(_ title:String,type:ProcessRankingType) -> some View {
        Button { openDetail(type) } label: {
            HStack { Text(title); Spacer(); Image(systemName:"arrow.up.right") }.font(.system(size:11,weight:.medium)).foregroundStyle(mint).padding(12)
        }.buttonStyle(.plain).background(mint.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
    }
    private func mini(_ title:String,_ value:String) -> some View {
        VStack(alignment:.leading,spacing:5) { Text(title).font(.system(size:10)).foregroundStyle(.white.opacity(0.45)); Text(value).font(.system(size:13,weight:.medium,design:.rounded)).monospacedDigit() }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func infoBlock(_ title:String,rows:[(String,String)]) -> some View {
        VStack(alignment:.leading,spacing:9) {
            Text(title).font(.system(size:11,weight:.semibold)).foregroundStyle(mint).lineLimit(2)
            ForEach(rows.indices,id:\.self) { index in
                HStack(alignment:.firstTextBaseline) {
                    Text(rows[index].0).font(.system(size:10)).foregroundStyle(.white.opacity(0.45))
                    Spacer(minLength:8)
                    Text(rows[index].1).font(.system(size:11,weight:.medium,design:.rounded)).monospacedDigit().multilineTextAlignment(.trailing)
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading).padding(14).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
    private var pressureText: String {
        guard ready, stats.memoryBreakdown.totalBytes > 0, stats.memoryBreakdown.pressure.rawValue > 0 else { return "暂无数据" }
        switch stats.memoryBreakdown.pressure.level { case .normal:return "正常"; case .warning:return "偏高"; case .critical:return "高" }
    }
    private var uptimeText: String { guard ready else { return "—" }; let minutes=Int(stats.cpuUptime/60); return "\(minutes/1440) 天 \(minutes%1440/60) 小时 \(minutes%60) 分" }
    private func percent(_ value:Double) -> String { ready ? String(format:"%.1f%%",value) : "—" }
    private func number(_ value:Double) -> String { ready ? String(format:"%.2f",value) : "—" }
    private func optionalPercent(_ value:Double?) -> String { value.map { String(format:"%.1f%%",$0) } ?? "暂无数据" }
    private func ghz(_ value:Double?) -> String { guard ready,let value,value.isFinite,value>0 else { return "暂无数据" };return String(format:"%.2f GHz",value) }
    private func megabytes(_ value:Double) -> String { ready ? bytes(UInt64(max(0,value)*1024*1024)) : "—" }
    private func gaugeCard(_ title:String,value:Double?,color:Color,subtitle:String) -> some View {
        VStack(spacing:13) {
            ring(value,color:color,size:84,lineWidth:8,fontSize:22)
            Text(title).font(.system(size:14,weight:.semibold))
            Text(subtitle).font(.system(size:10)).foregroundStyle(.white.opacity(0.4))
        }.frame(maxWidth:.infinity).padding(.vertical,16).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:14))
    }
    private func ring(_ value:Double?,color:Color,size:CGFloat,lineWidth:CGFloat,fontSize:CGFloat) -> some View {
        let fraction=min(1,max(0,(value ?? 0)/100))
        return ZStack {
            Circle().stroke(.white.opacity(0.08),lineWidth:lineWidth)
            Circle().trim(from:0,to:fraction).stroke(color,style:StrokeStyle(lineWidth:lineWidth,lineCap:.round)).rotationEffect(.degrees(-90))
            Text(value.map { String(format:"%.0f%%",$0) } ?? "—").font(.system(size:fontSize,weight:.semibold,design:.rounded)).monospacedDigit()
        }.frame(width:size,height:size).padding(lineWidth/2).animation(.easeOut(duration:0.25),value:fraction)
            .accessibilityValue(value.map { String(format:"%.0f%%",$0) } ?? "暂无数据")
    }
    private func rateCard(_ title:String,left:String,leftValue:String,right:String,rightValue:String) -> some View {
        VStack(alignment:.leading,spacing:9) {
            Text(title).font(.system(size:11,weight:.semibold)).foregroundStyle(mint)
            HStack {
                VStack(alignment:.leading,spacing:3) { Text(ready ? leftValue : "—").font(.system(size:15,weight:.medium,design:.rounded)); Text(left).font(.system(size:9)).foregroundStyle(.white.opacity(0.4)) }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.leading,spacing:3) { Text(ready ? rightValue : "—").font(.system(size:15,weight:.medium,design:.rounded)); Text(right).font(.system(size:9)).foregroundStyle(.white.opacity(0.4)) }.frame(maxWidth:.infinity,alignment:.leading)
            }
        }.padding(14).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:12))
    }
    private func bytes(_ value:UInt64) -> String { value == 0 && !ready ? "—" : ByteCountFormatter.string(fromByteCount:Int64(clamping:value),countStyle:.memory) }
}

// Unified Stats Card Component - handles both single and dual data types, matches boring.notch sizing
struct UnifiedStatsCard: View {
    let graphData: GraphData
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 3) { // Match boring.notch spacing
            // Header - consistent across all card types
            HStack(spacing: 4) {
                Image(systemName: graphData.icon)
                    .foregroundStyle(graphData.color)
                    .font(.caption) // Match boring.notch font size
                
                Text(graphData.title)
                    .font(.caption) // Match boring.notch font size
                    .fontWeight(.medium)
                    .foregroundStyle(Color.white.opacity(0.8))
                
                Spacer()
                
                // Show value on right for single graphs like boring.notch
                if let singleData = graphData as? SingleGraphData {
                    Text(singleData.value)
                        .font(.caption) // Match boring.notch font size
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
            
            // Values section for dual graphs only
            if let dualData = graphData as? DualGraphData {
                HStack(spacing: 6) {
                    Text(dualData.positiveValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(dualData.positiveColor)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.45))
                    
                    Text(dualData.negativeValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(dualData.negativeColor)
                }
                .frame(height: 18) // Smaller for dual graphs
            }
            
            // Graph section - adapts based on graph type
            Group {
                if let singleData = graphData as? SingleGraphData {
                    MiniGraph(data: singleData.data, color: singleData.color)
                } else if let dualData = graphData as? DualGraphData {
                    DualQuadrantGraph(
                        positiveData: dualData.positiveData,
                        negativeData: dualData.negativeData,
                        positiveColor: dualData.positiveColor,
                        negativeColor: dualData.negativeColor
                    )
                }
            }
            .frame(height: 36) // Match boring.notch exactly - reduced from 50
            
            // Click hint - shown for graphs that open popovers
            if graphData.rankingType != nil {
                Text("Click for details")
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.75))
                    .opacity(isHovered ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
            }
        }
        .padding(8) // Match boring.notch padding - reduced from 10
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(isHovered ? 0.45 : 0.18), lineWidth: 1)
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct MiniGraph: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        GeometryReader { geometry in
            let maxValue = data.max() ?? 1.0
            let normalizedData = maxValue > 0 ? data.map { $0 / maxValue } : data
            
            Path { path in
                guard !normalizedData.isEmpty else { return }
                
                let stepX = geometry.size.width / CGFloat(normalizedData.count - 1)
                
                for (index, value) in normalizedData.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geometry.size.height * (1 - CGFloat(value))
                    
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, lineWidth: 2)
            
            // Gradient fill
            Path { path in
                guard !normalizedData.isEmpty else { return }
                
                let stepX = geometry.size.width / CGFloat(normalizedData.count - 1)
                
                path.move(to: CGPoint(x: 0, y: geometry.size.height))
                
                for (index, value) in normalizedData.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geometry.size.height * (1 - CGFloat(value))
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [color.opacity(0.3), color.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}



struct DualQuadrantGraph: View {
    let positiveData: [Double]
    let negativeData: [Double]
    let positiveColor: Color
    let negativeColor: Color
    
    var body: some View {
        GeometryReader { geometry in
            let maxPositive = positiveData.max() ?? 1.0
            let maxNegative = negativeData.max() ?? 1.0
            let maxValue = max(maxPositive, maxNegative)
            
            let normalizedPositive = maxValue > 0 ? positiveData.map { $0 / maxValue } : positiveData
            let normalizedNegative = maxValue > 0 ? negativeData.map { $0 / maxValue } : negativeData
            
            let centerY = geometry.size.height / 2
            
            ZStack {
                // Center dividing line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: centerY))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: centerY))
                }
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                
                // Positive quadrant (upper half)
                Path { path in
                    guard !normalizedPositive.isEmpty else { return }
                    
                    let stepX = geometry.size.width / CGFloat(normalizedPositive.count - 1)
                    
                    for (index, value) in normalizedPositive.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = centerY - (centerY * CGFloat(value)) // Above center
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(positiveColor, lineWidth: 2)
                
                // Positive fill
                Path { path in
                    guard !normalizedPositive.isEmpty else { return }
                    
                    let stepX = geometry.size.width / CGFloat(normalizedPositive.count - 1)
                    
                    path.move(to: CGPoint(x: 0, y: centerY))
                    
                    for (index, value) in normalizedPositive.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = centerY - (centerY * CGFloat(value))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    
                    path.addLine(to: CGPoint(x: geometry.size.width, y: centerY))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [positiveColor.opacity(0.3), positiveColor.opacity(0.1)]),
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                
                // Negative quadrant (lower half)
                Path { path in
                    guard !normalizedNegative.isEmpty else { return }
                    
                    let stepX = geometry.size.width / CGFloat(normalizedNegative.count - 1)
                    
                    for (index, value) in normalizedNegative.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = centerY + (centerY * CGFloat(value)) // Below center
                        
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(negativeColor, lineWidth: 2)
                
                // Negative fill
                Path { path in
                    guard !normalizedNegative.isEmpty else { return }
                    
                    let stepX = geometry.size.width / CGFloat(normalizedNegative.count - 1)
                    
                    path.move(to: CGPoint(x: 0, y: centerY))
                    
                    for (index, value) in normalizedNegative.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = centerY + (centerY * CGFloat(value))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    
                    path.addLine(to: CGPoint(x: geometry.size.width, y: centerY))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [negativeColor.opacity(0.3), negativeColor.opacity(0.1)]),
                        startPoint: .bottom,
                        endPoint: .center
                    )
                )
            }
        }
    }
}

#Preview {
    NotchStatsView()
        .frame(width: 400, height: 300)
        .background(Color.black)
}
