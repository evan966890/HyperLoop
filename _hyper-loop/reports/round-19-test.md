# Round 19 试用报告

**测试时间**: 2026-03-30
**Tester**: Claude Opus 4.6
**测试方法**: bash -n 语法检查 + 逐条 BDD 场景代码审查 + Python 逻辑验证

---

## 语法检查

```
bash -n scripts/hyper-loop.sh → syntax ok
```

**结果**: PASS

---

## BDD 场景验证

### S001: loop 命令启动死循环 — PASS
- **Then 脚本输出 "Round 1/3"**: 第 860 行 `echo "  LOOP: Round ${ROUND}/${MAX_ROUNDS}"` ✓
- **Then 循环跑满 N 轮后正常退出**: `cmd_loop` 有 while 循环 + ROUND++ + 正常退出逻辑 ✓
- **Then results.tsv 有 N 行记录**: `record_result` 每轮写入 results.tsv ✓
- 截图: `screenshots/round-19/S001-syntax.txt`

### S002: auto_decompose 生成任务文件 — PASS (with P1 bug)
- **Then tasks/round-N/ 下至少有 1 个 task*.md**: `auto_decompose` 调用 `claude -p` 生成 ✓
- **Then 每个文件包含"修复任务"和"相关文件"**: prompt 模板包含格式要求 ✓
- **Then 降级生成默认 task1.md**: 第 767-786 行有 fallback 逻辑 ✓
- **P1 bug**: 第 719-720 行路径错误: `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 应为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`，`contract.md` 同理。Claude -p 会因找不到文件而降级，但 fallback 兜底所以不崩溃。
- 截图: `screenshots/round-19/S002-decompose.txt`

### S003: Writer worktree 创建 + trust + 启动 — PASS
- **Then 创建 worktree 目录**: 第 124 行 `git worktree add` ✓
- **Then config.toml 包含 trust**: 第 130-131 行写入 trust 配置 ✓
- **Then Codex 进程在 tmux 启动**: 第 179-182 行 `tmux new-window` + `codex` ✓
- **Then _ctx/ 被复制**: 第 136 行 `cp -r context _ctx` ✓
- 截图: `screenshots/round-19/S003-worktree.txt`

### S004: Writer 完成后 diff 被正确 commit — PASS
- **Then git add -A && git commit**: 第 338-339 行 ✓
- **Then squash merge 到 integration**: 第 348 行 `merge --squash` ✓
- **Then patch 和 stat 文件生成**: 第 342-345 行 ✓
- 截图: `screenshots/round-19/S004-merge.txt`

### S005: diff 审计拦截越界修改 — PASS
- **Then 返回非零退出码**: 第 291 行 `return 1` ✓
- **Then Writer 产出被跳过**: 第 327-330 行 `if ! audit_writer_diff; then ... 拒绝合并` ✓
- 截图: `screenshots/round-19/S005-audit.txt`

### S006: Writer 超时处理 — PASS
- **Then DONE.json 被写入 status=timeout**: 第 224 行 `echo '{"status":"timeout"}' > DONE.json` ✓
- **Then Writer 被标记 failed**: `merge_writers` 中 status != "done" 则跳过 (第 320-324 行) ✓
- 截图: `screenshots/round-19/S006-timeout.txt`

### S007: Tester 启动并生成报告 — FAIL (P0)
- **Then Tester Claude 子进程启动**: 第 383 行引用 `TESTER_INIT.md` ✓
- **P0 bug**: `_hyper-loop/context/TESTER_INIT.md` **文件不存在**。实际位于 `_hyper-loop/context/templates/TESTER_INIT.md`。`start_agent` 注入的消息让 Tester 读取一个不存在的文件，Tester 无法获取角色定义。
- **Then 超时生成空报告**: 第 419-421 行有 fallback ✓
- 截图: `screenshots/round-19/S007-tester.txt`

### S008: 3 Reviewer 启动并产出评分 — FAIL (P0)
- **Then 3 个 Reviewer 启动**: 第 453 行定义了 reviewer-a/b/c ✓
- **P0 bug**: 同 S007，`_hyper-loop/context/REVIEWER_INIT.md` **文件不存在**。实际位于 `_hyper-loop/context/templates/REVIEWER_INIT.md`。Reviewer 无法获取角色定义。
- **Then JSON 包含 "score" 字段**: Python 提取逻辑正确 ✓
- **Then 从 pane 输出提取 JSON**: 第 481-503 行 fallback 逻辑 ✓
- 截图: `screenshots/round-19/S008-reviewers.txt`

### S009: 和议计算正确 — PASS
- **Then 中位数 = 6.0**: Python 验证 sorted([5.0,6.0,7.0]) → median=6.0 ✓
- **Then DECISION = ACCEPTED (if > prev_median)**: 逻辑正确 ✓
- **Then verdict.env 可以被安全读取**: 全部用 grep 而非 source ✓
- 截图: `screenshots/round-19/S009-verdict.txt`

### S010: 一票否决（score < 4.0）— PASS
- **Then DECISION = REJECTED_VETO**: Python 验证 any(3.5 < 4.0) → veto=True ✓
- **Then 记录到 results.tsv**: `record_result` 调用正确 ✓
- 截图: `screenshots/round-19/S010-veto.txt`

### S011: Tester P0 否决 — PASS
- **Then DECISION = REJECTED_TESTER_P0**: 检测逻辑 `"P0" in text and ("bug" in lower or "fail" in lower)` ✓
- 截图: `screenshots/round-19/S011-p0.txt`

### S012: verdict.env 安全读取 — PASS
- **Then 不会出现 "command not found"**: 全部用 `grep | cut` 而非 `source` ✓
- 验证: 以 `SCORES="1.0 2.0 3.0"` 测试，提取正确 ✓
- 截图: `screenshots/round-19/S012-safe-read.txt`

### S013: 连续 5 轮失败自动回退 — PASS (条件性)
- **Then 代码回退到最佳轮次**: 第 922-931 行逻辑正确 ✓
- **Then consecutive_rejects 重置为 0**: 第 931 行 ✓
- **注意**: 回退条件要求 `BEST_ROUND > 0`，即至少有一轮曾被 ACCEPTED。如果从未 ACCEPTED（如当前 18 轮全部 REJECTED_VETO），回退不会触发。这是合理的设计（无历史最佳可回退），但 BDD spec 假设 "archive/round-2/git-sha.txt 存在且得分最高" 的前提条件仍然满足。
- 截图: `screenshots/round-19/S013-rollback.txt`

### S014: STOP 文件优雅退出 — PASS (P1 偏差)
- **Then 当前轮不执行**: STOP 检查在循环开头 ✓
- **Then 脚本正常退出 (exit 0)**: 实际使用 `break` 退出循环，然后自然结束。效果等同 exit 0，但严格来说不是 `exit 0`。
- **Then STOP 文件被删除**: 第 854 行 `rm "$STOP_FILE"` ✓
- 截图: `screenshots/round-19/S014-stop.txt`

### S015: worktree 清理 — FAIL (P1)
- **Then worktree 目录不存在**: `cleanup_round` 移除各子 worktree，但**不移除父目录** `/tmp/hyper-loop-worktrees-rN/`。`git worktree remove` 只清理 git 注册，不删除空目录。
- **Then branches 被删除**: 第 605 行 `git branch -D` ✓
- **Then tmux windows 被关闭**: 第 597 行 ✓
- 截图: `screenshots/round-19/S015-cleanup.txt`

### S016: macOS timeout 兼容 — PASS
- **Then timeout 函数可用**: 第 17-21 行 gtimeout → timeout → fallback 链 ✓
- 本机: gtimeout 和 timeout 均可用 ✓
- 截图: `screenshots/round-19/S016-timeout.txt`

### S017: 多 Writer 同文件冲突处理 — PASS
- **Then 第一个成功 merge**: squash merge 逻辑 ✓
- **Then 第二个报 conflict 被 deferred**: 第 352-354 行 `merge --abort` + "conflict, deferred" ✓
- **Then 脚本不崩溃**: `|| true` 保护 ✓
- 截图: `screenshots/round-19/S017-conflict.txt`

---

## Bug 汇总

| # | 严重度 | 场景 | 描述 |
|---|--------|------|------|
| 1 | **P0** | S007 | `TESTER_INIT.md` 路径错误: 脚本引用 `context/TESTER_INIT.md` 但文件在 `context/templates/TESTER_INIT.md`。Tester 无法获取角色定义。 |
| 2 | **P0** | S008 | `REVIEWER_INIT.md` 路径错误: 同上，文件在 `context/templates/REVIEWER_INIT.md`。Reviewer 无法获取角色定义。 |
| 3 | **P1** | S002 | `auto_decompose` 中 bdd-specs.md 和 contract.md 路径缺少 `context/` 子目录 (第 719-720 行)。Claude -p 找不到文件但有 fallback 兜底。 |
| 4 | **P1** | S015 | `cleanup_round` 不删除 `/tmp/hyper-loop-worktrees-rN/` 父目录，积累空目录。 |
| 5 | **P1** | — | `archive_round` 第 797 行路径错误: `_hyper-loop/bdd-specs.md` 应为 `_hyper-loop/context/bdd-specs.md`。 |
| 6 | **P2** | — | `cmd_status()` 函数重复定义 (第 697 行和第 957 行)，后者覆盖前者。 |

---

## 统计

| 指标 | 值 |
|------|-----|
| BDD 场景总数 | 17 |
| PASS | 13 |
| FAIL | 2 (S007, S008) |
| 条件性 PASS | 2 (S013, S014) |
| P0 bug | 2 |
| P1 bug | 3 |
| P2 bug | 1 |
| bash -n | PASS |

---

## 修复建议

### P0 修复 (必须)
1. **init 文件路径**: `run_tester` 和 `run_reviewers` 中 `start_agent` 的 INIT 路径改为 `context/templates/` 或将模板文件复制/符号链接到 `context/` 根目录:
   ```bash
   # 方案 A: 修改路径引用
   # run_tester 第 384 行
   "${PROJECT_ROOT}/_hyper-loop/context/templates/TESTER_INIT.md"
   # run_reviewers 第 460 行
   "${PROJECT_ROOT}/_hyper-loop/context/templates/REVIEWER_INIT.md"

   # 方案 B: 或者在 context/ 下创建符号链接
   ln -s templates/TESTER_INIT.md _hyper-loop/context/TESTER_INIT.md
   ln -s templates/REVIEWER_INIT.md _hyper-loop/context/REVIEWER_INIT.md
   ```

### P1 修复
2. **auto_decompose 路径**: 第 719-720 行加 `context/`:
   ```
   - BDD 行为规格：${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md
   - 评估契约：${PROJECT_ROOT}/_hyper-loop/context/contract.md
   ```
3. **cleanup 父目录**: 在 cleanup_round 末尾加 `rm -rf "$WORKTREE_BASE" 2>/dev/null`
4. **archive_round 路径**: 第 797 行加 `context/`
