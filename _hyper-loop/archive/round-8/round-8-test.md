# Round 8 试用报告

**Tester**: Claude Opus 4.6
**日期**: 2026-03-30
**脚本版本**: HyperLoop v5.3 (985 行)
**语法检查**: `bash -n` PASS (exit 0)

---

## BDD 场景验证

### S001: loop 命令启动死循环 — PASS
- `cmd_loop` 输出 `LOOP: Round ${ROUND}/${MAX_ROUNDS}` (line 857)
- 循环可跑满 N 轮后正常退出 (while + ROUND++ + break at MAX_ROUNDS)
- `record_result` 每轮追加到 results.tsv (line 622-624)
- 截图: `screenshots/round-8/s001-loop.txt`

### S002: auto_decompose 生成任务文件 — PASS (with P1 note)
- 生成到 `_hyper-loop/tasks/round-N/` (line 705-706)
- 每个文件包含"修复任务"和"相关文件"段落 (模板 line 738-750)
- Claude -p 失败时降级生成默认 task1.md (line 764-783)
- **P1**: line 716 引用 `_hyper-loop/bdd-specs.md` 而非 `_hyper-loop/context/bdd-specs.md`，路径不一致 (虽然两处文件都存在)
- 截图: `screenshots/round-8/s002-decompose.txt`

### S003: Writer worktree 创建 + trust + 启动 — PASS
- `git worktree add` 创建到 `/tmp/hyper-loop-worktrees-rN/taskM` (line 124)
- `~/.codex/config.toml` 写入 trust 配置 (line 130-132)
- Codex 在 tmux window 中启动 (line 179-182)
- `_ctx/` 目录复制到 worktree (line 136)
- 截图: `screenshots/round-8/s003-worktree.txt`

### S004: Writer 完成后 diff 被正确 commit — PASS
- `git add -A && git commit` 在 merge 前执行 (line 335-336)
- squash merge 到 integration 分支 (line 345)
- `.patch` 和 `.stat` 文件生成 (line 339-342)
- 截图: `screenshots/round-8/s004-merge.txt`

### S005: diff 审计拦截越界修改 — PASS
- 从 TASK.md 提取 `### 相关文件` 列表 (line 245-247)
- 比对 `git diff --name-only` (line 255)
- 越界时返回 exit 1 (line 288)
- Writer 产出被跳过不合并 (line 324-326)
- 截图: `screenshots/round-8/s005-audit.txt`

### S006: Writer 超时处理 — PASS
- 900s 超时后写 `{"status":"timeout"}` 到 DONE.json (line 224)
- merge_writers 视 timeout 为 failed 跳过 (line 317-319)
- 截图: `screenshots/round-8/s006-timeout.txt`

### S007: Tester 启动并生成报告 — PASS
- Tester 在 tmux 中启动 (start_agent, line 380-381)
- 等待 900s (15分钟, line 404)
- 超时时生成空报告而非崩溃 (line 416-418)
- 截图: `screenshots/round-8/s007-tester.txt`

### S008: 3 Reviewer 启动并产出评分 — PASS
- 3 个 Reviewer 在 tmux 中启动: gemini/claude/codex (line 450)
- 等待 600s (10分钟, line 467)
- JSON 包含 "score" 字段 (评审请求模板, line 446)
- 降级从 pane 输出提取 JSON (Python JSONDecoder, line 482-500)
- 截图: `screenshots/round-8/s008-reviewers.txt`

### S009: 和议计算正确 — PASS
- 中位数计算: `sorted + n//2` (line 543)
- 验证: `[5.0, 6.0, 7.0]` → median=6.0 正确
- `DECISION = ACCEPTED` 当 median > prev_median (line 562)
- verdict.env 可安全读取 (line 574-580)
- 截图: `screenshots/round-8/s009-verdict.txt`

### S010: 一票否决 (score < 4.0) — PASS
- `any(s < 4.0 for s in scores)` → veto=True (line 547)
- 验证: `[3.5, 6.0, 7.0]` → REJECTED_VETO 正确
- 记录到 results.tsv (record_result, line 609-625)
- 截图: `screenshots/round-8/s010-veto.txt`

### S011: Tester P0 否决 — PASS
- `"P0" in text and ("bug" in text.lower() or "fail" in text.lower())` (line 553)
- 触发 `REJECTED_TESTER_P0` (line 558)
- 截图: `screenshots/round-8/s011-tester-p0.txt`

### S012: verdict.env 安��读取 — PASS
- 全面使用 `grep '^KEY=' | cut -d= -f2` 替代 `source` (line 618-620, 672-673, 894-895)
- 验证: SCORES="1.0 2.0 3.0" 提取无 "command not found" 错误
- 截图: `screenshots/round-8/s012-verdict-safe.txt`

### S013: 连续 5 轮失败自动回退 — PASS
- `CONSECUTIVE_REJECTS >= 5 && BEST_ROUND > 0` 触发回退 (line 919)
- `git checkout $BEST_SHA -- .` 恢复代码 (line 925)
- `CONSECUTIVE_REJECTS=0` 重置计数器 (line 928)
- 截图: `screenshots/round-8/s013-rollback.txt`

### S014: STOP 文件优雅退出 — PASS
- STOP 文件检测在循环顶部 (line 849)
- 当前轮不执行 (break 在任何工作之前)
- `rm $STOP_FILE` 删除文件 (line 851)
- 脚本正常退出 exit 0 (break → 函数自然返回)
- 截图: `screenshots/round-8/s014-stop.txt`

### S015: worktree 清理 — PARTIAL PASS (P1 bug)
- subshell + set +e 防止清理失败终止循环 (line 591-592)
- `git worktree remove --force` 删除每个 worktree (line 601)
- `git branch -D` 删除分支 (line 602)
- tmux writer windows 被关闭 (line 593-595)
- **P1 BUG**: 不删除 `/tmp/hyper-loop-worktrees-rN/` 父目录本身。BDD 要求该目录不存在，但 `git worktree remove` 只删子目录，空壳父目录可能残留。需要在清理末尾加 `rm -rf "$WORKTREE_BASE" 2>/dev/null`
- 截图: `screenshots/round-8/s015-cleanup.txt`

### S016: macOS timeout 兼容 — PASS
- `gtimeout` 优先检测 (line 17)
- 自定义 `timeout` 函数作为 fallback (line 20: background + sleep + kill)
- 不会报 "command not found"
- 截图: `screenshots/round-8/s016-timeout-compat.txt`

### S017: 多 Writer 同文件冲突处理 — PASS
- 第一个 merge 成功 (line 345-348)
- 第二个报 conflict → `merge --abort` → "deferred" (line 349-353)
- `((FAILED++)) || true` 防止 set -e 退出 → 脚本不崩溃
- 截图: `screenshots/round-8/s017-conflict.txt`

---

## 总结

| 指标 | 结果 |
|------|------|
| bash -n 语法检查 | PASS |
| BDD 场景通过 | 16/17 PASS, 1 PARTIAL (S015) |
| P0 Bug | 0 |
| P1 Bug | 2 |

---

## Bug 列表

### P1-001: cleanup_round 不删除 worktree 父目录
- **场景**: S015
- **位置**: `scripts/hyper-loop.sh` line 597-606
- **描述**: `cleanup_round` 使��� `git worktree remove` 删除每个子目录，但不删除 `/tmp/hyper-loop-worktrees-rN/` 父目录本身。BDD S015 要求该目录不存在。
- **修复**: 在 subshell 末���加 `rm -rf "$WORKTREE_BASE" 2>/dev/null`

### P1-002: auto_decompose 内 bdd-specs/contract 路径不一致
- **场景**: S002
- **位置**: `scripts/hyper-loop.sh` line 716-717
- **描述**: decompose prompt 引用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，但规范路径是 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。目前两处都有文件所以不影响功能，但如果只保留 context/ 下的版本就会失败。
- **修复**: 统一引用为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`

### P1-003 (代码质量): cmd_status 重复定义
- **位置**: line 694 和 line 954
- **描述**: `cmd_status()` 被定义了两次。第二个定义覆盖第一个（多了"最佳轮次"显示）。第一个定义是死代码。
- **修复**: 删除 line 694-700 的第一个定义

### P1-004 (代码质量): cmd_loop 内 verdict 读取缩进不一致
- **位置**: line 894-895
- **描述**: `DECISION=` 和 `MEDIAN=` 的 grep 行缩进 2 空格，而周围代码缩进 6 空格。功能无影响但可读性差。
- **修复**: 统一缩进为 6 空格

---

## 评分建议

- **客观指标 (80%)**: bash -n 通过, 16/17 BDD PASS = ~94% → 约 7.5/10
- **主观维度 (20%)**: 代码结构清晰, 错误处理完整 (subshell+set+e, || true), 有降级方案, 但有缩进不一致和重复定义 → 约 6.5/7.0
- **综合建议**: 约 7.3/10
