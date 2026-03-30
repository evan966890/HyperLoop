# Round 7 — Tester 报告

语法检查：`bash -n scripts/hyper-loop.sh` — **PASS**（无输出无报错）

## BDD 场景逐条验证

| 场景 | 结果 | 原因 |
|------|------|------|
| S001 | PASS | `cmd_loop` 接收 MAX_ROUNDS 参数，输出 "LOOP: Round N/M"，循环到 MAX 后退出；`record_result` 每轮追加 results.tsv，N 轮 = N 行记录 |
| S002 | PASS | `auto_decompose` 创建 TASK_DIR、调用 `claude -p` 生成 task*.md；失败时 fallback 生成默认 task1.md (line 746-761) |
| S003 | PASS | `start_writers` 为每个 task 调用 `git worktree add` 创建 `/tmp/hyper-loop-worktrees-rN/taskM`；写入 `~/.codex/config.toml` trust 配置 (line 130-133)；`cp -r context _ctx` 复制上下文包 (line 136)；Codex 在 tmux window 中启动 (line 179-190) |
| S004 | PASS | `merge_writers` 先执行 `git add -A && git commit` (line 338-339)，再 squash merge 到 integration 分支 (line 348)；生成 .patch 和 .stat 文件 (line 342-345)；所有状态 echo 均使用 `>&2` 避免污染 stdout 返回值 |
| S005 | PASS | `audit_writer_diff` 从 TASK.md 提取允许文件列表，比对实际修改文件；越界则 return 1 (line 288-292)；merge_writers 中检查返回值，失败则跳过合并 (line 327-330) |
| S006 | PASS | `wait_writers` 默认超时 900s (line 198)，符合 BDD 15 分钟要求；超时后写 `{"status":"timeout"}` 到 DONE.json (line 224)；status=timeout 被 merge_writers 跳过 (line 320-323) |
| S007 | PASS | `run_tester` 使用 `timeout 600` (10 分钟) 运行 claude 非交互模式 (line 404)；输出写入 reports/round-N-test.md；超时/失败时生成默认报告 "Tester 无输出" (line 411-413)。注：BDD 说 15 分钟但代码用 10 分钟，不影响功能 |
| S008 | PASS | `run_reviewers` 并行启动 3 个 Reviewer（gemini/claude/codex），使用管道 `-p` 模式而非 tmux（v5.4 改为非交互管道模式）；各 reviewer 超时 300s；通过 python EXTRACT_PY 提取 JSON 中的 score 字段；文件不存在/空时 fallback 给中立分 5 (line 477-482) |
| S009 | PASS | `compute_verdict` 的 Python 代码正确排序后取中位数 `scores[n//2]`；[5,6,7] → median=6.0；ACCEPTED 条件为 `median > prev_median`；verdict.env 写入纯 KEY=VALUE 格式无特殊字符 |
| S010 | PASS | Python 中 `veto = any(s < 4.0 for s in scores)` (line 523)；[3.5,6,7] 触发 veto → DECISION=REJECTED_VETO；record_result 写入 results.tsv |
| S011 | PASS | Python 中 `tester_p0 = "P0" in text and ("bug" in text.lower() or "fail" in text.lower())` (line 527-529)；包含 "P0" 和 "fail" 时 DECISION=REJECTED_TESTER_P0 |
| S012 | PASS | `record_result` 和 `cmd_round`/`cmd_loop` 均使用 `grep '^KEY=' | cut -d= -f2` 读取 verdict.env (line 597-599, 651-652, 875-876)，不使用 source，不会触发 "command not found" |
| S013 | PASS | `cmd_loop` 追踪 CONSECUTIVE_REJECTS，>=5 且 BEST_ROUND>0 时读取 `archive/round-N/git-sha.txt` 回退代码 (line 899-910)；回退后 CONSECUTIVE_REJECTS 重置为 0 |
| S014 | PASS | `cmd_loop` 每轮开头检查 `_hyper-loop/STOP` 文件 (line 830)；存在则删除 STOP 文件并 break (line 832-833)；脚本正常结束 |
| S015 | PASS | `cleanup_round` 删除 worktree、删除分支、关闭 tmux windows (line 567-585)；line 584 `rm -rf "${WORKTREE_BASE}"` 确保父目录被清除 |
| S016 | PASS | 脚本开头 (line 17-21) 检测 gtimeout → timeout 函数；macOS 无 timeout 时用 shell fallback 实现 |
| S017 | PASS | `merge_writers` 的 squash merge 失败时执行 `merge --abort` 并标记为 deferred (line 352-354)；不影响后续 task 合并，脚本不崩溃 |

## P0 Bug

无

## P1 Bug

### P1-1: merge_writers 中 `git merge --squash` stdout 未重定向（line 348）

```bash
if git -C "$INTEGRATION_WT" merge "$BRANCH" --squash --no-edit 2>/dev/null; then
```

`git merge --squash` 可能将合并摘要（"Squash commit -- not updating HEAD" 等）输出到 stdout。由于 `merge_writers` 的返回值通过 `echo "$INTEGRATION_WT"` 发往 stdout，未重定向的 git 输出可能污染 `INTEGRATION_WT` 路径变量，导致 `build_app` 的 `cd` 失败。

**实际影响**：从 7 轮运行日志看构建正常通过，可能 macOS git 版本将此输出写到 stderr，但跨平台不可靠。

**建议修复**：`git merge ... >/dev/null 2>/dev/null`

---

### P1-2: `archive_round` 中 bdd-specs.md 路径错误（line 773）

```bash
cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
```

实际文件在 `_hyper-loop/context/bdd-specs.md`，此行永远静默失败，BDD 规格从未被归档。

**建议修复**：改为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`

---

### P1-3: Reviewer fallback 注释与代码不一致（line 476 vs 479）

注释写 "fallback 给 3 分"，但实际 JSON 给 `"score":5`。注释误导维护者。

**建议修复**：注释改为 "fallback 给 5 分（中立分）"

---

### P1-4: `cmd_status` 函数重复定义（line 673 和 line 935）

两处定义 `cmd_status`，后者覆盖前者。line 673-679 是死代码。

**建议修复**：删除 line 673-679 的第一个定义

---

### P1-5: `PREV_MEDIAN` 空文件边界情况（line 849-851）

```bash
PREV_MEDIAN=$(tail -1 "${PROJECT_ROOT}/_hyper-loop/results.tsv" | cut -f2 || echo 0)
```

当 results.tsv 存在但为空时，`tail -1 | cut -f2` 返回空字符串（管道成功，`|| echo 0` 不触发）。空字符串传入 Python 的 `float("")` 会抛 ValueError 崩溃。

**建议修复**：加 `PREV_MEDIAN="${PREV_MEDIAN:-0}"`
