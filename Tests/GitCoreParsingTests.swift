import Foundation

// MARK: - status 解析

func testStatusBasicParsing() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "line1\n", message: "init")
    try repo.write("a.txt", content: "line1\nline2\n")           // 第一处修改
    try repo.git("add", "a.txt")                                 // 暂存该修改
    try repo.write("a.txt", content: "line1\nline2\nline3\n")    // 再改 → 部分暂存
    try repo.write("b.txt", content: "new file")                 // 未跟踪

    let st = try repo.open().status()

    try assertEq(st.branch, "main", "分支名")
    try assertTrue(st.upstream == nil, "无上游")
    try assertTrue(!st.isDetached, "非分离头")
    try assertTrue(!st.isEmptyRepo, "非空仓库")
    try assertTrue(st.headHash.count == 40, "HEAD 哈希长度")

    try assertEq(st.entries.count, 2, "条目数")
    try assertEq(st.staged.count, 1, "已暂存数")
    try assertEq(st.staged[0].path, "a.txt")
    try assertEq(st.staged[0].stagedKind, .modified)
    try assertTrue(st.staged[0].isWorktreeEntry, "a.txt 同时也在未暂存分组(部分暂存)")

    try assertEq(st.unstaged.count, 2, "未暂存数(a.txt 修改 + b.txt 未跟踪)")
    let untracked = st.unstaged.first { $0.isUntracked }
    try assertTrue(untracked != nil, "存在未跟踪条目")
    try assertEq(untracked?.path, "b.txt")
    try assertEq(untracked?.worktreeKind, .untracked)
}

func testStatusChinesePath() throws {
    let repo = try FixtureRepo()
    try repo.commit("中文 目录/文件 名字.swift", content: "print(1)\n", message: "init")
    try repo.write("中文 目录/文件 名字.swift", content: "print(2)\n")

    let st = try repo.open().status()
    try assertEq(st.unstaged.first?.path, "中文 目录/文件 名字.swift", "中文路径应原样保留")
}

func testStatusRenameParsing() throws {
    let repo = try FixtureRepo()
    try repo.commit("old.txt", content: "some content here\n", message: "init")
    try repo.git("mv", "old.txt", "new.txt")

    let st = try repo.open().status()
    try assertEq(st.staged.count, 1)
    let f = st.staged[0]
    try assertEq(f.indexStatus, "R", "重命名状态字符")
    try assertEq(f.oldPath, "old.txt")
    try assertEq(f.path, "new.txt")
    try assertEq(f.stagedKind, .renamed)
}

func testStatusEmptyRepo() throws {
    let repo = try FixtureRepo()
    let st = try repo.open().status()
    try assertTrue(st.isEmptyRepo, "空仓库标记")
    try assertEq(st.branch, "main", "未出生分支名")
    try assertEq(st.entries.count, 0)
    try assertEq(st.headHash, "", "无 HEAD 哈希")

    let history = try repo.open().history()
    try assertEq(history.commits.count, 0, "空仓库历史为空,不抛错")
}

func testStatusDetachedHead() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    try repo.commit("a.txt", content: "2\n", message: "c2")
    try repo.git("checkout", "HEAD~1")

    let st = try repo.open().status()
    try assertTrue(st.isDetached, "分离头指针")
    try assertTrue(st.branch == nil)
    try assertTrue(st.headHash.count == 40)
}

func testStatusAheadBehind() throws {
    let origin = try FixtureRepo()
    try origin.commit("a.txt", content: "1\n", message: "c1")

    let cloneDir = NSTemporaryDirectory() + "sourcegit-tests-clone-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: cloneDir) }
    _ = try Git.run(["clone", origin.dir, cloneDir])

    let clone = try GitRepository.open(cloneDir)
    let st = try clone.status()
    try assertEq(st.upstream, "origin/main", "克隆仓库有上游")
    try assertTrue(!st.hasUpstreamDelta, "初始无 ahead/behind")

    try "2\n".write(toFile: cloneDir + "/a.txt", atomically: true, encoding: .utf8)
    _ = try Git.run(["add", "-A"], cwd: cloneDir)
    _ = try Git.run(["commit", "-m", "extra"], cwd: cloneDir)

    let st2 = try clone.status()
    try assertEq(st2.ahead, 1, "领先 1")
    try assertEq(st2.behind, 0)
}

// MARK: - history / refs

func testHistoryLinear() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    try repo.commit("a.txt", content: "2\n", message: "c2")
    try repo.commit("a.txt", content: "3\n", message: "c3")

    let h = try repo.open().history()
    try assertEq(h.commits.count, 3)
    try assertEq(h.laneCount, 1, "线性历史只有一条泳道")
    try assertTrue(h.commits[0].parents.count == 1, "最新提交有父")
    try assertTrue(h.commits[2].parents.isEmpty, "根提交无父")
    try assertEq(h.commits[0].subject, "c3", "最新在前")
    try assertEq(h.commits[0].message, "c3")
    try assertTrue(h.commits[0].shortHash.count >= 7)
    try assertEq(h.commits[0].authorName, "SourceGit 测试")
}

func testHistoryRefsAndTags() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    try repo.git("tag", "v-light")
    try repo.git("tag", "-a", "v-ann", "-m", "附注标签")

    let h = try repo.open().history()
    let refs = h.commits[0].refs
    try assertTrue(refs.contains { $0.kind == .currentHead && $0.name == "main" }, "HEAD 装饰")
    try assertTrue(refs.contains { $0.kind == .tag && $0.name == "v-light" }, "轻量标签")
    try assertTrue(refs.contains { $0.kind == .tag && $0.name == "v-ann" }, "附注标签")

    let tags = try repo.open().tags()
    try assertEq(tags.count, 2)
    try assertTrue(tags.allSatisfy { $0.hash == h.commits[0].hash }, "附注标签哈希应解引用到提交")
}

func testHistoryMergeAndGraph() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    try repo.git("switch", "-c", "feature")
    try repo.commit("b.txt", content: "feat\n", message: "c2-feature")
    try repo.git("switch", "main")
    try repo.commit("a.txt", content: "main\n", message: "c3-main")
    try repo.git("merge", "feature", "-m", "merge-feature")

    let h = try repo.open().history(scope: ["--all"], limit: 100)
    try assertEq(h.commits.count, 4, "4 个提交")
    try assertEq(h.laneCount, 2, "合并产生两条泳道")

    let merge = h.commits[0]
    try assertEq(merge.subject, "merge-feature")
    try assertEq(merge.parents.count, 2, "合并提交有两个父")
    try assertEq(h.rows[0].lane, 0, "合并提交在泳道 0")

    let featureCommit = h.commits.first { $0.subject == "c2-feature" }
    try assertTrue(featureCommit != nil)
    try assertEq(h.rows.first { $0.commit.subject == "c2-feature" }?.lane, 1, "特性分支提交在泳道 1")
}

func testHistoryMultiLineMessage() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "主题行\n\n正文第一行\n正文第二行\n")

    let h = try repo.open().history()
    try assertEq(h.commits[0].subject, "主题行")
    try assertEq(h.commits[0].body, "正文第一行\n正文第二行")
}

// MARK: - diff 解析

func testDiffWorktreeModified() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "a\nb\nc\n", message: "init")
    try repo.write("a.txt", content: "a\nx\nc\n")

    let files = try repo.open().diffWorktree()
    try assertEq(files.count, 1)
    let f = files[0]
    try assertEq(f.kind, .modified)
    try assertEq(f.oldPath, "a.txt")
    try assertEq(f.newPath, "a.txt")
    try assertEq(f.adds, 1)
    try assertEq(f.dels, 1)

    let hunk = f.hunks[0]
    try assertEq(hunk.lines.count, 4, "上下文2 + 删1 + 增1")
    let deleted = hunk.lines.first { $0.kind == .deleted }
    let added = hunk.lines.first { $0.kind == .added }
    try assertEq(deleted?.text, "b")
    try assertEq(deleted?.oldNumber, 2)
    try assertEq(added?.text, "x")
    try assertEq(added?.newNumber, 2)
}

func testDiffStagedNewFile() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "init")
    try repo.write("new.txt", content: "hello\n")
    try repo.git("add", "new.txt")

    let files = try repo.open().diffStaged()
    try assertEq(files.count, 1)
    try assertEq(files[0].kind, .added)
    try assertTrue(files[0].oldPath == nil, "新增文件无旧路径")
    try assertEq(files[0].newPath, "new.txt")
    try assertEq(files[0].adds, 1)
}

func testDiffStagedRename() throws {
    let repo = try FixtureRepo()
    try repo.commit("old.txt", content: "some long content\nsecond line\nthird line\n", message: "init")
    try repo.git("mv", "old.txt", "new.txt")

    let files = try repo.open().diffStaged()
    try assertEq(files.count, 1)
    try assertEq(files[0].kind, .renamed)
    try assertEq(files[0].oldPath, "old.txt")
    try assertEq(files[0].newPath, "new.txt")
    try assertTrue((files[0].renameScore ?? 0) > 50, "重命名相似度")
}

func testDiffDeletedFile() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "init")
    try repo.commit("b.txt", content: "keep\n", message: "c2")
    try repo.git("rm", "a.txt")
    try repo.git("commit", "-m", "remove a")

    let files = try repo.open().diffRange(from: "HEAD~1", to: "HEAD")
    try assertEq(files.count, 1)
    try assertEq(files[0].kind, .deleted)
    try assertTrue(files[0].newPath == nil)
    try assertEq(files[0].oldPath, "a.txt")
}

func testDiffBinary() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "init")
    try repo.write("bin.dat", data: Data([0x00, 0x01, 0xFF, 0xFE, 0x7F, 0x80, 0x33]))
    try repo.git("add", "bin.dat")

    let files = try repo.open().diffStaged()
    try assertEq(files.count, 1)
    try assertEq(files[0].kind, .binary)
    try assertEq(files[0].displayName, "bin.dat")
}

func testDiffCommitRootAndChild() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    let c1 = try repo.git("rev-parse", "HEAD")
    try repo.commit("a.txt", content: "2\n", message: "c2")
    let c2 = try repo.git("rev-parse", "HEAD")

    let root = try repo.open().diffCommit(c1)
    try assertEq(root.count, 1)
    try assertEq(root[0].kind, .added, "根提交对空树全为新增")

    let child = try repo.open().diffCommit(c2)
    try assertEq(child.count, 1)
    try assertEq(child[0].kind, .modified)
    try assertEq(child[0].dels, 1)
    try assertEq(child[0].adds, 1)
}

func testDiffUntrackedFile() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "init")
    try repo.write("fresh.md", content: "# 新文件\n内容\n")

    let files = try repo.open().diffUntracked("fresh.md")
    try assertEq(files.count, 1)
    try assertEq(files[0].kind, .added)
    try assertEq(files[0].adds, 2)
}

func testDiffPathFilter() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "init")
    try repo.write("a.txt", content: "2\n")
    try repo.write("b.txt", content: "new\n")

    let onlyA = try repo.open().diffWorktree("a.txt")
    try assertEq(onlyA.count, 1, "按路径过滤只返回 a.txt")
    try assertEq(onlyA[0].displayName, "a.txt")

    let all = try repo.open().diffWorktree()
    try assertEq(all.count, 1, "未跟踪文件不出现在 worktree diff 中")
}

func testDiffCommitChangesSummary() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "base\n", message: "c1")
    try repo.commit("new.txt", content: "n1\nn2\n", message: "c2")   // 新增
    try repo.git("mv", "new.txt", "renamed.txt")                      // 重命名
    try repo.git("commit", "-m", "rename")
    let head = try repo.git("rev-parse", "HEAD")

    // 根提交:全为新增
    let rootChanges = try repo.open().diffCommitChanges(try repo.git("rev-list", "--max-parents=0", "HEAD"))
    try assertEq(rootChanges.count, 1)
    try assertEq(rootChanges[0].kind, .added)
    try assertEq(rootChanges[0].adds, 1)

    // 重命名提交:R100 old new,行数 0/0
    let r = try repo.open()
    let renameChanges = try r.diffCommitChanges(head)
    try assertEq(renameChanges.count, 1)
    try assertEq(renameChanges[0].kind, .renamed)
    try assertEq(renameChanges[0].oldPath, "new.txt")
    try assertEq(renameChanges[0].path, "renamed.txt")
    try assertEq(renameChanges[0].adds, 0)
    try assertEq(renameChanges[0].dels, 0)
}

// MARK: - refs / remotes / stash

func testBranchesAndRemotes() throws {
    let origin = try FixtureRepo()
    try origin.commit("a.txt", content: "1\n", message: "c1")
    try origin.git("branch", "dev")

    let cloneDir = NSTemporaryDirectory() + "sourcegit-tests-clone2-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: cloneDir) }
    _ = try Git.run(["clone", origin.dir, cloneDir])
    let clone = try GitRepository.open(cloneDir)

    let (local, remote) = try clone.branches()
    try assertEq(local.map(\.name), ["main"], "克隆仓库本地仅有默认分支(dev 只在远端)")
    try assertEq(remote.map(\.name).sorted(), ["origin/dev", "origin/main"], "远程分支(不含 origin/HEAD)")
    let main = local.first { $0.name == "main" }!
    try assertEq(main.upstream, "origin/main", "main 的上游")

    let remotes = try clone.remotes()
    try assertEq(remotes.count, 1)
    try assertEq(remotes[0].name, "origin")
    try assertEq(remotes[0].fetchURL, origin.dir, "fetch URL 指向源仓库")
}

func testStashLifecycle() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    try repo.write("a.txt", content: "2\n")
    try repo.open().stashSave(message: "wip 中文")

    var stashes = try repo.open().stashes()
    try assertEq(stashes.count, 1)
    try assertTrue(stashes[0].subject.contains("wip"), "贮藏主题")
    try assertEq(stashes[0].index, 0)

    let st = try repo.open().status()
    try assertEq(st.entries.count, 0, "贮藏后工作区干净")

    try repo.open().stashApply(stashes[0], pop: true)
    let st2 = try repo.open().status()
    try assertEq(st2.unstaged.count, 1, "弹出后改动恢复")

    stashes = try repo.open().stashes()
    try assertEq(stashes.count, 0, "pop 后贮藏清空")
}

// MARK: - 工作副本写操作

func testStageUnstageCommitDiscard() throws {
    let repo = try FixtureRepo()
    try repo.commit("a.txt", content: "1\n", message: "c1")
    try repo.write("a.txt", content: "1\n2\n")
    try repo.write("b.txt", content: "new")

    let r = try repo.open()
    try r.stage(["a.txt", "b.txt"])
    try assertEq(r.status().staged.count, 2, "暂存两个文件")

    try r.unstage(["b.txt"])
    let st = try r.status()
    try assertEq(st.staged.count, 1)
    try assertTrue(st.unstaged.contains { $0.path == "b.txt" }, "b 回到未暂存(未跟踪)")

    try r.commit(message: "second")
    let after = try r.status()
    try assertEq(after.staged.count, 0)
    try assertEq(after.unstaged.count, 1, "提交后仅剩未跟踪 b.txt")
    try assertEq(try r.history().commits.count, 2)

    try repo.write("a.txt", content: "1\n2\n3\n")
    try r.discardWorktreeChanges(["a.txt"])
    try assertEq(r.status().entries.count, 1, "放弃修改后仅剩未跟踪 b.txt")

    try r.removeUntracked(["b.txt"])
    try assertEq(r.status().entries.count, 0, "删除未跟踪后完全干净")
}

// MARK: - 错误路径

func testOpenInvalidRepoFails() throws {
    let dir = NSTemporaryDirectory() + "sourcegit-tests-notrepo-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(atPath: dir) }
    try assertThrows("非 git 目录应抛错") {
        _ = try GitRepository.open(dir)
    }
}
