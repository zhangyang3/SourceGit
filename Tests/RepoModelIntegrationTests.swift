import Foundation

// MARK: - UI 状态机集成测试
//
// 直接驱动界面层真实的 RepoModel(与 App 走同一份代码),
// 针对临时仓库跑完整流程:打开仓库 → 状态 → 暂存 → 提交 → 历史 → 提交详情 →
// 差异加载 → 分支/远端/贮藏操作 → 更新配置。

@MainActor
func testModelOpenRepoAndRefresh() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "line1\n", message: "c1")
    try repo.write("a.txt", content: "line1\nline2\n")
    try repo.write("new.md", content: "# 新文件\n")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()

    try assertEq(model.status.branch, "main", "分支名")
    try assertEq(model.status.entries.count, 2, "两个变更条目")
    try assertEq(model.status.staged.count, 0, "初始无暂存")
    try assertEq(model.status.unstaged.count, 2, "两个未暂存")
    try assertEq(model.branches.map(\.name), ["main"], "本地分支")
    try assertEq(model.tags.count, 0)
    try assertEq(model.stashes.count, 0)
    try assertTrue(!model.isBusy, "刷新后不处于忙状态")
    try assertTrue(!model.busyOverlayVisible, "后台刷新不显示全屏遮罩")
}

@MainActor
func testModelStageAndCommit() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "line1\n", message: "c1")
    try repo.write("a.txt", content: "line1\nline2\n")
    try repo.write("b.txt", content: "new file\n")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()

    // 暂存两个文件(经由状态机入口)
    model.stage(["a.txt", "b.txt"])
    try await MiniTest.waitUntil { !model.isBusy }
    try assertEq(model.status.staged.count, 2, "两个文件已暂存")

    // 提交(等待式)
    model.commitMessage = "集成测试提交"
    await model.commit()
    try assertTrue(model.lastError == nil, "提交无错误: \(model.lastError?.message ?? "")")
    try assertEq(model.status.staged.count, 0, "提交后暂存区清空")
    try assertEq(model.commitMessage, "", "提交信息已清空")

    // 历史应包含新提交
    await model.loadHistory()
    try assertEq(model.history.commits.count, 2, "两条提交")
    try assertEq(model.history.commits[0].subject, "集成测试提交", "最新提交在首位")
    try assertTrue(model.history.commits[0].refs.contains { $0.kind == .currentHead }, "HEAD 装饰")
}

@MainActor
func testModelSelectFileAndLoadDiff() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "a\nb\nc\n", message: "c1")
    try repo.write("a.txt", content: "a\nx\nc\n")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()

    let file = try unwrap(model.status.unstaged.first { $0.path == "a.txt" })
    model.select(file, staged: false)
    await model.loadFileDiff()

    try assertEq(model.fileDiff.count, 1, "一个文件的差异")
    try assertEq(model.fileDiff[0].displayName, "a.txt")
    try assertEq(model.fileDiff[0].adds, 1)
    try assertEq(model.fileDiff[0].dels, 1)
    try assertTrue(!model.busyOverlayVisible, "读取差异不显示全屏遮罩")
}

@MainActor
func testModelHistoryDetailAndFileDiff() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    try repo.commit("a.txt", content: "1\n2\n", message: "c2")
    try repo.commit("b.txt", content: "new\n", message: "c3")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()
    await model.loadHistory()

    // 选中一个提交 → 加载变更清单
    model.selectedCommitID = model.history.commits[0].id
    await model.loadCommitDetail()
    try assertEq(model.commitChanges.count, 1, "一个变更文件")
    try assertEq(model.commitChanges[0].path, "b.txt")
    try assertEq(model.commitChanges[0].kind, .added)

    // 选中文件 → 加载差异
    model.selectedCommitPath = model.commitChanges[0].path
    await model.loadSelectedCommitFileDiff()
    try assertEq(model.selectedCommitDiff.count, 1, "选中文件差异")
    try assertEq(model.selectedCommitDiff[0].adds, 1)

    // 重复加载应命中 LRU 缓存且结果一致
    await model.loadSelectedCommitFileDiff()
    try assertEq(model.selectedCommitDiff.count, 1, "二次加载(缓存)结果一致")
}

@MainActor
func testModelBranchOperations() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()

    // 建分支并切换
    let ok = await model.performAsync("创建分支") { try $0.createBranch("feature", from: "main", checkout: true) }
    try assertTrue(ok, "创建分支成功")
    try assertEq(model.status.branch, "feature", "已切换到新分支")

    // 切回 main
    let mainBranch = try unwrap(model.branches.first { $0.name == "main" })
    model.checkout(mainBranch)
    try await MiniTest.waitUntil { !model.isBusy }
    try assertEq(model.status.branch, "main", "切回 main")

    // 重命名
    let feature = try unwrap(model.branches.first { $0.name == "feature" })
    let renamed = await model.performAsync("重命名") { try $0.renameBranch(feature.name, to: "feat-x") }
    try assertTrue(renamed, "重命名成功")
    try assertTrue(model.branches.contains { $0.name == "feat-x" }, "新名字出现在分支列表")
}

@MainActor
func testModelStashFlow() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    try repo.write("a.txt", content: "2\n")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()

    let stashed = await model.performAsync("贮藏") { try $0.stashSave(message: "集成贮藏", includeUntracked: true, keepIndex: false) }
    try assertTrue(stashed, "贮藏成功")
    try assertEq(model.stashes.count, 1, "贮藏列表有一项")
    try assertTrue(model.stashes[0].subject.contains("集成贮藏"), "贮藏主题")
    try assertEq(model.status.entries.count, 0, "贮藏后工作区干净")

    // 应用贮藏
    let stash = model.stashes[0]
    let applied = await model.performAsync("应用贮藏") { try $0.stashApply(stash, pop: false) }
    try assertTrue(applied, "应用贮藏成功")
    try assertEq(model.status.unstaged.count, 1, "改动已恢复")
}

@MainActor
func testModelEmptyCommitIsRejected() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()

    // 空提交信息
    model.commitMessage = "   "
    await model.commit()
    try assertTrue(model.lastError != nil, "空提交信息应被拒绝")
    try assertEq(model.lastError?.title, "无法提交")

    // 无暂存内容
    model.lastError = nil
    model.commitMessage = "没有暂存"
    await model.commit()
    try assertTrue(model.lastError != nil, "无暂存内容应被拒绝")
}

@MainActor
func testModelUpdateSettingsPersistence() throws {
    let suite = "SourceGitTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    let settings = UpdateSettings(defaults: defaults)
    try assertTrue(settings.autoCheck, "默认开启自动检查")
    try assertEq(settings.frequency, .weekly, "默认每周检查")

    settings.autoCheck = false
    settings.frequency = .daily
    settings.skippedVersion = "v9.9.9"

    let reloaded = UpdateSettings(defaults: defaults)
    try assertTrue(!reloaded.autoCheck, "开关已持久化")
    try assertEq(reloaded.frequency, .daily, "频率已持久化")
    try assertEq(reloaded.skippedVersion, "v9.9.9", "跳过版本已持久化")

    reloaded.clearSkipped()
    try assertTrue(UpdateSettings(defaults: defaults).skippedVersion == nil, "清除跳过版本已持久化")
}

@MainActor
func testModelDiffLRUCacheEviction() throws {
    let cache = DiffLRUCache(capacity: 3)
    let file = DiffFile(oldPath: "a", newPath: "a", kind: .modified, oldMode: nil, newMode: nil, renameScore: nil, hunks: [])
    for i in 0..<5 {
        cache.set("k\(i)", value: [file])
    }
    try assertEq(cache.count, 3, "缓存不超过上限")
    try assertTrue(cache.get("k0") == nil, "最早的条目已被淘汰")
    try assertTrue(cache.get("k4") != nil, "最新条目仍在")
}

@MainActor
func testModelPollingDoesNotBlockUI() async throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")

    let model = try RepoModel(path: repo.dir, name: "test")
    await model.refreshAll()
    // 模拟一次轮询触发的后台刷新
    await model.refreshStatus(allowWhileBusy: false)
    try assertTrue(!model.busyOverlayVisible, "轮询刷新不显示遮罩")
    try assertTrue(!model.isBusy, "刷新结束后不忙")
}
