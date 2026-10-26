import Foundation

/// 提交图的一行:提交所在的泳道,以及本行上下半段的连线数据。
public struct CommitGraphRow: Identifiable, Sendable {
    /// 等同于提交哈希
    public var id: String { commit.id }
    public let commit: GitCommit
    /// 本提交所在泳道编号
    public let lane: Int
    /// 进入本行(上半段)时有提交等待的泳道
    public let before: [Int]
    /// 离开本行(下半段)时有提交等待的泳道
    public let after: [Int]
    /// 从本提交点连向下一行的曲线(起点=本提交泳道,终点=父提交泳道)
    public let curves: [(from: Int, to: Int)]
}

/// 提交图泳道(lane)算法。
///
/// 输入要求按 `--topo-order` 排列(新→旧)。核心思路:
/// 维护数组 `lanes`,`lanes[i]` 表示第 i 条泳道正在等待的提交哈希。
/// 处理每个提交时:
/// 1. 若某泳道等待的正是它,占用该泳道;否则在尾部新开一条;
/// 2. 该哈希占用的所有泳道释放,优先把父提交填进刚释放的槽位;
/// 3. 父提交若已被其他泳道等待(汇合),直接画曲线连过去,不再占新槽;
/// 4. 每行结束后回收尾部空泳道,压缩图宽。
public enum GraphBuilder {

    public static func build(_ commits: [GitCommit]) -> (rows: [CommitGraphRow], laneCount: Int) {
        var lanes: [String?] = []
        var rows: [CommitGraphRow] = []
        rows.reserveCapacity(commits.count)
        var maxLane = 0

        for commit in commits {
            let before = lanes.indices.filter { lanes[$0] != nil }
            var lane = lanes.firstIndex { $0 == commit.hash }
            if lane == nil {
                lanes.append(commit.hash)
                lane = lanes.count - 1
            }
            let myLane = lane!
            maxLane = max(maxLane, myLane)

            // 释放本哈希占用的全部泳道(含自己)
            let freed = lanes.indices.filter { lanes[$0] == commit.hash }
            for i in freed { lanes[i] = nil }

            var curves: [(from: Int, to: Int)] = []
            var slotCursor = 0
            for parent in commit.parents {
                // 父提交已被其他泳道等待 → 汇合,直接连过去
                if let existing = lanes.firstIndex(where: { $0 == parent }) {
                    curves.append((myLane, existing))
                    continue
                }
                let slot: Int
                if slotCursor < freed.count {
                    slot = freed[slotCursor]
                    slotCursor += 1
                } else {
                    lanes.append(parent)
                    slot = lanes.count - 1
                    maxLane = max(maxLane, slot)
                }
                lanes[slot] = parent
                curves.append((myLane, slot))
            }

            let after = lanes.indices.filter { lanes[$0] != nil }
            rows.append(CommitGraphRow(commit: commit, lane: myLane, before: before, after: after, curves: curves))

            // 回收尾部空泳道(注意 lanes 是 [String?],last 为 String??,需双重解包)
            while let last = lanes.last, last == nil {
                lanes.removeLast()
            }
        }
        return (rows, maxLane + 1)
    }
}
