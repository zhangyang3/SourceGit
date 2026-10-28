import Foundation

// MARK: - 远端流程集成测试(本地裸仓库作为远端,与真实远端同代码路径)

/// 建立拓扑:origin(工作仓库,模拟同事机器)+ 裸仓库(服务器)+ 工作克隆(被测端)。
private func makeOriginAndClone() throws -> (origin: FixtureRepo, clone: GitRepository, cloneDir: String) {
    let origin = try FixtureRepo()
    try origin.commit("a.txt", content: "base\n", message: "c1")

    // 裸仓库作为远端服务器
    let bareDir = NSTemporaryDirectory() + "sourcegit-tests-bare-\(UUID().uuidString)"
    _ = try Git.run(["clone", "--bare", origin.dir, bareDir])

    // origin 关联裸仓库(模拟同事机器的推送路径)
    _ = try Git.run(["remote", "add", "origin", bareDir], cwd: origin.dir)

    // 被测克隆
    let cloneDir = NSTemporaryDirectory() + "sourcegit-tests-remoteclone-\(UUID().uuidString)"
    _ = try Git.run(["clone", bareDir, cloneDir])
    return (origin, try GitRepository.open(cloneDir), cloneDir)
}

func testFetchAndPull() throws {
    let (origin, clone, cloneDir) = try makeOriginAndClone()

    // origin 新增提交并推送到服务器(裸仓库)
    try origin.commit("b.txt", content: "new on origin\n", message: "origin-c2")
    try origin.git("push", "origin", "main")
    let originHead = try origin.git("rev-parse", "main")

    let remoteBefore = try clone.remoteBranchesSnapshot("origin/main")
    try assertTrue(remoteBefore != originHead, "fetch 前远程分支落后于 origin")

    try clone.fetch("origin")
    let remoteAfter = try clone.remoteBranchesSnapshot("origin/main")
    try assertEq(remoteAfter, originHead, "fetch 后远程分支与服务器一致")

    var st = try clone.status()
    try assertEq(st.behind, 1, "fetch 后 behind=1")

    // pull 快进
    try clone.pull(remote: "origin", branch: "main", rebase: false, ffOnly: true)
    st = try clone.status()
    try assertEq(st.behind, 0, "pull 后 behind=0")
    let cloneHead = try Git.run(["rev-parse", "HEAD"], cwd: cloneDir).sg_trimmed()
    try assertEq(cloneHead, originHead, "pull 后与 origin 对齐")
}

func testPushFlow() throws {
    let (_, clone, cloneDir) = try makeOriginAndClone()

    // 克隆侧新提交并推送
    try "pushed\n".write(toFile: cloneDir + "/a.txt", atomically: true, encoding: .utf8)
    _ = try Git.run(["add", "-A"], cwd: cloneDir)
    _ = try Git.run(["commit", "-m", "clone-c2"], cwd: cloneDir)
    let cloneHead = try Git.run(["rev-parse", "HEAD"], cwd: cloneDir).sg_trimmed()

    try clone.push(remote: "origin", branch: "main", setUpstream: false, forceWithLease: false)

    // origin(裸仓库)的 main 应与 cloneHead 一致
    let bareURL = try clone.remotes()[0].fetchURL
    let bareHead = try Git.run(["rev-parse", "main"], cwd: bareURL).sg_trimmed()
    try assertEq(bareHead, cloneHead, "push 后远端 main 与本地一致")

    // 推送新分支 + 上游设置
    try clone.createBranch("feature", from: "main", checkout: false)
    try clone.push(remote: "origin", branch: "feature", setUpstream: true, forceWithLease: false)
    let local = try clone.branches().local
    let feature = local.first { $0.name == "feature" }
    try assertEq(feature?.upstream, "origin/feature", "push -u 设置上游")
}

func testPushForceWithLease() throws {
    let (_, clone, cloneDir) = try makeOriginAndClone()

    // 本地 amend 出分叉
    try "amended\n".write(toFile: cloneDir + "/a.txt", atomically: true, encoding: .utf8)
    _ = try Git.run(["add", "-A"], cwd: cloneDir)
    _ = try Git.run(["commit", "--amend", "-m", "amended"], cwd: cloneDir)
    let cloneHead = try Git.run(["rev-parse", "HEAD"], cwd: cloneDir).sg_trimmed()
    // 普通推送应失败(非快进)
    try assertThrows("分叉后普通 push 应被拒绝") {
        try clone.push(remote: "origin", branch: "main", setUpstream: false, forceWithLease: false)
    }
    // force-with-lease 成功
    try clone.push(remote: "origin", branch: "main", setUpstream: false, forceWithLease: true)
    let bareURL = try clone.remotes()[0].fetchURL
    let bareHead = try Git.run(["rev-parse", "main"], cwd: bareURL).sg_trimmed()
    try assertEq(bareHead, cloneHead, "强推后远端与本地一致")
}

func testMergeConflictAndAbort() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "base\n", message: "c1")
    try repo.git("switch", "-c", "feat")
    try repo.commit("a.txt", content: "feat version\n", message: "feat-c2")
    try repo.git("switch", "main")
    try repo.commit("a.txt", content: "main version\n", message: "main-c2")

    let r = try repo.open()
    try assertThrows("冲突合并应报错") {
        try r.merge("feat", noFF: false)
    }
    try assertTrue(r.mergeInProgress, "MERGE_HEAD 存在")
    let st = try r.status()
    try assertTrue(st.entries.contains { $0.isConflicted }, "存在冲突条目")
    try assertTrue(st.unstaged.contains { $0.path == "a.txt" && $0.isConflicted })

    try r.abortMerge()
    try assertTrue(!r.mergeInProgress, "终止后恢复")
    let st2 = try r.status()
    try assertEq(st2.entries.count, 0, "终止合并后工作区干净")
}

func testCheckoutRemoteBranch() throws {
    let (origin, clone, _) = try makeOriginAndClone()
    // origin 建分支 feat 并推送
    try origin.git("switch", "-c", "feat")
    try origin.commit("c.txt", content: "feat\n", message: "feat-c2")
    try origin.git("push", "-u", "origin", "feat")

    try clone.fetch("origin")
    let remoteFeat = try clone.branches().remote.first { $0.shortName == "feat" }
    try assertTrue(remoteFeat != nil, "fetch 后存在 origin/feat")

    try clone.checkoutRemote(remoteFeat!.name)
    let current = try clone.currentBranch()
    try assertEq(current, "feat", "切换远程分支自动创建同名本地分支")
}

func testBranchDeleteRenameForce() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    try repo.git("switch", "-c", "feature")
    try repo.commit("b.txt", content: "unmerged\n", message: "feature-only")
    try repo.git("switch", "main")

    let r = try repo.open()
    let feature = try r.branches().local.first { $0.name == "feature" }!

    // 未合并分支 -d 失败
    var failed = false
    do { try r.deleteBranch(feature, force: false) } catch { failed = true }
    try assertTrue(failed, "未合并分支不允许普通删除")

    // -D 强制删除成功
    try r.deleteBranch(feature, force: true)
    let names = try r.branches().local.map(\.name)
    try assertTrue(!names.contains("feature"), "强删后不存在")

    // 重命名
    try r.createBranch("to-rename", from: nil, checkout: false)
    try r.renameBranch("to-rename", to: "renamed")
    let names2 = try r.branches().local.map(\.name)
    try assertTrue(names2.contains("renamed") && !names2.contains("to-rename"), "重命名生效")
}

// MARK: - 辅助

private extension GitRepository {
    func remoteBranchesSnapshot(_ name: String) throws -> String {
        try branches().remote.first { $0.name == name }?.hash ?? ""
    }
}
