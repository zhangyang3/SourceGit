import Foundation

/// 产品版本单一来源。
/// - make-app.sh 从本文件提取版本号写入 Info.plist,不一致会构建失败;
/// - Release workflow 要求 tag 与此版本一致(见 PLAN §7.3)。
public enum AppVersion {
    public static let current = "0.1.0"

    /// GitHub 仓库(owner/repo),检查更新与发布均使用。
    public static let repository = "zhangyang3/SourceGit"

    /// 运行时有效版本:打包 .app 读 Info.plist;直接运行二进制回退到源码常量。
    public static var effective: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !v.isEmpty {
            return v
        }
        return current
    }
}
