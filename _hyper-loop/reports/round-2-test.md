# Round 2 — Tester 报告

构建验证: `bash -n scripts/hyper-loop.sh` **PASS** (语法无错误)

## BDD 场景逐条结果

| 场景 | 结果 | 原因 |
|------|------|------|
| S001 | PASS | `cmd_loop` (L798) 接受 MAX_ROUNDS 参数，循环正确跑满后退出，`record_result` 每轮追加 results.tsv |
| S002 | PASS | `auto_decompose` (L679) 调 claude -p 拆任务，失败时 L740-758 降级生成默认 task1.md。**但 P1 bug: 拆解 prompt 中引用的文件路径错误，见下方** |
| S003 | PASS | `start_writers` (L101) 创建 worktree(L124)、trust config.toml(L130)、复制 _ctx/(L136)、tmux 启动 Codex(L179-191) |
| S004 | PASS | `merge_writers` (L299) 先 add+commit(L338-339) 再 squash merge(L348)，生成 .patch/.stat(L342-345) |
| S005 | **FAIL** | `audit_writer_diff` (L258) 用 `git diff --name-only HEAD` 检查越界文件，**但 Writer(Codex) 可能已自行 commit 修改，此时 `git diff HEAD` 返回空，审计被完全绕过**。应对比分支创建点而非 HEAD |
| S006 | PASS | `wait_writers` (L196) 超时写入 `{"status":"timeout"}`(L224)，merge_writers 中 status!=done 会跳过(L320-323) |
| S007 | PASS | `run_tester` (L379) 用 `timeout 600 claude -p` 非交互模式运行，无输出时生成默认报告(L411-413) |
| S008 | PASS | `run_reviewers` (L417) 3 个 subshell 并行 & wait，fallback 给 3 分(L477-482)。**但 reviewer-c 的 codex 命令有 P1 问题，见下方** |
| S009 | PASS | `compute_verdict` (L486) Python 中位数计算正确：sorted scores → `scores[n//2]`。ACCEPTED 当 median > prev_median |
| S010 | PASS | L523: `any(s < 4.0 for s in scores)` → veto=True → L531: DECISION=REJECTED_VETO |
| S011 | PASS | L525-529: 检查报告含 "P0" 且 ("bug" or "fail") → L533: REJECTED_TESTER_P0 |
| S012 | PASS | `record_result` (L586) 和 cmd_loop(L870) 均用 `grep + cut` 安全读取 verdict.env，不 source，不会执行恶意值 |
| S013 | PASS | L895-905: `CONSECUTIVE_REJECTS >= 5` 且 `BEST_ROUND > 0` 时读 archive git-sha.txt 回退代码，重置计数器 |
| S014 | PASS | L825-829: 检查 STOP 文件 → 删除 → break 退出循环 → exit 0 |
| S015 | PASS | `cleanup_round` (L563) subshell+set+e 中关闭 tmux windows(L569)、移除 worktrees(L577)、删分支(L578)。**小问题: 父目录 /tmp/hyper-loop-worktrees-rN/ 未清理** |
| S016 | PASS | L17-21: gtimeout → timeout → 自实现 fallback，三级降级 |
| S017 | PASS | L348: squash merge 失败时 L352-354 merge --abort + 计数，脚本不崩溃 |

**总计: 16 PASS / 1 FAIL**

---

## P0 Bug

无

## P1 Bug

### P1-1: audit_writer_diff 可被绕过（S005 FAIL）
- **位置**: `scripts/hyper-loop.sh:258`
- **问题**: `git diff --name-only HEAD` 只检查未提交的修改。Writer (Codex) 是完整的 AI agent，可能在工作中自行 `git add + git commit`。一旦 commit，`git diff HEAD` 为空，审计返回 "没有改任何文件"(L261)，return 0 — 整个 diff 审计被完全绕过。
- **影响**: Writer 越界修改不会被拦截，破坏了安全边界
- **修复建议**: 改用 `git diff --name-only $(git merge-base main HEAD) HEAD` 对比从分支创建点到 HEAD 的所有变更

### P1-2: auto_decompose 引用了错误的文件路径
- **位置**: `scripts/hyper-loop.sh:692-693`
- **问题**: 引用 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，实际路径是 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`
- **影响**: Claude 拆任务时拿到错误路径，可能找不到文件导致拆解质量下降
- **同样问题出现在**: L770 `archive_round` 归档 bdd-specs.md 的路径也是错的（会静默失败）

### P1-3: reviewer-c codex 命令参数冲突
- **位置**: `scripts/hyper-loop.sh:468`
- **问题**: `echo "$REVIEW_PROMPT" | timeout 300 codex exec -a never "$REVIEW_PROMPT"` 同时通过 stdin 管道和命令行参数传递 prompt。`codex exec` 优先读取参数，stdin 被忽略。长 prompt 作为命令行参数可能超出 ARG_MAX 限制
- **修复建议**: 去掉命令行参数，改为纯 stdin 管道: `echo "$REVIEW_PROMPT" | timeout 300 codex exec -a never -`

### P1-4: cmd_status 函数重复定义
- **位置**: `scripts/hyper-loop.sh:670` 和 `scripts/hyper-loop.sh:930`
- **问题**: `cmd_status()` 定义了两次，bash 静默使用最后一个定义(L930)，L670 的版本是死代码
- **影响**: 维护混乱，第一个定义缺少"最佳轮次"信息
- **修复建议**: 删除 L670-676 的第一个定义
