import SwiftUI

/// 提交行与泳道图的几何常量(行视图与 Canvas 必须一致)。
enum CommitRowStyle {
    static let height: CGFloat = 46
    static let laneWidth: CGFloat = 12
    static let graphLeading: CGFloat = 12
    static let dotRadius: CGFloat = 4.5

    static func laneX(_ lane: Int) -> CGFloat {
        graphLeading + CGFloat(lane) * laneWidth
    }

    static func graphWidth(laneCount: Int) -> CGFloat {
        max(56, graphLeading + CGFloat(laneCount) * laneWidth + 12)
    }
}

/// 历史页:泳道图形 + 提交列表 + 分页加载。
struct HistoryView: View {
    @ObservedObject var model: RepoModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("提交历史")
                    .font(.callout.weight(.semibold))
                Text(model.historyScopeLabel)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Color.accentColor)
                Text("\(model.filteredHistoryRows.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if model.historyLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            Divider()

            let rows = model.filteredHistoryRows
            if rows.isEmpty {
                if model.historyLoading {
                    Spacer()
                    ProgressView("加载中…")
                    Spacer()
                } else if !model.searchText.isEmpty {
                    emptyState(icon: "magnifyingglass", title: "没有匹配的提交",
                               message: "尝试更换关键词,或清空过滤条件。")
                } else if model.status.isEmptyRepo {
                    emptyState(icon: "clock.arrow.circlepath", title: "还没有任何提交",
                               message: "到「工作副本」暂存文件并创建首个提交。")
                } else {
                    emptyState(icon: "clock.arrow.circlepath", title: "没有提交",
                               message: "当前范围没有可显示的提交。")
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row in
                            CommitRowView(model: model, row: row)
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
                                .padding(.vertical, 10)
                                Spacer()
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
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

    private var isSelected: Bool { model.selectedCommitID == row.commit.id }

    private var isHead: Bool {
        row.commit.refs.contains { $0.kind == .currentHead }
            || row.commit.hash == model.status.headHash
    }

    var body: some View {
        HStack(spacing: 0) {
            CommitGraphCanvas(row: row, laneCount: model.history.laneCount, isHead: isHead)
                .frame(width: CommitRowStyle.graphWidth(laneCount: model.history.laneCount),
                       height: CommitRowStyle.height)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.commit.subject.isEmpty ? "(无提交信息)" : row.commit.subject)
                        .lineLimit(1)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .truncationMode(.tail)

                    ForEach(Array(row.commit.refs.enumerated()), id: \.offset) { _, ref in
                        RefChip(ref: ref)
                    }
                }
                Text("\(row.commit.authorName) · \(Fmt.ago(row.commit.authorDate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            Text(row.commit.shortHash)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.trailing, 10)
        .rowBackground(selected: isSelected)
        .contentShape(Rectangle())
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
        case .currentHead: return Color.accentColor
        case .localBranch: return .green
        case .remoteBranch: return .purple
        case .tag: return .orange
        case .other: return .gray
        }
    }

    private var label: String {
        switch ref.kind {
        case .currentHead: return "HEAD → \(ref.name)"
        case .tag: return "🏷 \(ref.name)"
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
/// - 上半段:`before` 泳道垂直线
/// - 中点:提交圆点(HEAD 提交带外环)
/// - 下半段:`curves` 连线(起点=本提交泳道,终点=父提交泳道)+ `after` 垂直线
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

            // 上半段:已有泳道穿过
            for lane in row.before {
                var path = Path()
                path.move(to: CGPoint(x: CommitRowStyle.laneX(lane), y: 0))
                path.addLine(to: CGPoint(x: CommitRowStyle.laneX(lane), y: mid))
                context.stroke(path, with: .color(SGPalette.laneColor(lane)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            // 下半段:连向父提交的曲线
            for curve in row.curves {
                let x0 = CommitRowStyle.laneX(curve.from)
                let x1 = CommitRowStyle.laneX(curve.to)
                var path = Path()
                path.move(to: CGPoint(x: x0, y: mid))
                if abs(x1 - x0) < 0.5 {
                    path.addLine(to: CGPoint(x: x1, y: bottom))
                } else {
                    let bend = (bottom - mid) * 0.75
                    path.addCurve(
                        to: CGPoint(x: x1, y: bottom),
                        control1: CGPoint(x: x0, y: mid + bend),
                        control2: CGPoint(x: x1, y: bottom - bend)
                    )
                }
                context.stroke(path, with: .color(SGPalette.laneColor(curve.from)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            // 下半段:穿过泳道的垂直线(排除已由曲线覆盖的自身泳道重复无碍,直接叠加)
            for lane in row.after {
                var path = Path()
                path.move(to: CGPoint(x: CommitRowStyle.laneX(lane), y: mid))
                path.addLine(to: CGPoint(x: CommitRowStyle.laneX(lane), y: bottom))
                context.stroke(path, with: .color(SGPalette.laneColor(lane)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }

            // 提交圆点
            let cx = CommitRowStyle.laneX(row.lane)
            let dotColor = SGPalette.laneColor(row.lane)
            let ringInset: CGFloat = isHead ? 8 : 1.5
            let dotRect = CGRect(
                x: cx - CommitRowStyle.dotRadius,
                y: mid - CommitRowStyle.dotRadius,
                width: CommitRowStyle.dotRadius * 2,
                height: CommitRowStyle.dotRadius * 2
            )
            // 底色描边圈(与背景同色,产生圆点分隔感)
            let ringRect = dotRect.insetBy(dx: -ringInset, dy: -ringInset)
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
