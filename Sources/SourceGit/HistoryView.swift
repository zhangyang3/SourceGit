import SwiftUI

/// 泳道图几何常量(行视图与 Canvas 必须一致)。
enum CommitRowStyle {
    static let laneWidth: CGFloat = 13
    static let graphLeading: CGFloat = 14

    static func laneX(_ lane: Int) -> CGFloat {
        graphLeading + CGFloat(lane) * laneWidth
    }
}

/// 历史页:顶部筛选行 + 提交表格(图表 / 描述 / 提交 / 作者 / 日期)。
/// 布局参考常见 Git 客户端:筛选项为弹出菜单,表格列对齐。
struct HistoryView: View {
    @ObservedObject var model: RepoModel

    private var rowHeight: CGFloat { model.compactRows ? 24 : 46 }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            tableHeader
            Divider()
            content
        }
    }

    // MARK: - 筛选行

    private var filterBar: some View {
        HStack(spacing: 0) {
            popupMenu(title: model.showRemoteBranches ? "所有分支" : "本地分支") {
                Button("所有分支") { setRemoteBranches(true) }
                Button("仅本地分支") { setRemoteBranches(false) }
            }
            divider
            popupMenu(title: model.showRemoteBranches ? "显示远程分支" : "隐藏远程分支") {
                Button(model.showRemoteBranches ? "隐藏远程分支" : "显示远程分支") {
                    setRemoteBranches(!model.showRemoteBranches)
                }
            }
            divider
            popupMenu(title: model.dateOrder ? "按时间顺序" : "按层级顺序") {
                Button("按层级顺序") { setDateOrder(false) }
                Button("按时间顺序") { setDateOrder(true) }
            }
            divider
            popupMenu(title: model.compactRows ? "紧凑视图" : "宽松视图") {
                Button("宽松视图") { setCompact(false) }
                Button("紧凑视图") { setCompact(true) }
            }

            Spacer(minLength: 0)

            Text("跳转到:")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Menu {
                if model.branches.isEmpty {
                    Text("没有分支")
                } else {
                    ForEach(model.branches) { branch in
                        Button(branch.name) { model.section = .branch(branch) }
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 8)
    }

    private func popupMenu<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Menu(content: content) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func setRemoteBranches(_ on: Bool) {
        model.showRemoteBranches = on
        Task { await model.loadHistory(reset: true) }
    }

    private func setDateOrder(_ on: Bool) {
        model.dateOrder = on
        Task { await model.loadHistory(reset: true) }
    }

    private func setCompact(_ on: Bool) {
        model.compactRows = on
    }

    // MARK: - 表头

    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("图表").frame(width: 44, alignment: .leading)
            Text("描述").frame(maxWidth: .infinity, alignment: .leading)
            Text("提交").frame(width: 78, alignment: .leading)
            Text("作者").frame(width: 130, alignment: .leading)
            Text("日期").frame(width: 116, alignment: .leading)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - 列表

    @ViewBuilder
    private var content: some View {
        let rows = model.filteredHistoryRows
        if rows.isEmpty {
            if model.historyLoading {
                Spacer()
                ProgressView("加载中…")
                Spacer()
            } else if !model.searchText.isEmpty {
                emptyState(icon: "magnifyingglass", title: "没有匹配的提交",
                           message: "试试更换关键词,或清空底部过滤器。")
            } else if model.status.isEmptyRepo {
                emptyState(icon: "clock.arrow.circlepath", title: "还没有任何提交",
                           message: "到「文件状态」暂存文件并创建首个提交。")
            } else {
                emptyState(icon: "clock.arrow.circlepath", title: "没有提交",
                           message: "当前范围没有可显示的提交。")
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        CommitRowView(model: model, row: row, rowHeight: rowHeight)
                    }
                    if model.hasMoreHistory && model.searchText.isEmpty {
                        HStack {
                            Spacer()
                            Button {
                                Task { await model.loadMoreHistory() }
                            } label: {
                                Label("加载更多(已显示 \(model.history.commits.count) 条)", systemImage: "chevron.down.circle")
                            }
                            .controlSize(.regular)
                            .padding(.vertical, 8)
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 提交行

struct CommitRowView: View {
    @ObservedObject var model: RepoModel
    let row: CommitGraphRow
    let rowHeight: CGFloat

    private var isSelected: Bool { model.selectedCommitID == row.commit.id }

    private var isHead: Bool {
        row.commit.refs.contains { $0.kind == .currentHead } || row.commit.hash == model.status.headHash
    }

    var body: some View {
        HStack(spacing: 0) {
            CommitGraphCanvas(row: row, laneCount: model.history.laneCount, isHead: isHead)
                .frame(width: 44, height: rowHeight)

            // 描述列只放主题与引用徽章:作者、日期已有独立列,不再重复
            HStack(spacing: 5) {
                Text(row.commit.subject.isEmpty ? "(无提交信息)" : row.commit.subject)
                    .lineLimit(1)
                    .fontWeight(isSelected ? .semibold : .regular)
                ForEach(Array(row.commit.refs.enumerated()), id: \.offset) { _, ref in
                    RefChip(ref: ref)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.commit.shortHash)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)

            Text(row.commit.authorName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            Text(Fmt.ago(row.commit.authorDate))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: 116, alignment: .leading)
        }
        .padding(.vertical, rowHeight > 30 ? 4 : 1)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(row.commit.subject)
        .accessibilityHint("查看该提交的详情与差异")
        .onTapGesture { model.selectedCommitID = row.commit.id }
        .contextMenu {
            Button("复制短哈希") { copyToPasteboard(row.commit.shortHash) }
            Button("复制完整哈希") { copyToPasteboard(row.commit.hash) }
            Divider()
            Button("复制提交信息") { copyToPasteboard(row.commit.message) }
        }
        .help(row.commit.hash)
    }
}

// MARK: - 引用徽章

struct RefChip: View {
    let ref: CommitRef

    private var color: Color {
        switch ref.kind {
        case .currentHead: return .accentColor
        case .localBranch: return .green
        case .remoteBranch: return .purple
        case .tag: return .orange
        case .other: return .gray
        }
    }

    private var label: String {
        switch ref.kind {
        case .currentHead: return "HEAD → \(ref.name)"
        case .tag: return ref.name
        default: return ref.name
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(color)
    }
}

// MARK: - 泳道图 Canvas

/// 单行泳道图形:
/// - 上半段:`before` 泳道垂直线 + 汇合到本提交的收敛曲线;
/// - 中点:提交圆点(HEAD 提交带外环强调);
/// - 下半段:通向父提交的曲线 + `after` 泳道垂直线。
struct CommitGraphCanvas: View {
    let row: CommitGraphRow
    let laneCount: Int
    let isHead: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            let bottom = size.height
            let lineWidth: CGFloat = 2
            let dotRadius: CGFloat = min(4.5, size.height / 8)

            func x(_ lane: Int) -> CGFloat {
                CommitRowStyle.laneX(lane)
            }

            // 上半段:穿过本行的泳道
            for lane in row.before {
                var path = Path()
                path.move(to: CGPoint(x: x(lane), y: 0))
                path.addLine(to: CGPoint(x: x(lane), y: mid))
                context.stroke(path, with: .color(SGPalette.laneColor(lane)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            // 上半段:并入本提交的收敛曲线(侧泳道汇入主线)
            for edge in row.convergences {
                let x0 = x(edge.from), x1 = x(edge.to)
                var path = Path()
                path.move(to: CGPoint(x: x0, y: 0))
                if abs(x1 - x0) < 0.5 {
                    path.addLine(to: CGPoint(x: x1, y: mid))
                } else {
                    path.addCurve(
                        to: CGPoint(x: x1, y: mid),
                        control1: CGPoint(x: x0, y: mid * 0.45),
                        control2: CGPoint(x: x1, y: mid * 0.55)
                    )
                }
                context.stroke(path, with: .color(SGPalette.laneColor(edge.from)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            // 下半段:通向父提交的曲线
            for edge in row.curves {
                let x0 = x(edge.from), x1 = x(edge.to)
                var path = Path()
                path.move(to: CGPoint(x: x0, y: mid))
                if abs(x1 - x0) < 0.5 {
                    path.addLine(to: CGPoint(x: x1, y: bottom))
                } else {
                    let bend = (bottom - mid) * 0.7
                    path.addCurve(
                        to: CGPoint(x: x1, y: bottom),
                        control1: CGPoint(x: x0, y: mid + bend),
                        control2: CGPoint(x: x1, y: bottom - bend)
                    )
                }
                context.stroke(path, with: .color(SGPalette.laneColor(edge.from)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            // 下半段:穿过本行的泳道
            for lane in row.after {
                var path = Path()
                path.move(to: CGPoint(x: x(lane), y: mid))
                path.addLine(to: CGPoint(x: x(lane), y: bottom))
                context.stroke(path, with: .color(SGPalette.laneColor(lane)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            // 提交圆点
            let cx = x(row.lane)
            let dotColor = SGPalette.laneColor(row.lane)
            let ring: CGFloat = isHead ? dotRadius + 4 : dotRadius + 1.5
            let dotRect = CGRect(x: cx - dotRadius, y: mid - dotRadius,
                                 width: dotRadius * 2, height: dotRadius * 2)
            let ringRect = CGRect(x: cx - ring, y: mid - ring, width: ring * 2, height: ring * 2)
            context.fill(Path(ellipseIn: ringRect),
                         with: .color(colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : .white))
            if isHead {
                context.stroke(Path(ellipseIn: ringRect.insetBy(dx: 1.5, dy: 1.5)),
                               with: .color(dotColor), lineWidth: 2)
            }
            context.fill(Path(ellipseIn: dotRect), with: .color(dotColor))
        }
        .accessibilityHidden(true)
    }
}
