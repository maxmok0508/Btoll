import Foundation
import Defaults
import Darwin

@MainActor
enum BsstollPortableSetup {
    static func start() {
        guard let resource=Bundle.main.resourceURL?.appendingPathComponent("PortableBridge"),
              FileManager.default.fileExists(atPath:resource.appendingPathComponent("manifest.json").path) else { return }
        let home=FileManager.default.homeDirectoryForCurrentUser
        let uid=getuid()
        Task {
            do {
                let result=try await Task.detached {
                    try BsstollBridgeFiles.install(resource:resource,home:home,uid:uid)
                }.value
                BtollL10n.writeBridgeLanguage()
                if result.firstInstall {
                    Defaults[.enableStatsFeature]=true
                    Defaults[.dynamicShelf]=false
                    Defaults[.enableTimerFeature]=false
                    Defaults[.enableThirdPartyExtensions]=true
                    Defaults[.enableExtensionLiveActivities]=true
                    Defaults[.enableExtensionNotchExperiences]=true
                    Defaults[.enableExtensionNotchTabs]=true
                    let auth=ExtensionAuthorizationManager.shared
                    if auth.authorizationEntry(for:"local.codex.atoll-status") == nil {
                        auth.authorize(bundleIdentifier:"local.codex.atoll-status",appName:"Btoll 本机监控",scopes:[.liveActivities,.notchExperiences])
                    }
                }
            } catch {
                Logger.log("Portable monitoring setup failed: \(error.localizedDescription)",category:.warning)
            }
        }
    }
}
