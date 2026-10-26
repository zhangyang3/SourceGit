import Combine
import Foundation

// MARK: - GitHub Release 模型

/// GitHub Releases API 的最小解析模型。
public struct AppRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
    }

    /// 显示用版本号(去掉 v 前缀)。
    public var displayVersion: String {
        tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }
}

/// 语义化版本比较(纯函数,便于测试)。
/// 规则:忽略 v 前缀与 "-" 预发布后缀,按点分数值逐段比较;返回 -1/0/1。
public func compareVersions(_ a: String, _ b: String) -> Int {
    func parts(_ s: String) -> [Int] {
        let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        let main = trimmed.split(separator: "-").first ?? trimmed.split(separator: "+").first ?? Substring(trimmed)
        return main.split(separator: ".").map { Int($0) ?? 0 }
    }
    let pa = parts(a)
    let pb = parts(b)
    for i in 0..<max(pa.count, pb.count) {
        let x = i < pa.count ? pa[i] : 0
        let y = i < pb.count ? pb[i] : 0
        if x != y { return x < y ? -1 : 1 }
    }
    return 0
}

// MARK: - 更新配置(持久化 UserDefaults)

/// 检查频率。
public enum UpdateFrequency: String, CaseIterable, Identifiable, Sendable {
    case launch = "每次启动"
    case daily = "每天一次"
    case weekly = "每周一次"
    public var id: String { rawValue }
}

/// 是否应该执行启动时自动检查(纯函数,便于测试)。
public func shouldAutoCheck(
    autoCheck: Bool,
    frequency: UpdateFrequency,
    lastCheck: Date?,
    now: Date = Date()
) -> Bool {
    guard autoCheck else { return false }
    guard let lastCheck else { return true }
    switch frequency {
    case .launch: return true
    case .daily: return now.timeIntervalSince(lastCheck) > 86_400
    case .weekly: return now.timeIntervalSince(lastCheck) > 7 * 86_400
    }
}

/// 更新配置(写入 UserDefaults;单例在 UI 层使用)。
public final class UpdateSettings: ObservableObject {
    public static let shared = UpdateSettings()

    private let defaults: UserDefaults

    @Published public var autoCheck: Bool {
        didSet { defaults.set(autoCheck, forKey: "update.autoCheck") }
    }

    @Published public var frequency: UpdateFrequency {
        didSet { defaults.set(frequency.rawValue, forKey: "update.frequency") }
    }

    /// 用户选择跳过的版本 tag(如 "v0.2.0")
    @Published public var skippedVersion: String? {
        didSet {
            if let skippedVersion {
                defaults.set(skippedVersion, forKey: "update.skippedVersion")
            } else {
                defaults.removeObject(forKey: "update.skippedVersion")
            }
        }
    }

    @Published public var lastCheckDate: Date? {
        didSet {
            if let lastCheckDate {
                defaults.set(lastCheckDate, forKey: "update.lastCheck")
            } else {
                defaults.removeObject(forKey: "update.lastCheck")
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoCheck = defaults.object(forKey: "update.autoCheck") as? Bool ?? true
        if let raw = defaults.string(forKey: "update.frequency"),
           let saved = UpdateFrequency(rawValue: raw) {
            frequency = saved
        } else {
            frequency = .weekly
        }
        skippedVersion = defaults.string(forKey: "update.skippedVersion")
        lastCheckDate = defaults.object(forKey: "update.lastCheck") as? Date
    }

    public func clearSkipped() {
        skippedVersion = nil
    }
}

/// 更新检查状态。
public enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    /// 尚无任何 Release(首次发布前的正常状态)
    case noRelease(String)
    case available(AppRelease)
    case failed(String)
}
