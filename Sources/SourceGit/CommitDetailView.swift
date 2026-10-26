import SwiftUI

/// 提交详情:元信息头 + 变更文件列表(左)+ 选中文件 diff(右)。
struct CommitDetailView: View {
    @ObservedObject var model: RepoModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let commit = model.selectedCommit {
            VStack(spacing: 0) {
                header(commit)
                Divider()

                HSplitView {
                    // 变更文件摘要列表(轻量,不含 hunk)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.commitChanges) { change in
                                CommitFileRow(
                                    change: change,
                                    selected: model.selectedCommitPath == change.path
                                ) {
                                    model.selectedCommitPath = change.path
                                }
                            }
                            if model.commitChanges.isEmpty {
                                Text("没有文件变更")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(12)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .frame(minWidth: 240, idealWidth: 320, maxWidth: 460)

                    // 选中文件 diff(按需加载 + LRU 缓存)
                    if !model.selectedCommitDiff.isEmpty {
                        DiffFilesView(files: model.selectedCommitDiff, mode: model.diffMode, dark: colorScheme == .dark)
                    } else {
                        ContentUnavailableView(
                            "选择文件查看差异",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "选择提交以查看详情",
                systemImage: "doc.text.magnifyingglass"
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func header(_ commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                AvatarCircle(name: commit.authorName, email: commit.authorEmail)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(commit.authorName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(Fmt.ago(commit.authorDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(commit.authorEmail)  ·  \(Fmt.short(commit.authorDate))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 6) {
                        ForEach(Array(commit.refs.enumerated()), id: \.offset) { _, ref in
                            RefChip(ref: ref)
                        }
                        if model.selectedCommitIsMerge {
                            Text("合并提交 · 与第一父提交比较")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                Spacer()

                // 哈希(点击复制)
                Text(commit.shortHash)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    .help("点击复制完整哈希:\(commit.hash)")
                    .onTapGesture { copyToPasteboard(commit.hash) }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(commit.subject.isEmpty ? "(无提交信息)" : commit.subject)
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
                if !commit.body.isEmpty {
                    Text(commit.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - 变更文件行

struct CommitFileRow: View {
    let change: CommitFileChange
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            FileKindBadge(kind: change.kind)
            FilePathLabel(path: change.path)
            if let old = change.oldPath {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(old)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let adds = change.adds, let dels = change.dels {
                Text("+\(adds)")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .monospacedDigit()
                Text("−\(dels)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .monospacedDigit()
            } else {
                Text("二进制")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .rowBackground(selected: selected)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .help(change.oldPath.map { "\($0) → \(change.path)" } ?? change.path)
    }
}

// MARK: - 作者头像(邮件哈希取色,首字母)

struct AvatarCircle: View {
    let name: String
    let email: String

    /// 稳定散列(djb2),避免 Swift hashValue 每次运行变化。
    private var stableHash: UInt64 {
        var hash: UInt64 = 5381
        for byte in email.utf8 {
            hash = (hash << 5) &+ hash &+ UInt64(byte)
        }
        return hash
    }

    private var hue: Double {
        Double(stableHash % 360) / 360
    }

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    var body: some View {
        ZStack {
            Circle().fill(Color(hue: hue, saturation: 0.42, brightness: 0.72))
            Text(initials)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .help("\(name) <\(email)>")
    }
}
