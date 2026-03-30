# Round 17 试用报告

**测试时间**: 2026-03-30
**测试对象**: scripts/hyper-loop.sh (git HEAD, 987 行)
**测试方法**: bash -n 语法检查 + BDD 场景逐条代码审查 + Python 逻辑验证

---

## 语法检查

| 检查项 | 结果 |
|--------|------|
| `bash -n` (git HEAD 版本) | PASS |
| `bash -n` (working copy) | N/A — 工作副本已损坏 (见 P0-1) |

---

## BDD 场景验证

| 场景 | 描述 | 结果 | 截图 |
|------|------|------|------|
| S001 | loop 命令启动死循环 | PASS | screenshots/round-17/S001-loop-cmd.txt |
| S002 | auto_decompose 生成任务文件 | PASS | screenshots/round-17/S002-auto-decompose.txt |
| S003 | Writer worktree 创建 + trust + 启动 | PASS | screenshots/round-17/S003-writer-worktree.txt |
| S004 | Writer 完成后 diff 被正确 commit | PASS | screenshots/round-17/S004-writer-commit-merge.txt |
| S005 | diff 审计拦截越界修改 | PASS | screenshots/round-17/S005-diff-audit.txt |
| S006 | Writer 超时处理 | PASS | screenshots/round-17/S006-writer-timeout.txt |
| S007 | Tester 启动并生成报告 | **FAIL** | screenshots/round-17/S007-tester.txt |
| S008 | 3 Reviewer 启动并产出评分 | **FAIL** | screenshots/round-17/S008-reviewers.txt |
| S009 | 和议计算正确 | PASS | screenshots/round-17/S009-verdict-calc.txt |
| S010 | 一票否决 (score < 4.0) | PASS | screenshots/round-17/S010-veto.txt |
| S011 | Tester P0 否决 | PASS | screenshots/round-17/S011-tester-p0.txt |
| S012 | verdict.env 安全读取 | PASS | screenshots/round-17/S012-verdict-env-safe.txt |
| S013 | 连续 5 轮失败自动回退 | **FAIL** | screenshots/round-17/S013-rollback.txt |
| S014 | STOP 文件优雅退出 | PASS | screenshots/round-17/S014-stop-file.txt |
| S015 | worktree 清理 | PASS | screenshots/round-17/S015-cleanup.txt |
| S016 | macOS timeout 兼容 | PASS | screenshots/round-17/S016-macos-timeout.txt |
| S017 | 多 Writer 同文件冲突处理 | PASS | screenshots/round-17/S017-conflict.txt |

**通过率**: 14/17 (82.4%)

---

## Bug 列表

### P0 Bugs (阻塞性)

#### P0-1: scripts/hyper-loop.sh 工作副本被 `script` 命令覆盖

- **现象**: 文件内容只有 1 行 `Script started on Mon Mar 30 04:15:42 2026`
- **影响**: 脚本无法执行。所有后续循环会使用损坏的文件
- **根因**: 有人在项目目录下执行了 `script` 命令，输出文件恰好覆盖了 hyper-loop.sh
- **修复**: `git checkout HEAD -- scripts/hyper-loop.sh`

#### P0-2: TESTER_INIT.md / REVIEWER_INIT.md 路径不存在 (S007, S008)

- **位置**: line 384, line 460
- **脚本引用**: `_hyper-loop/context/TESTER_INIT.md`, `_hyper-loop/context/REVIEWER_INIT.md`
- **实际文件**: `_hyper-loop/context/agents/tester.md`, `_hyper-loop/context/agents/reviewer.md`
- **影响**: Tester 和 Reviewer 无法读到角色定义，inject prompt 中的"角色定义"指向不存在的文件。Agent 会以无上下文状态运行，导致评分不可靠
- **修复**: 改为正确路径 `${PROJECT_ROOT}/_hyper-loop/context/agents/tester.md` / `reviewer.md`

#### P0-3: merge_writers stdout 污染 INTEGRATION_WT 变量 (S004 关联)

- **位置**: line 656-657 (cmd_round), line 878-879 (cmd_loop)
- **现象**: `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获了所有 echo 输出 + 路径
- **INTEGRATION_WT 实际值**:
  ```
  合并 Writer 产出...
    ⚠ task1: status=timeout, 跳过
  合并完成: 0 merged, 1 failed/skipped
  /tmp/hyper-loop-worktrees-rN/integration
  ```
- **影响**: `build_app "$INTEGRATION_WT"` 收到多行垃圾字符串做 cd 目标。因在 if 条件中运行，cd 静默失败，build_cmd 在错误目录执行
- **修复**: merge_writers 中的信息性 echo 应重定向到 stderr (`>&2`)，只有最后一行 `echo "$INTEGRATION_WT"` 输出到 stdout

### P1 Bugs (功能缺陷)

#### P1-1: BEST_ROUND 只追踪 ACCEPTED 轮次，全 reject 时回退失效 (S013)

- **位置**: line 906-910
- **现象**: BEST_ROUND/BEST_MEDIAN 追踪逻辑在 ACCEPTED 分支内，reject 轮不记录
- **影响**: 如果所有轮次都被 reject（如当前 16 轮全 REJECTED_VETO），BEST_ROUND=0，回退条件 `BEST_ROUND > 0` 永不满足。连续 5+ 轮失败不触发回退
- **验证**: results.tsv 显示 16 轮全 REJECTED_VETO，无回退发生
- **修复**: 将 BEST_ROUND 追踪移到 if/else 外面，对所有轮次（含 rejected）追踪最高 median

#### P1-2: cmd_status 重复定义

- **位置**: line 697 和 line 957
- **影响**: 第二个定义覆盖第一个。第一个版本缺少"最佳轮次"显示
- **修复**: 删除 line 697 的旧版本

#### P1-3: archive_round 拷贝 bdd-specs.md 路径错误

- **位置**: line 797
- **脚本**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/"`
- **影响**: 如果 `_hyper-loop/bdd-specs.md` 副本不存在或过期，archive 中缺少 BDD spec 快照。目前因有副本文件存在而未阻塞
- **修复**: 改为 `_hyper-loop/context/bdd-specs.md`

---

## 总结

脚本核心逻辑（循环、拆解、Writer/merge、审计、超时、和议计算、安全读取、清理、STOP、macOS 兼容、冲突处理）全部正确实现。17 个 BDD 场景中 14 个通过。

3 个失败场景的根因是 **路径配置错误**（P0-2, P0-3）和 **追踪逻辑范围不足**（P1-1）。P0-1（工作副本损坏）是外部操作导致，非代码逻辑 bug。

**优先修复顺序**:
1. P0-1: 恢复工作副本 (`git checkout`)
2. P0-3: merge_writers echo → stderr
3. P0-2: 修正 TESTER_INIT/REVIEWER_INIT 路径
4. P1-1: BEST_ROUND 全局追踪
