import Foundation

// MARK: - 版本比较

func testVersionCompare() throws {
    try assertEq(compareVersions("0.1.0", "0.0.9"), 1, "0.1.0 > 0.0.9")
    try assertEq(compareVersions("v0.1.0", "0.1.0"), 0, "v 前缀忽略")
    try assertEq(compareVersions("0.2.0", "0.10.0"), -1, "数值比较而非字符串")
    try assertEq(compareVersions("1.0", "1.0.0"), 0, "缺省段视为 0")
    try assertEq(compareVersions("1.2.3", "1.2.4"), -1)
    try assertEq(compareVersions("2.0.0", "1.99.99"), 1)
    try assertEq(compareVersions("v10.0.1", "9.9.9"), 1)
}

// MARK: - Release JSON 解析

func testReleaseParsing() throws {
    let json = """
    {
      "tag_name": "v0.2.0",
      "name": "SourceGit 0.2.0",
      "body": "## 新增\\n- 历史视图\\n- 远端操作",
      "html_url": "https://github.com/zhangyang3/SourceGit/releases/tag/v0.2.0",
      "draft": false,
      "prerelease": false,
      "assets": []
    }
    """.data(using: .utf8)!
    let release = try JSONDecoder().decode(AppRelease.self, from: json)
    try assertEq(release.tagName, "v0.2.0")
    try assertEq(release.displayVersion, "0.2.0")
    try assertEq(release.htmlURL, "https://github.com/zhangyang3/SourceGit/releases/tag/v0.2.0")
    try assertTrue(release.body?.contains("历史视图") == true, "说明正文")
    try assertTrue(release.body?.contains("\\n") == false, "换行已转义为真实换行")
}

// MARK: - 自动检查频率

func testShouldAutoCheckFrequency() throws {
    let now = Date()
    try assertTrue(shouldAutoCheck(autoCheck: false, frequency: .daily, lastCheck: nil, now: now) == false, "关闭自动检查")
    try assertTrue(shouldAutoCheck(autoCheck: true, frequency: .daily, lastCheck: nil, now: now), "从未检查过")
    try assertTrue(shouldAutoCheck(autoCheck: true, frequency: .daily, lastCheck: now, now: now) == false, "同一天内不重复")
    try assertTrue(shouldAutoCheck(autoCheck: true, frequency: .daily, lastCheck: now.addingTimeInterval(-90_000), now: now), "超过一天")
    try assertTrue(shouldAutoCheck(autoCheck: true, frequency: .weekly, lastCheck: now.addingTimeInterval(-8 * 86_400), now: now), "超过一周")
    try assertTrue(shouldAutoCheck(autoCheck: true, frequency: .weekly, lastCheck: now.addingTimeInterval(-86_400), now: now) == false, "一周内")
    try assertTrue(shouldAutoCheck(autoCheck: true, frequency: .launch, lastCheck: now, now: now), "每次启动都检查")
}

// MARK: - AppVersion 有效性

func testAppVersionFormat() throws {
    let v = AppVersion.effective
    try assertTrue(v.split(separator: ".").count == 3, "三段式版本号: \(v)")
    try assertTrue(compareVersions(v, "0.0.1") >= 0, "版本号有效")
}
