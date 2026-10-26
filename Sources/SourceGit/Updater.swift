import AppKit
import Foundation
import SwiftUI

/// GitHub Releases 更新检查器(单例;纯逻辑在 GitCore/UpdateCore.swift)。
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    let settings: UpdateSettings
    @Published private(set) var state: UpdateState = .idle

    init(settings: UpdateSettings = .shared) {
        self.settings = settings
    }

    var apiURL: URL {
        URL(string: "https://api.github.com/repos/\(AppVersion.repository)/releases/latest")!
    }

    /// 启动时按配置自动检查。
    func maybeAutoCheck() async {
        guard shouldAutoCheck(
            autoCheck: settings.autoCheck,
            frequency: settings.frequency,
            lastCheck: settings.lastCheckDate
        ) else { return }
        await check(manual: false)
    }

    /// 检查更新。manual=true 时忽略"跳过此版本"设置。
    @MainActor
    func check(manual: Bool) async {
        state = .checking
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            if statusCode == 404 {
                state = .noRelease("暂无可用发布(仓库未公开或尚未发布版本)")
                return
            }
            guard (200...299).contains(statusCode) else {
                state = .failed("GitHub API 返回状态码 \(statusCode)")
                return
            }
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            settings.lastCheckDate = Date()
            if compareVersions(release.tagName, AppVersion.effective) > 0 {
                if !manual, settings.skippedVersion == release.tagName {
                    state = .upToDate
                } else {
                    state = .available(release)
                }
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed("网络请求失败:\(error.localizedDescription)")
        }
    }

    /// 打开 Release 页面下载。
    @MainActor
    func openDownload(_ release: AppRelease) {
        if let url = URL(string: release.htmlURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// 跳过指定版本。
    @MainActor
    func skip(_ release: AppRelease) {
        settings.skippedVersion = release.tagName
    }
}
