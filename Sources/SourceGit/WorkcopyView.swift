import SwiftUI

/// 工作副本页:文件分组列表(左)+ 提交编辑器(右)。
struct WorkcopyView: View {
    @ObservedObject var model: RepoModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        HSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    FileGroupSection(
                        title: "未暂存的文件",
                        count: model.filteredUnstaged.count,
                        actionTitle: "全部暂存",
                        actionEnabled: !model.filteredUnstaged.isEmpty,
                        action: { model.stageAllUnstaged() }
                    ) {
                        ForEach(model.filteredUnstaged) { file in
                            FileRow(model: model, file: file, staged: false)
                        }
                    }

                    FileGroupSection(
                        title: "已暂存的文件",
                        count: model.filteredStaged.count,
                        actionTitle: "全部取消暂存",
                        actionEnabled: !model.filteredStaged.isEmpty,
                        action: { model.unstageAllStaged() }
                    ) {
                        ForEach(model.filteredStaged) { file in
                            FileRow(model: model, file: file, staged: true)
                        }
                    }

                    if model.filteredUnstaged.isEmpty && model.filteredStaged.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 28))
                                .foregroundStyle(.green)
                            Text(model.searchText.isEmpty ? "没有未提交的更改" : "没有匹配过滤条件的文件")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(minWidth: 380, idealWidth: 520)

            CommitEditorView(model: model, editorFocused: $editorFocused)
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)
        }
        .onChange(of: model.focusCommitEditorToken) {
            editorFocused = true
        }
    }
}

// MARK: - 文件分组

struct FileGroupSection<Content: View>: View {
    let title: String
    let count: Int
    let actionTitle: String
    let actionEnabled: Bool
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(title) (\(count))")
                    .font(.callout.weight(.semibold))
                Spacer()
                Button(actionTitle) { action() }
                    .controlSize(.small)
                    .disabled(!actionEnabled)
            }
            .padding(.horizontal, 4)
            .padding(.top, 6)
            .padding(.bottom, 4)

            content
        }
    }
}

// MARK: - 文件行

struct FileRow: View {
    @ObservedObject var model: RepoModel
    let file: WorktreeFile
    let staged: Bool

    private var selection: SelectedFile {
        SelectedFile(file: file, staged: staged)
    }

    private var isSelected: Bool {
        model.selectedFile == selection
    }

    private var kind: FileChangeKind {
        staged ? file.stagedKind : file.worktreeKind
    }

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { staged },
                set: { _ in model.toggleStage(selection) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .accessibilityLabel(staged ? "取消暂存 \(file.path)" : "暂存 \(file.path)")
            .help(staged ? "点击取消暂存" : "点击暂存")

            FileKindBadge(kind: kind)

            FilePathLabel(path: file.path)

            if file.isConflicted {
                Text("冲突")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
            }
            if let old = file.oldPath, staged {
                Text("← \(old)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .rowBackground(selected: isSelected)
        // 注意:不要用 .accessibilityElement(children: .combine) 合并整行——
        // 那会把行内的暂存复选框从无障碍树里抹掉,VoiceOver 将无法单独切换暂存。
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(file.path)
        .onTapGesture { model.select(file, staged: staged) }
        .onTapGesture(count: 2) { model.toggleStage(selection) }
        .contextMenu {
            if staged {
                Button("取消暂存") { model.unstage([file.path]) }
            } else {
                Button("暂存") { model.stage([file.path]) }
            }
            Divider()
            Button("放弃修改…", role: .destructive) {
                model.requestDiscard([file], staged: staged)
            }
            Divider()
            Button("在 Finder 中显示") {
                model.revealInFinder(relativePath: file.path)
            }
            Button("用默认应用打开") {
                openWithDefaultApp((model.repo.path as NSString).appendingPathComponent(file.path))
            }
            Button("复制路径") {
                copyToPasteboard(file.path)
            }
        }
    }
}

// MARK: - 提交编辑器

struct CommitEditorView: View {
    @ObservedObject var model: RepoModel
    let editorFocused: FocusState<Bool>.Binding

    private var amendBinding: Binding<Bool> {
        Binding(
            get: { model.amendMode },
            set: { newValue in
                Task { await model.toggleAmend(newValue) }
            }
        )
    }

    private var canCommit: Bool {
        let messageOK = !model.commitMessage.sg_trimmed().isEmpty
        let changeOK = model.amendMode || !model.status.staged.isEmpty
        return messageOK && changeOK
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("提交信息")
                    .font(.headline)
                Spacer()
                Text(model.status.isEmptyRepo ? "空仓库:首次提交" : "")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            TextEditor(text: $model.commitMessage)
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
                .frame(maxHeight: .infinity)
                .focused(editorFocused)

            Toggle("修订上次提交 (amend)", isOn: amendBinding)
                .controlSize(.small)
                .disabled(model.status.isEmptyRepo)

            HStack(spacing: 10) {
                Button {
                    Task { await model.commit() }
                } label: {
                    Label(
                        model.amendMode ? "修订提交" : "提交",
                        systemImage: model.amendMode ? "arrow.uturn.backward.circle" : "checkmark.circle"
                    )
                    .frame(minWidth: 60)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!canCommit)

                Text(model.status.staged.isEmpty
                     ? "已暂存 0 个文件"
                     : "已暂存 \(model.status.staged.count) 个文件")
                    .font(.caption)
                    .foregroundStyle(model.status.staged.isEmpty ? Color.secondary : Color.green)
                    .monospacedDigit()

                Spacer()
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
