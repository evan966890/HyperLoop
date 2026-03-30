# Round 14 试用报告

**测试时间**: 2026-03-30
**测试对象**: scripts/hyper-loop.sh (git HEAD, 987 lines)
**语法检查**: bash -n PASS

---

## BDD 场景验证

| 场景 | 描述 | 结果 | 截图 |
|------|------|------|------|
| S001 | loop 命令启动死循环 | PASS | screenshots/round-14/S001-syntax-check.txt |
| S002 | auto_decompose 生成任务文件 | **FAIL** | screenshots/round-14/S002-auto-decompose.txt |
| S003 | Writer worktree 创建+trust+启动 | PASS | screenshots/round-14/S003-writer-worktree.txt |
| S004 | Writer 完成后 diff 正确 commit | PASS | screenshots/round-14/S004-writer-commit.txt |
| S005 | diff 审计拦截越界修改 | PASS | screenshots/round-14/S005-diff-audit.txt |
| S006 | Writer 超时处理 | PASS | screenshots/round-14/S006-writer-timeout.txt |
| S007 | Tester 启动并生成报告 | PASS | screenshots/round-14/S007-tester.txt |
| S008 | 3 Reviewer 启动并产出评分 | PASS | screenshots/round-14/S008-reviewers.txt |
| S009 | 和议计算正确 | PASS | screenshots/round-14/S009-median.txt |
| S010 | 一票否决(score<4.0) | PASS | screenshots/round-14/S010-veto.txt |
| S011 | Tester P0 否决 | PASS | screenshots/round-14/S011-tester-p0.txt |
| S012 | verdict.env 安全读取 | PASS | screenshots/round-14/S012-verdict-safe.txt |
| S013 | 连续5轮失败自动回退 | PASS | screenshots/round-14/S013-rollback.txt |
| S014 | STOP 文件优雅退出 | PASS | screenshots/round-14/S014-stop.txt |
| S015 | worktree 清理 | PASS | screenshots/round-14/S015-cleanup.txt |
| S016 | macOS timeout 兼容 | PASS | screenshots/round-14/S016-timeout.txt |
| S017 | 多 Writer 同文件冲突处理 | PASS | screenshots/round-14/S017-conflict.txt |

**通过率**: 16/17 (94.1%)

---

## P0 Bug 列表

### P0-1: 工作副本被覆盖 — scripts/hyper-loop.sh 磁盘文件损坏

**严重性**: P0
**位置**: scripts/hyper-loop.sh (working copy)
**现象**: 磁盘上的 hyper-loop.sh 只有 43 字节，内容为 `Script started on Mon Mar 30 04:15:42 2026`。这是 `script` 命令的输出覆盖了原始脚本。
**影响**: 直接运行 `bash scripts/hyper-loop.sh` 会失败。BUILD_CMD (`bash -n scripts/hyper-loop.sh`) 也只是检查这个 1 行文件（语法当然通过，但脚本无法执行任何功能）。
**修复**: `git checkout HEAD -- scripts/hyper-loop.sh` 恢复 987 行完整脚本。

### P0-2: auto_decompose 引用错误的文件路径 (S002 FAIL)

**严重性**: P0
**位置**: auto_decompose() 函数, 第 719-720 行
**现象**: 分解 prompt 引用 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 和 `${PROJECT_ROOT}/_hyper-loop/contract.md`，但实际文件路径是 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md` 和 `${PROJECT_ROOT}/_hyper-loop/context/contract.md`。
**影响**: Claude 在拆解任务时无法读取 BDD 规格和评估契约，导致生成的任务质量低下，无法针对性修复问题。这可能是连续 13 轮 REJECTED_VETO 的根因之一。
**修复**: 将路径改为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。

### P0-3: archive_round 引用错误的 bdd-specs.md 路径

**严重性**: P0
**位置**: archive_round() 函数, 第 797 行
**现象**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/"` — 文件不在这个路径。
**影响**: 归档时无法复制 BDD 规格，archive 目录不完整。
**修复**: 改为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。

---

## P1 Bug 列表

### P1-1: cmd_status() 函数定义重复

**严重性**: P1
**位置**: 第 697 行和第 957 行
**现象**: `cmd_status()` 被定义了两次。第二个定义覆盖第一个。
**影响**: 第一个定义（简单版）永远不会被执行。不影响功能但是代码不整洁。
**修复**: 删除第 697-704 行的第一个定义。

### P1-2: BUILD_CMD 对损坏的工作副本无意义

**严重性**: P1
**位置**: project-config.env
**现象**: `BUILD_CMD="bash -n scripts/hyper-loop.sh"` 检查的是磁盘上的工作副本（当前已损坏）。即使损坏文件也能通过 `bash -n`（因为只有 1 行合法 bash）。
**影响**: 构建验证形同虚设，无法检测脚本功能性问题。
**建议**: BUILD_CMD 应该对 git HEAD 版本做检查，或者先恢复工作副本。

---

## 总结

脚本的 git HEAD 版本（987 行）结构完整，17 个 BDD 场景中 16 个通过。核心问题是：
1. **工作副本已损坏**（P0-1），需要 `git checkout` 恢复
2. **auto_decompose 和 archive_round 引用了错误的文件路径**（P0-2, P0-3），导致 Claude 拆解任务时看不到关键上下文
3. 这两个路径 bug 很可能是连续 13 轮全部 0 分的根因 — 分解器无法读取 BDD 规格，生成的任务没有针对性

**建议优先级**: P0-1 > P0-2 > P0-3 > P1-1
