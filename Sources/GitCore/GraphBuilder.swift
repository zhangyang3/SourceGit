import Foundation

/// 提交图的一行:提交所在的泳道,以及本行上下半段的连线数据。
public struct CommitGraphRow: Identifiable, Sendable {
    public var id: String { commit.id }
    public let commit: GitCommit
    /// 本提交所在泳道(0 号为主泳道/主线)
    public let lane: Int
    /// 进入本行(上半段)时有提交等待的泳道
    public let before: [Int]
    /// 离开本行(下半段)时有提交等待的泳道
    public let after: [Int]
    /// 向下连线:本提交泳道 → 父提交所在泳道
    public let curves: [(from: Int, to: Int)]
    /// 向上收敛连线:并入本提交的泳道 → 本提交泳道(绘制于上半段)
    public let convergences: [(from: Int, to: Int)]
}

/// 提交图泳道(lane)算法。
///
/// 模型与 git 的 `--graph` 一致:
/// - **0 号泳道恒为主泳道**(first-parent 主线),主线提交始终排在最左列;
/// - 合并提交的第 2、3…个父提交会在右侧开启新的侧泳道;
/// - 侧泳道的提交若与主线(或另一侧泳道)汇合,汇合处画一条收敛曲线,
///   该侧泳道在此终止;
/// - 父提交同时被多个泳道等待时,取最左侧泳道绘制,其余泳道画收敛曲线。
///
/// 输入需按 `--topo-order` 排列(子提交在前)。
public enum GraphBuilder {

    public static func build(_ commits: [GitCommit]) -> (rows: [CommitGraphRow], laneCount: Int) {
        // lanes[0] 为主泳道,lanes[1...] 为侧泳道;值为该泳道正在等待的提交哈希
        var lanes: [String?] = []
        var rows: [CommitGraphRow] = []
        var maxLane = 0

        for commit in commits {
            let before = lanes.indices.filter { lanes[$0] != nil }

            // 1) 定位本提交所在泳道:主线优先,其次最左侧的等待泳道;都没有则是新分支
            let myLane: Int
            if let idx = lanes.firstIndex(where: { $0 == commit.hash }) {
                myLane = idx
            } else {
                lanes.append(commit.hash)
                myLane = lanes.count - 1
            }
            maxLane = max(maxLane, myLane)

            // 2) 同一提交被多个泳道等待 → 其余泳道在此汇合(收敛曲线画在本行上半段)
            var convergences: [(from: Int, to: Int)] = []
            for j in lanes.indices where j != myLane && lanes[j] == commit.hash {
                convergences.append((from: j, to: myLane))
            }

            // 3) 释放所有等待该提交的泳道
            for j in lanes.indices where lanes[j] == commit.hash {
                lanes[j] = nil
            }

            // 4) 分配父提交
            var curves: [(from: Int, to: Int)] = []
            for (index, parent) in commit.parents.enumerated() {
                if index == 0 {
                    // 第一个父提交继承当前泳道(主线因此保持在 0 号泳道)。
                    // 若它已被别的泳道等待,那些泳道的竖线会继续向下,
                    // 在父提交所在行以收敛曲线并入。
                    lanes[myLane] = parent
                    curves.append((from: myLane, to: myLane))
                    continue
                }
                // 额外的父提交:已在某泳道等待 → 并入该泳道;否则新开一条侧泳道
                if let k = lanes.firstIndex(where: { $0 == parent }) {
                    curves.append((from: myLane, to: k))
                    continue
                }
                lanes.append(parent)
                let slot = lanes.count - 1
                lanes[slot] = parent
                curves.append((from: myLane, to: slot))
            }

            let after = lanes.indices.filter { lanes[$0] != nil }
            rows.append(
                CommitGraphRow(
                    commit: commit,
                    lane: myLane,
                    before: before,
                    after: after,
                    curves: curves,
                    convergences: convergences
                )
            )

            // 5) 回收末尾空泳道,保持图宽紧凑
            while let last = lanes.last, last == nil {
                lanes.removeLast()
            }
        }
        return (rows, maxLane + 1)
    }
}
