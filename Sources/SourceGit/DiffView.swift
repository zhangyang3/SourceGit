import SwiftUI

/// 单文件渲染行数上限(超过截断,保证内存与流畅度;见 PLAN §2.3)。
let diffLineRenderCap = 3000

/// 底部差异面板。
struct DiffPane: View {
    @ObservedObject var model: RepoModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            if let sel = model.selectedFile {
                header(sel)
                Divider()
                if model.fileDiff.isEmpty {
                    ContentUnavailableView(
                        "无差异内容",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("该文件暂无可显示的差异。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    DiffFilesView(files: model.fileDiff, mode: model.diffMode, dark: colorScheme == .dark)
                }
            } else {
                ContentUnavailableView {
                    Label("选择文件以查看差异", systemImage: "doc.text.magnifyingglass")
                } description: {
                    Text("在上方列表中点击文件\n支持统一与并排两种视图。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func header(_ sel: SelectedFile) -> some View {
        HStack(spacing: 8) {
            FileKindBadge(kind: sel.staged ? sel.file.stagedKind : sel.file.worktreeKind)
            VStack(alignment: .leading, spacing: 1) {
                FilePathLabel(path: sel.file.path)
                if let rename = model.fileDiff.first?.renameDisplay {
                    Text(rename).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()

            let first = model.fileDiff.first
            if let first, first.kind != .binary {
                Text("+\(first.adds)")
                    .foregroundStyle(.green).monospacedDigit()
                Text("−\(first.dels)")
                    .foregroundStyle(.red).monospacedDigit()
            }

            Picker("差异模式", selection: $model.diffMode) {
                ForEach(DiffDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 130)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - 文件差异列表

struct DiffFilesView: View {
    let files: [DiffFile]
    let mode: DiffDisplayMode
    let dark: Bool

    var body: some View {
        ScrollView([.vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(files) { file in
                    DiffFileSection(file: file, mode: mode, dark: dark)
                }
            }
        }
    }
}

struct DiffFileSection: View {
    let file: DiffFile
    let mode: DiffDisplayMode
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 文件头
            HStack(spacing: 8) {
                FileKindBadge(kind: kindForBadge)
                VStack(alignment: .leading, spacing: 1) {
                    FilePathLabel(path: file.displayName)
                    if let rename = file.renameDisplay {
                        Text(rename).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if file.kind == .binary {
                    Text("二进制文件").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("+\(file.adds)").foregroundStyle(.green).monospacedDigit()
                    Text("−\(file.dels)").foregroundStyle(.red).monospacedDigit()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SGPalette.hunkHeaderBg)

            if file.kind == .binary {
                Text("二进制文件不支持文本差异展示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            } else {
                let capped = cappedHunks()
                ForEach(capped.hunks) { hunk in
                    if mode == .unified {
                        UnifiedHunkView(hunk: hunk, dark: dark)
                    } else {
                        SideBySideHunkView(hunk: hunk, dark: dark)
                    }
                }
                if capped.truncated {
                    Text("⚠ 文件较大,已截断显示前 \(diffLineRenderCap) 行")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(8)
                }
            }
        }
    }

    private var kindForBadge: FileChangeKind {
        switch file.kind {
        case .modified: return .modified
        case .added: return .added
        case .deleted: return .deleted
        case .renamed: return .renamed
        case .copied: return .copied
        case .binary: return .modified
        }
    }

    private func cappedHunks() -> (hunks: [DiffHunk], truncated: Bool) {
        let total = file.hunks.reduce(0) { $0 + $1.lines.count }
        guard total > diffLineRenderCap else { return (file.hunks, false) }
        var budget = diffLineRenderCap
        var result: [DiffHunk] = []
        for hunk in file.hunks {
            if budget <= 0 { break }
            if hunk.lines.count <= budget {
                result.append(hunk)
                budget -= hunk.lines.count
            } else {
                result.append(
                    DiffHunk(
                        id: hunk.id,
                        oldStart: hunk.oldStart, oldCount: hunk.oldCount,
                        newStart: hunk.newStart, newCount: hunk.newCount,
                        context: hunk.context,
                        lines: Array(hunk.lines.prefix(budget))
                    )
                )
                budget = 0
            }
        }
        return (result, true)
    }
}

// MARK: - 统一视图

struct UnifiedHunkView: View {
    let hunk: DiffHunk
    let dark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunkHeaderView(text: hunk.header, context: hunk.context)
            ForEach(hunk.lines) { line in
                UnifiedLineRow(line: line, dark: dark)
            }
        }
    }
}

struct HunkHeaderView: View {
    let text: String
    let context: String

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(context)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(SGPalette.hunkHeaderBg)
        .textSelection(.enabled)
    }
}

struct UnifiedLineRow: View {
    let line: DiffLine
    let dark: Bool

    private var background: Color? {
        switch line.kind {
        case .added: return SGPalette.diffAddedBg(dark)
        case .deleted: return SGPalette.diffDeletedBg(dark)
        case .context: return nil
        case .meta: return Color.primary.opacity(0.04)
        }
    }

    private var textColor: Color {
        switch line.kind {
        case .added: return SGPalette.diffAddedText
        case .deleted: return SGPalette.diffDeletedText
        case .context: return .primary
        case .meta: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            LineNumberCell(number: line.oldNumber, width: 46)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            LineNumberCell(number: line.newNumber, width: 46)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
        .background(background ?? Color.clear)
        .monospacedDigit()
    }
}

struct LineNumberCell: View {
    let number: Int?
    let width: CGFloat

    var body: some View {
        Text(number.map(String.init) ?? "")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .trailing)
            .padding(.trailing, 6)
            .textSelection(.enabled)
    }
}

// MARK: - 并排视图

struct SideBySideHunkView: View {
    let hunk: DiffHunk
    let dark: Bool

    /// 删除/新增按顺序配对;上下文行左右同显。
    static func pair(_ hunk: DiffHunk) -> [(DiffLine?, DiffLine?)] {
        var rows: [(DiffLine?, DiffLine?)] = []
        var pendingDeletes: [DiffLine] = []
        for line in hunk.lines {
            switch line.kind {
            case .deleted:
                pendingDeletes.append(line)
            case .added:
                let match = pendingDeletes.isEmpty ? nil : pendingDeletes.removeFirst()
                rows.append((match, line))
            case .context:
                while let d = pendingDeletes.first {
                    rows.append((d, nil))
                    pendingDeletes.removeFirst()
                }
                rows.append((line, line))
            case .meta:
                continue
            }
        }
        while let d = pendingDeletes.first {
            rows.append((d, nil))
            pendingDeletes.removeFirst()
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HunkHeaderView(text: hunk.header, context: hunk.context)
            ForEach(Array(Self.pair(hunk).enumerated()), id: \.offset) { _, pair in
                SideBySideRow(left: pair.0, right: pair.1, dark: dark)
            }
        }
    }
}

struct SideBySideRow: View {
    let left: DiffLine?
    let right: DiffLine?
    let dark: Bool

    var body: some View {
        HStack(spacing: 0) {
            halfSide(left, oldSide: true)
            Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1)
            halfSide(right, oldSide: false)
        }
    }

    @ViewBuilder
    private func halfSide(_ line: DiffLine?, oldSide: Bool) -> some View {
        let bg: Color? = {
            guard let line else { return Color.primary.opacity(0.03) }
            switch line.kind {
            case .added: return SGPalette.diffAddedBg(dark)
            case .deleted: return SGPalette.diffDeletedBg(dark)
            default: return nil
            }
        }()
        HStack(spacing: 0) {
            LineNumberCell(number: line.flatMap { oldSide ? $0.oldNumber : $0.newNumber }, width: 46)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            Text(line.map { $0.text.isEmpty ? " " : $0.text } ?? " ")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(textColor(line))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)
        }
        .background(bg ?? Color.clear)
        .monospacedDigit()
    }

    private func textColor(_ line: DiffLine?) -> Color {
        switch line?.kind {
        case .added: return SGPalette.diffAddedText
        case .deleted: return SGPalette.diffDeletedText
        default: return .primary
        }
    }
}
