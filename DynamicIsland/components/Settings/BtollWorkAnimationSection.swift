import SwiftUI
import AppKit
import UniformTypeIdentifiers
import LottieUI

struct BtollWorkAnimationSection: View {
    struct Choice: Identifiable, Decodable {
        let id: String
        let name: String
        let file: String
    }
    @State private var selected="codex"
    @State private var choices:[Choice]=[]
    @State private var error:String?
    private let root=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AtollCodexBridge")
    var body:some View {
        Section {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:132),spacing:10)],spacing:10) {
                option(id:"codex",name:"跟随 Codex 状态",url:root.appendingPathComponent("assets/animations/state-working.json"))
                option(id:"project",name:"项目图标",url:Bundle.main.resourceURL?.appendingPathComponent("PortableBridge/assets/brand-icon-active.json"))
                if FileManager.default.fileExists(atPath:root.appendingPathComponent("assets/local-status-active.json").path) {
                    option(id:"original",name:"原工作动画",url:root.appendingPathComponent("assets/local-status-active.json"))
                }
                ForEach(choices) { choice in option(id:choice.id,name:choice.name,url:root.appendingPathComponent(choice.file)) }
                if choices.count>1 { option(id:"shuffle",name:"自动轮换",url:choices.first.map { root.appendingPathComponent($0.file) }) }
            }.padding(.vertical,6)
            HStack {
                Button(BtollL10n.text("导入动画…"),systemImage:"plus") { importAnimation() }
                Spacer()
                if let error { BtollText(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
            }
        } header: { BtollText("工作动画") }
          footer: { BtollText("跟随 Codex 的响应、执行、等待输入和完成状态切换动画；旋转表示正在处理。每种状态内的动作连续衔接，约 5 秒更新一次。") }
          .onAppear(perform:reload)
    }
    private func option(id:String,name:String,url:URL?)->some View {
        Button {
            do {
                try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let data=try JSONSerialization.data(withJSONObject:["selected":id])
                try data.write(to:root.appendingPathComponent("animation-preferences.json"),options:.atomic)
                selected=id;error=nil
            } catch { self.error="无法保存动画设置" }
        } label: {
            VStack(spacing:8) {
                ZStack {
                    RoundedRectangle(cornerRadius:12).fill(.black).frame(height:62)
                    if let url {
                        LottieView(state:LUStateData(type:.loadedFrom(url),speed:1,loopMode:selected==id ? .loop : .playOnce)).frame(width:50,height:50)
                    } else { Image(systemName:"shuffle").font(.title2) }
                }
                HStack(spacing:5) {
                    BtollText(name).font(.system(size:11,weight:.medium)).lineLimit(2).multilineTextAlignment(.center).frame(minHeight:28)
                    if selected==id { Image(systemName:"checkmark.circle.fill").foregroundStyle(.mint) }
                }
            }.padding(9).frame(maxWidth:.infinity)
                .background(selected==id ? Color.mint.opacity(0.1):Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:13))
                .overlay(RoundedRectangle(cornerRadius:13).stroke(selected==id ? Color.mint.opacity(0.7):.clear,lineWidth:1))
        }.buttonStyle(.plain).accessibilityLabel(BtollL10n.text(name)).accessibilityValue(selected==id ? "已选择":"未选择")
    }
    private func reload() {
        func read(_ url:URL)->[Choice] { guard let data=try? Data(contentsOf:url),let values=try? JSONDecoder().decode([Choice].self,from:data) else{return []};return values.filter { !$0.file.hasPrefix("/") && !$0.file.split(separator:"/").contains("..") && FileManager.default.fileExists(atPath:root.appendingPathComponent($0.file).path) } }
        let all=read(root.appendingPathComponent("assets/animations/catalog.json"))+read(root.appendingPathComponent("user-animations/catalog.json"))
        var ids=Set<String>()
        choices=all.filter { ids.insert($0.id).inserted }
        if let data=try? Data(contentsOf:root.appendingPathComponent("animation-preferences.json")),let preferences=(try? JSONSerialization.jsonObject(with:data)) as? [String:String] { selected=preferences["selected"] ?? "codex" }
        else {selected="codex"}
    }
    private func importAnimation() {
        let panel=NSOpenPanel();panel.allowedContentTypes=[.json];panel.allowsMultipleSelection=true;panel.canChooseDirectories=false
        guard panel.runModal() == .OK else{return}
        do {
            let directory=root.appendingPathComponent("user-animations")
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            var imported:[[String:String]]=[]
            let catalog=directory.appendingPathComponent("catalog.json")
            if let data=try? Data(contentsOf:catalog) { imported=(try? JSONSerialization.jsonObject(with:data)) as? [[String:String]] ?? [] }
            for url in panel.urls {
                let data=try Data(contentsOf:url)
                guard data.count<=5*1024*1024,let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],value["layers"] is [Any],value["fr"] is NSNumber else { throw CocoaError(.fileReadCorruptFile) }
                let id="user-"+UUID().uuidString.lowercased()
                try data.write(to:directory.appendingPathComponent(id+".json"),options:.atomic)
                imported.append(["id":id,"name":url.deletingPathExtension().lastPathComponent,"file":"user-animations/"+id+".json"])
            }
            try JSONSerialization.data(withJSONObject:imported).write(to:catalog,options:.atomic)
            error=nil;reload()
        } catch { self.error="请选择有效的 Lottie JSON（每个不超过 5 MB）" }
    }
}
