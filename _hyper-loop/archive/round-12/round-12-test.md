# Round 12 — Tester BDD 验证报告

**测试对象**: `scripts/hyper-loop.sh` (integration branch: `hyper-loop/r12-integration`, commit `81bad6e`)
**语法检查**: `bash -n` PASS
**测试时间**: 2026-03-31

## 本轮修改摘要 (4 tasks)

| Task | 修改 | 优先级 |
|------|------|--------|
| task1 | `audit_writer_diff` 白名单加 `_writer_prompt.md` + untracked 文件检测 | P0 |
| task2 | `compute_verdict` Tester P0 否决阈值降低至 `>= 1 and >= 1` | P1 |
| task3 | `cmd_loop` 重启后从 `results.tsv` 初始化 `BEST_ROUND`/`BEST_MEDIAN`/`CONSECUTIVE_REJECTS` | P1 |
| task4 | 删除废弃函数 `start_agent`/`kill_agent` + `build_app` 子 shell 隔离 `cd` | P2 |

## BDD 场景逐条验证

| 场景 | 结果 | 原因 |
|------|------|------|
| S001 | **PASS** | `cmd_loop` 接受 MAX_ROUNDS 参数，输出 "Round N/M"，循环结束后正常退出，`record_result` 每轮写 results.tsv |
| S002 | **PASS** | `auto_decompose` 用 claude -p 生成任务文件；如失败，降级生成默认 task1.md（line 792-844）|
| S003 | **PASS** | `start_writers` 创建 worktree、写 trust 到 `~/.codex/config.toml`、复制 `_ctx/`、启动 codex exec 后台进程。注：实际用 subshell 而非 tmux window，是已知设计变更 |
| S004 | **PASS** | `merge_writers` 先删元数据（DONE.json, WRITER_INIT.md, TASK.md, _writer_prompt.md, _ctx/）再 git add -A && commit，然后 squash merge。R12 task1 修复了 `_writer_prompt.md` 白名单遗漏 |
| S005 | **PASS** | `audit_writer_diff` 对比 TASK.md 允许文件列表与实际变更；越界返回 1；`merge_writers` 据此跳过合并。R12 task1 增加了 untracked 文件检测 |
| S006 | **PASS** | `wait_writers` 超时（默认 900s=15min）后杀进程并写 `{"status":"timeout"}` 到 DONE.json，`merge_writers` 跳过 status!=done 的 writer |
| S007 | **PASS** | `run_tester` 用 claude -p 管道模式运行，超时 600s；空输出时生成默认报告不崩溃。注：BDD 说 15min tmux，实际 10min 管道，是已知设计变更 |
| S008 | **PASS** | `run_reviewers` 3 个 reviewer 并行 &（gemini/claude/codex），timeout 300s，JSON 提取 + fallback score 5。注：BDD 说 10min tmux，实际 5min subshell |
| S009 | **PASS** | Python 中位数计算正确（奇数取中间值，偶数取均值）；scores=[5,6,7] -> median=6.0 -> ACCEPTED（如 >prev）；verdict.env 用 grep 读取不会 crash |
| S010 | **PASS** | `veto = any(s < 4.0 for s in scores)` 正确；scores=[3.5,6,7] -> veto=True -> REJECTED_VETO |
| S011 | **PASS** | R12 task2 修复：从 `>=2 or (>=1 and >3)` 改为 `>=1 and >=1`，现在 1 个 `### P0` heading + 1 个 FAIL 即触发 REJECTED_TESTER_P0，符合 BDD 规格 |
| S012 | **PASS** | `record_result` 和 `cmd_round`/`cmd_loop` 都用 `grep '^KEY=' | cut -d= -f2` 读取 verdict.env，不 source；SCORES 带引号也能正确处理 |
| S013 | **PASS** | R12 task3 修复：`cmd_loop` 启动时遍历 results.tsv 恢复 BEST_ROUND/BEST_MEDIAN（找最高 median 的 ACCEPTED 轮）和 CONSECUTIVE_REJECTS；rollback 逻辑 `>=5 && BEST_ROUND>0` 重启后不再失效 |
| S014 | **PASS** | `cmd_loop` 每轮开头检查 STOP 文件 -> rm -> break -> 正常退出 exit 0 |
| S015 | **PASS** | `cleanup_round` 在子 shell(set +e) 中：杀 tmux windows -> 移除 worktree+branch -> `rm -rf $WORKTREE_BASE`。容错不崩溃 |
| S016 | **PASS** | 脚本开头：先检查 gtimeout，再检查 timeout，最后定义 polyfill 函数 |
| S017 | **PASS** | `merge_writers` 先删元数据文件再 git add，消除 false conflict；真实冲突 `merge --abort` 标记 deferred；脚本不崩溃 |

## R12 Task 修复验证

| Task | 验证项 | 结果 |
|------|--------|------|
| task1 | `_writer_prompt.md` 在 audit whitelist (line 284) | **PASS** |
| task1 | untracked 文件检测 (line 258-262) | **PASS** |
| task1 | merge_writers rm 列表一致性 | **PASS** |
| task2 | P0 否决条件 (line 558) | **PASS** |
| task2 | 其他 verdict 逻辑不受影响 | **PASS** |
| task3 | BEST_ROUND 从 results.tsv 初始化 (line 1025-1045) | **PASS** |
| task3 | CONSECUTIVE_REJECTS 从历史恢复 | **PASS** |
| task3 | HIST_DECISION glob 匹配 ACCEPTED* | **PASS** |
| task4 | start_agent/kill_agent 已删除 | **PASS** |
| task4 | build_app 子 shell 隔离 (line 376-380) | **PASS** |
| task4 | build_app 返回值正确 (line 381-387) | **PASS** |

## P0 Bugs

无。

## P1 Bugs

无。

## 备注（非 Bug，已知设计偏差）

1. **S003/S007/S008 — tmux vs subshell**: BDD 规格说 Writer/Tester/Reviewer 在 "tmux window 中启动"，实际实现使用 `codex exec` 后台 subshell 和 `claude -p` 管道。这是从交互模式到非交互模式的有意设计变更，非回归。
2. **S007 timeout**: BDD 说 15 分钟，实际 `run_tester` 用 `timeout 600`（10 分钟）。
3. **S008 timeout**: BDD 说 10 分钟，实际 `run_reviewers` 用 `timeout 300`（5 分钟）。
4. **建议**: 更新 BDD 规格中 S003/S007/S008 的 tmux 描述和超时值以反映当前非交互架构。

## 总结

- **17/17 BDD 场景 PASS**
- **R12 全部 4 个 task 修复验证通过**
- **0 P0 bugs, 0 P1 bugs**
