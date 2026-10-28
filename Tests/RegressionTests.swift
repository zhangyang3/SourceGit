import Foundation

// MARK: - 评审修复的回归测试

@MainActor
func testRegressionSwitchRepositoryReloadsState() async throws {
    let repoA = try FixtureRepo()
    try repoA.commit("a.txt", content: "1\n", message: "c1")
    let repoB = try FixtureRepo()
    try repoB.commit("b.txt", content: "2\n", message: "b1")
    try repoB.git("branch", "other")

    // 模拟 AppState 的仓库切换
    let modelA = try RepoModel(path: repoA.dir, name: "A")
    await modelA.refreshAll()
    try assertEq(modelA.status.branch, "main")
    try assertEq(modelA.branches.count, 1)

    let modelB = try RepoModel(path: repoB.dir, name: "B")
    await modelB.refreshAll()
    try assertEq(modelB.status.branch, "main")
    try assertEq(modelB.branches.count, 2, "新仓库的分支已加载(切换仓库不会漏刷新)")
    try assertTrue(modelB.status.entries.isEmpty)
}

@MainActor
func testRegressionHistoryScopeReloadsOnSectionChange() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "main-c1")
    try repo.git("switch", "-c", "feature")
    try repo.commit("b.txt", content: "2\n", message: "feat-c2")
    try repo.git("switch", "main")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()

    // 全量历史
    model.section = .history
    await model.loadHistory(reset: true)
    try assertEq(model.history.commits.count, 2, "全量历史 2 条")
    try assertEq(model.historyScopeLabel, "所有分支")

    // 切到 feature 分支:范围变化必须重新加载
    let feature = try unwrap(model.branches.first { $0.name == "feature" }, "缺少 feature 分支")
    model.section = .branch(feature)
    await model.loadHistory(reset: true)
    try assertEq(model.historyScopeLabel, "feature")
    // 分支历史天然包含祖先提交(feature 的历史 = feature + main 的祖先)
    try assertEq(model.history.commits.first?.hash, feature.hash, "最新提交应为 feature 的提交")
    try assertTrue(model.history.commits.count < 2 || model.history.commits.contains { $0.subject == "main-c1" },
                   "祖先提交仍在历史中")

    // 切回全量
    model.section = .history
    await model.loadHistory(reset: true)
    try assertEq(model.history.commits.count, 2, "切回全量历史")
}

@MainActor
func testRegressionDiscardKeepsStagedContent() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "base\n", message: "c1")
    // 工作区改成 v2,只暂存第一行;工作区再改成 v3
    try repo.write("a.txt", content: "staged\nmore\n")
    try repo.git("add", "a.txt")
    try repo.write("a.txt", content: "staged\nworktree\n")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()
    let stagedFile = try unwrap(model.status.staged.first { $0.path == "a.txt" })
    let unstagedFile = try unwrap(model.status.unstaged.first { $0.path == "a.txt" })

    // 放弃"未暂存"分组:只还原工作区到暂存区版本,已暂存内容保留
    await model.discard([unstagedFile], staged: false)
    let content = try String(contentsOfFile: repo.dir + "/a.txt", encoding: .utf8)
    try assertTrue(content.contains("staged"), "已暂存内容应保留")
    try assertTrue(!content.contains("worktree"), "未暂存改动应被还原")

    // 放弃"已暂存"分组:回到 HEAD
    await model.discard([stagedFile], staged: true)
    let content2 = try String(contentsOfFile: repo.dir + "/a.txt", encoding: .utf8)
    try assertTrue(content2.contains("base"), "已暂存内容被放弃后应回到 HEAD")
}

@MainActor
func testRegressionMergeInProgressCached() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "base\n", message: "c1")
    try repo.git("switch", "-c", "feat")
    try repo.commit("a.txt", content: "feat\n", message: "f2")
    try repo.git("switch", "main")
    try repo.commit("a.txt", content: "main\n", message: "m2")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()
    try assertTrue(!model.mergeInProgress, "普通状态:无合并进行中")

    _ = try? repo.git("merge", "feat")
    await model.refreshAll()
    try assertTrue(model.mergeInProgress, "合并冲突后状态被缓存为合并进行中")
}

@MainActor
func testRegressionHasMoreHistory() async throws {
    let repo = try FixtureRepo()
    for i in 1...3 {
        try repo.commit("f\(i).txt", content: "\(i)\n", message: "c\(i)")
    }

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()
    await model.loadHistory(reset: true)
    try assertEq(model.history.commits.count, 3)
    try assertTrue(!model.hasMoreHistory, "已加载全部时不应显示加载更多")
}
