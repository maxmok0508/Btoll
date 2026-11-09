import SwiftUI
import AppKit

struct BtollLanguageSection:View {
    @State private var language=UserDefaults.standard.string(forKey:"btollInterfaceLanguage") ?? "system"
    @State private var restart=false
    var body:some View {
        Section {
            Picker(BtollL10n.isEnglish ? "App language":"应用语言",selection:$language) {
                Text(BtollL10n.isEnglish ? "Follow system":"跟随系统").tag("system")
                Text("简体中文").tag("zh-Hans")
                Text("English").tag("en")
            }.onChange(of:language) { _,value in
                UserDefaults.standard.set(value,forKey:"btollInterfaceLanguage")
                if value=="system" { UserDefaults.standard.removeObject(forKey:"AppleLanguages") }
                else { UserDefaults.standard.set([value],forKey:"AppleLanguages") }
                BtollL10n.writeBridgeLanguage()
                restart=true
            }
        } header: { Text("语言 / Language") }
          footer: { Text(BtollL10n.isEnglish ? "Restart Btoll to apply the language to every window.":"重启 Btoll 后，所选语言会应用到所有窗口。") }
          .alert(BtollL10n.isEnglish ? "Apply language":"应用语言",isPresented:$restart) {
              Button(BtollL10n.isEnglish ? "Restart now":"现在重启") { relaunch() }
              Button(BtollL10n.isEnglish ? "Later":"稍后",role:.cancel) { }
          } message: { Text(BtollL10n.isEnglish ? "Your settings and session data will be preserved.":"设置和会话数据会保留。") }
    }
    private func relaunch() {
        let process=Process();process.executableURL=URL(fileURLWithPath:"/bin/sh")
        process.arguments=["-c","/bin/sleep 1; /usr/bin/open \"$1\"","btoll-relaunch",Bundle.main.bundleURL.path]
        do { try process.run();NSApp.terminate(nil) } catch { restart=true }
    }
}
