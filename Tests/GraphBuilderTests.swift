import Foundation

/// 泳道算法纯单元测试(不依赖真实仓库,手工构造提交)。
private func commit(
    _ hash: String, parents: [String],
    subject: String = ""
) -> GitCommit {
    GitCommit(
        hash: hash, shortHash: String(hash.prefix(7)),
        parents: parents,
        authorName: "tester", authorEmail: "t@t",
        authorDate: Date(timeIntervalSince1970: 0),
        commitDate: Date(timeIntervalSince1970: 0),
        message: subject.isEmpty ? hash : subject
    )
}

func testGraphLinear() throws {
    let c1 = commit("c1", parents: [])
    let c2 = commit("c2", parents: ["c1"])
    let c3 = commit("c3", parents: ["c2"])
    let (rows, laneCount) = GraphBuilder.build([c3, c2, c1])

    try assertEq(laneCount, 1)
    try assertEq(rows.map(\.lane), [0, 0, 0])
    try assertEq(rows[0].curves.count, 1, "每个普通提交一条连线")
    try assertEq(rows[0].curves[0].from, 0)
    try assertEq(rows[0].curves[0].to, 0)
    try assertEq(rows[2].curves.count, 0, "根提交无连线")
}

func testGraphMerge() throws {
    // c1 ← c2(主线), c1 ← c3(分支), c2+c3 ← M
    let c1 = commit("c1", parents: [])
    let c2 = commit("c2", parents: ["c1"])
    let c3 = commit("c3", parents: ["c1"])
    let m = commit("m", parents: ["c2", "c3"])
    let (rows, laneCount) = GraphBuilder.build([m, c2, c3, c1]) // topo-order

    try assertEq(laneCount, 2)
    // 主线恒在 0 号泳道,分支提交在 1 号泳道(与 git --graph 一致)
    try assertEq(rows.map(\.lane), [0, 0, 1, 0], "主线在 0 号泳道,分支在 1 号泳道")
    try assertEq(rows[0].curves.count, 2, "合并提交两条连线")
    try assertEq(rows[0].curves.map(\.to).sorted(), [0, 1])
    // c3 在 1 号泳道,其父 c1 已由主线等待 → 该泳道延续到 c1 所在行再汇入
    try assertEq(rows[2].curves.count, 1)
    try assertEq(rows[2].curves[0].from, 1)
    // c1 同时被两条泳道等待 → 在 c1 所在行画收敛曲线(上半段)
    try assertEq(rows[3].convergences.count, 1, "c1 行应有一条汇合收敛线")
    try assertEq(rows[3].convergences[0].from, 1)
    try assertEq(rows[3].convergences[0].to, 0)
    // 根提交之后没有等待的泳道
    try assertEq(rows[3].after, [])
}

func testGraphSideBranchConvergesIntoMainline() throws {
    // main: a → b;side: a → s;两条泳道在 a 汇合
    let a = commit("a", parents: [])
    let b = commit("b", parents: ["a"])
    let s = commit("s", parents: ["a"])
    let (rows, laneCount) = GraphBuilder.build([b, s, a])

    try assertEq(rows.map(\.lane), [0, 1, 0], "主线始终在 0 号泳道")
    try assertEq(laneCount, 2)
    try assertTrue(rows[2].convergences.contains { $0.from == 1 && $0.to == 0 },
                  "侧道在根提交处汇入主线")
}

func testGraphOctopusMerge() throws {
    let c1 = commit("c1", parents: [])
    let c2 = commit("c2", parents: ["c1"])
    let c3 = commit("c3", parents: ["c1"])
    let c4 = commit("c4", parents: ["c1"])
    let m = commit("m", parents: ["c2", "c3", "c4"])
    let (rows, laneCount) = GraphBuilder.build([m, c2, c3, c4, c1])

    try assertEq(laneCount, 3)
    try assertEq(rows[0].curves.count, 3, "章鱼合并三条连线")
    try assertEq(rows.map(\.lane), [0, 0, 1, 2, 0])
}

func testGraphOrphanRoots() throws {
    // 两个不相连的根:a1 处理完后泳道被回收,b1 复用泳道 0(视觉上互不相连)
    let a1 = commit("a1", parents: [])
    let b1 = commit("b1", parents: [])
    let (rows, laneCount) = GraphBuilder.build([a1, b1])

    try assertEq(rows.map(\.lane), [0, 0])
    try assertEq(laneCount, 1)
    try assertEq(rows[0].after, [], "a1 行下方无等待泳道")
    try assertEq(rows[1].curves.count, 0, "根提交无连线")
}
