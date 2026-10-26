import AppKit
import SwiftUI

// MARK: - 文件状态徽章

extension FileChangeKind {
    var badgeLetter: String {
        switch self {
        case .added: return "A"
        case .modified: return "M"
        case .deleted: return "D"
        case .renamed: return "R"
        case .copied: return "C"
        case .untracked: return "?"
        case .conflicted: return "!"
        case .typechange: return "T"
        }
    }

    var badgeColor: Color {
        switch self {
        case .added: return .green
        case .modified: return .orange
        case .deleted: return .red
        case .renamed, .copied: return .blue
        case .untracked: return .gray
        case .conflicted: return .red
        case .typechange: return .orange
        }
    }

    var displayLabel: String {
        switch self {
        case .added: return "新增"
        case .modified: return "修改"
        case .deleted: return "删除"
        case .renamed: return "重命名"
        case .copied: return "复制"
        case .untracked: return "未跟踪"
        case .conflicted: return "冲突"
        case .typechange: return "类型变化"
        }
    }
}

struct FileKindBadge: View {
    let kind: FileChangeKind

    var body: some View {
        Text(kind.badgeLetter)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .frame(width: 16, height: 16)
            .background(kind.badgeColor.opacity(0.18))
            .foregroundStyle(kind.badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help(kind.displayLabel)
    }
}

// MARK: - 路径展示

/// 目录次要色 + 文件名主色的路径标签。
struct FilePathLabel: View {
    let path: String

    var body: some View {
        let dir = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        HStack(spacing: 4) {
            if !dir.isEmpty {
                Text(dir + "/")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(name)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .help(path)
    }
}

// MARK: - 颜色

enum SGPalette {
    /// 泳道循环色(M3 历史图使用)。
    static let lanes: [Color] = [
        Color(nsColor: .systemBlue),
        Color(nsColor: .systemOrange),
        Color(nsColor: .systemGreen),
        Color(nsColor: .systemPurple),
        Color(nsColor: .systemPink),
        Color(nsColor: .systemTeal),
        Color(nsColor: .systemYellow),
        Color(nsColor: .systemIndigo),
    ]

    static func laneColor(_ index: Int) -> Color {
        lanes[index % lanes.count]
    }

    static let diffAddedText = Color(nsColor: .systemGreen)
    static let diffDeletedText = Color(nsColor: .systemRed)
    static func diffAddedBg(_ dark: Bool) -> Color { Color.green.opacity(dark ? 0.22 : 0.12) }
    static func diffDeletedBg(_ dark: Bool) -> Color { Color.red.opacity(dark ? 0.22 : 0.12) }
    static var hunkHeaderBg: Color { Color.primary.opacity(0.06) }
}

// MARK: - 日期格式化

enum Fmt {
    private static let relative = RelativeDateTimeFormatter()

    static func ago(_ date: Date) -> String {
        relative.localizedString(for: date, relativeTo: Date())
    }

    static func short(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute())
    }
}

// MARK: - 上游跟踪显示

/// "ahead 2, behind 1" → "↑2 ↓1"
func trackDisplay(_ track: String?) -> String? {
    guard let track, !track.isEmpty else { return nil }
    if track == "gone" { return "已断开" }
    var parts: [String] = []
    if let r = track.range(of: #"ahead (\d+)"#, options: .regularExpression) {
        parts.append("↑" + track[r].dropFirst("ahead ".count))
    }
    if let r = track.range(of: #"behind (\d+)"#, options: .regularExpression) {
        parts.append("↓" + track[r].dropFirst("behind ".count))
    }
    return parts.isEmpty ? track : parts.joined(separator: " ")
}

// MARK: - 面板与剪贴板

/// 目录选择面板,返回选中的目录路径。
func openDirectoryPanel(title: String) -> String? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.message = title
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK else { return nil }
    return panel.url?.path
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// 用默认应用打开文件。
func openWithDefaultApp(_ fullPath: String) {
    NSWorkspace.shared.open(URL(fileURLWithPath: fullPath))
}

// MARK: - 行高亮扩展

extension View {
    /// 列表行选中态背景。
    func rowBackground(selected: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
    }
}
