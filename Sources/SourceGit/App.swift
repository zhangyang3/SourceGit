import AppKit
import SwiftUI

@main
struct SourceGitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    init() {
        // `swift run` / 直接运行二进制时需声明为常规 GUI 应用;
        // 打包成 .app 时无副作用。
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("SourceGit") {
            MainView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1320, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Text("SourceGit \(AppVersion.effective)")
            }
            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    Task { await UpdateChecker.shared.check(manual: true) }
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    appState.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("打开仓库…") {
                    appState.openRepoFromPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
                Button("克隆仓库…") {
                    appState.showCloneSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandMenu("视图") {
                Button("工作副本") {
                    appState.activeRepo?.section = .status
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(appState.activeRepo == nil)

                Button("历史") {
                    appState.activeRepo?.section = .history
                    if let repo = appState.activeRepo, repo.history.commits.isEmpty {
                        Task { await repo.loadHistory() }
                    }
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(appState.activeRepo == nil)

                Divider()

                Button("聚焦过滤框") {
                    appState.activeRepo?.focusSearchToken += 1
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(appState.activeRepo == nil)
            }
            CommandMenu("仓库") {
                Button("刷新") {
                    Task { await appState.activeRepo?.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.activeRepo == nil)

                Divider()

                Button("在 Finder 中显示") {
                    appState.activeRepo?.revealInFinder()
                }
                .disabled(appState.activeRepo == nil)
                Button("在终端中打开") {
                    appState.activeRepo?.openInTerminal()
                }
                .disabled(appState.activeRepo == nil)

                Divider()

                Button("从列表移除当前仓库…") {
                    appState.removeCurrent()
                }
                .disabled(appState.activeRepo == nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 常驻工具:关最后一个窗口不退出(⌘Q 退出)。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
