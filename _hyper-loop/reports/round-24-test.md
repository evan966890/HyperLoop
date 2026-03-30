# Round 24 试用报告

**日期**: 2026-03-30
**测试方法**: bash -n 语法检查 + BDD 场景逐条代码审计 + Python 逻辑单元测试
**测试对象**: `git show HEAD:scripts/hyper-loop.sh` (987 行, committed version)
**注意**: 工作副本 `scripts/hyper-loop.sh` 已损坏（见 P0-001），以下测试基于 git HEAD 版本

---

## 语法检查

```
bash -n scripts/hyper-loop.sh (HEAD version) → EXIT_CODE=0 ✓
```

截图: `screenshots/round-24/S000-syntax-check.txt`

---

## BDD 场景验证

### S001: loop 命令启动死循环 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 输出 "Round N/M" | ✓ `LOOP: Round ${ROUND}/${MAX_ROUNDS}` | L860 |
| 循环跑满后正常退出 | ✓ while 循环 + ROUND++ + MAX_ROUNDS 比较 | L850,941 |
| results.tsv 有记录 | ✓ record_result 每轮写入 | L885,892 |

### S002: auto_decompose 生成任务文件 — PASS (with P1 note)

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 至少 1 个 task*.md | ✓ claude -p 生成 + fallback | L760-788 |
| 包含"修复任务"和"相关文件" | ✓ 模板格式正确 | L741-753 |
| claude -p 失败降级 | ✓ TASK_COUNT==0 时生成默认 task1.md | L767-785 |

**注意**: decompose prompt 中 bdd-specs.md 和 contract.md 路径缺少 `context/` 前缀（L719-720），但根级副本存在，不影响功能。见 P1-001。

### S003: Writer worktree 创建 + trust + 启动 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 创建 worktree 目录 | ✓ `git worktree add` | L124 |
| config.toml 包含 trust | ✓ 写入 `trust_level = "trusted"` | L130-132 |
| Codex 在 tmux 启动 | ✓ `tmux new-window` + `codex --dangerously-bypass` | L179,182 |
| _ctx/ 被复制 | ✓ `cp -r context _ctx` | L136 |

### S004: Writer 完成后 diff 被正确 commit — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| git add -A && git commit | ✓ | L338-339 |
| squash merge 到 integration | ✓ `merge --squash --no-edit` | L348 |
| .patch 和 .stat 生成 | ✓ `git diff > .patch`, `git diff --stat > .stat` | L342-345 |

### S005: diff 审计拦截越界修改 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 返回非零退出码 | ✓ `return 1` | L291 |
| Writer 产出被跳过 | ✓ `continue` 跳过合并 | L328-330 |

审计逻辑完整：从 TASK.md 提取"相关文件"列表，逐一比对改动文件，允许 DONE.json/_ctx/TASK.md 等 HyperLoop 文件。

### S006: Writer 超时处理 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 15 分钟超时 | ✓ `TIMEOUT=900` | L198 |
| DONE.json 写入 timeout | ✓ `echo '{"status":"timeout"}'` | L224 |
| Writer 标记为 failed | ✓ merge_writers 中 status!=done → FAILED++ | L321-323 |

### S007: Tester 启动并生成报告 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| tmux 中启动 | ✓ `start_agent "tester"` | L383 |
| 15 分钟内生成报告 | ✓ 轮询 REPORT_FILE，900s 超时 | L407 |
| 超时生成空报告 | ✓ 写入标题 + 超时说明 | L420-421 |

**注意**: 超时空报告文本说"10 分钟"但实际超时 15 分钟。见 P2-002。

### S008: 3 Reviewer 启动并产出评分 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 3 个 Reviewer 在 tmux 启动 | ✓ gemini + claude + codex | L453 |
| 10 分钟超时 | ✓ `WAITED < 600` | L470 |
| JSON 包含 score 字段 | ✓ 模板要求 + Python 提取验证 | L448,495 |
| 文件不存在时从 pane 提取 | ✓ capture-pane + Python JSON 提取 | L483-503 |

### S009: 和议计算正确 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 中位数 = 6.0 (奇数) | ✓ `scores[n//2]` | L546 |
| DECISION = ACCEPTED | ✓ `median > prev_median` 判断 | L564 |

实际测试: `scores=[5,6,7] → median=6.0 ✓`, `scores=[4,5,6,7] → median=5.5 ✓`
截图: `screenshots/round-24/S009-S012-verdict-tests.txt`

### S010: 一票否决 (score < 4.0) — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| DECISION = REJECTED_VETO | ✓ `any(s < 4.0)` → veto | L550,558 |
| 记录到 results.tsv | ✓ record_result 写入 | L892 |

实际测试: `scores=[3.5,6,7] → veto=True ✓`

### S011: Tester P0 否决 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| DECISION = REJECTED_TESTER_P0 | ✓ `"P0" in text and ("bug" or "fail")` | L556-557,560 |

实际测试: `"P0 bug fails" → True ✓`, `"All pass" → False ✓`

### S012: verdict.env 安全读取 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 正确提取 DECISION 和 MEDIAN | ✓ grep + cut | L621-623, L675-676, L897-898 |
| 不出现 command not found | ✓ 不再 source verdict.env | L619-623 |

实际测试: bash strict mode 下 grep 方法无错误。
截图: `screenshots/round-24/S009-S012-verdict-tests.txt`

### S013: 连续 5 轮失败自动回退 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| CONSECUTIVE_REJECTS >= 5 检查 | ✓ | L922 |
| git checkout 回退 | ✓ `git checkout "$BEST_SHA" -- .` | L928 |
| consecutive_rejects 重置 | ✓ `CONSECUTIVE_REJECTS=0` | L931 |

**注意**: 回退需要 `BEST_ROUND > 0`（即至少有一轮 ACCEPTED），否则不触发。当前 23 轮全 REJECTED_VETO，回退不会触发，符合逻辑。

### S014: STOP 文件优雅退出 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 当前轮不执行 | ✓ 循环开头检查 | L852 |
| exit 0 | ✓ break 退出循环，正常结束 | L855 |
| STOP 文件被删除 | ✓ `rm "$STOP_FILE"` | L854 |

### S015: worktree 清理 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| worktree 目录不存在 | ✓ `git worktree remove --force` | L604 |
| 分支被删除 | ✓ `git branch -D` | L605 |
| tmux windows 关闭 | ✓ grep + kill-window | L596-598 |

清理在 subshell + `set +e` 中运行，不会因清理失败终止循环。

### S016: macOS timeout 兼容 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| timeout 函数可用 | ✓ gtimeout 存在时用 gtimeout，否则 fallback | L17-20 |

本机 gtimeout 和 timeout 均存在 (`/opt/homebrew/bin/`)。
截图: `screenshots/round-24/S016-timeout-compat.txt`

### S017: 多 Writer 同文件冲突处理 — PASS

| Then 条件 | 结果 | 行号 |
|-----------|------|------|
| 第一个成功 merge | ✓ squash merge 成功分支 | L348-351 |
| 第二个报 conflict deferred | ✓ merge --abort + "conflict, deferred" | L353-354 |
| 脚本不崩溃 | ✓ `FAILED++` 计数继续循环 | L355 |

---

## Bug 汇总

### P0 — 阻塞性

| ID | 描述 | 截图 |
|----|------|------|
| P0-001 | **scripts/hyper-loop.sh 工作副本被 `script` 命令覆盖**。文件只剩 43 字节 (`Script started on Mon Mar 30 07:00:32 2026`)，987 行脚本仅存在于 git HEAD。系统从工作目录运行时完全不工作。**修复**: `git checkout HEAD -- scripts/hyper-loop.sh` | `screenshots/round-24/P0-script-corrupted.txt` |

### P1 — 功能缺陷

| ID | 描述 | 截图 |
|----|------|------|
| P1-001 | **auto_decompose 路径不一致**: L719-720 引用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`（缺少 `context/`）。当前根级副本存在所以不崩溃，但与其他引用不一致 (L75-76, L393, L438-439 都用 `context/`)。同样 `archive_round` L797 也缺 `context/`。 | `screenshots/round-24/P1-auto-decompose-paths.txt` |

### P2 — 代码质量

| ID | 描述 | 截图 |
|----|------|------|
| P2-001 | **cmd_status 重复定义**: L697 和 L957 各有一个 `cmd_status()`，第一个是死代码。应删除 L697-703 的版本。 | `screenshots/round-24/P2-duplicate-cmd-status.txt` |
| P2-002 | **Tester 超时消息不一致**: L421 说"10 分钟"但实际超时 900s = 15 分钟。应改为"15 分钟"。 | `screenshots/round-24/P2-tester-timeout-message.txt` |

---

## 总结

| 指标 | 值 |
|------|-----|
| BDD 场景总数 | 17 |
| PASS | 17 |
| FAIL | 0 |
| bash -n 语法检查 | PASS (git HEAD 版本) |
| P0 bug | 1 (工作副本损坏) |
| P1 bug | 1 (路径不一致) |
| P2 bug | 2 (死代码 + 消息不一致) |

**评估**: git HEAD 中的脚本逻辑完整、健壮。所有 17 个 BDD 场景在代码级别验证通过。关键改进（verdict.env 安全读取、cleanup subshell 容错、wait_writers set+e）均已到位。

**唯一阻塞问题是 P0-001**: 工作副本被外部 `script` 命令意外覆盖，需要 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复。这不是脚本自身的 bug，而是外部操作事故。

**建议**: 修复 P0-001 后，脚本可以进入实际运行测试（端到端验证）。当前代码审查评分建议 **7.0-7.5**（17/17 BDD pass + 良好错误处理 - P1 路径问题 - P2 代码质量问题）。
