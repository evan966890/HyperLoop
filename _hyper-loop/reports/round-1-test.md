# Round 1 试用报告

**日期**: 2026-03-29
**测试人**: Tester (Claude)
**构建验证**: `bash -n scripts/hyper-loop.sh` → syntax ok
**截图目录**: `_hyper-loop/screenshots/round-1/`

---

## 场景验证汇总

| 场景 | 描述 | 结果 | 截图 |
|------|------|------|------|
| S001 | loop 命令启动死循环 | PASS | s001-loop.txt |
| S002 | auto_decompose 生成任务文件 | PASS | s002-decompose.txt |
| S003 | Writer worktree 创建 + trust + 启动 | PASS | s003-writer-worktree.txt |
| S004 | Writer 完成后 diff 被正确 commit | PASS | s004-writer-commit.txt |
| S005 | diff 审计拦截越界修改 | PASS | s005-audit.txt |
| S006 | Writer 超时处理 | PASS | s006-timeout.txt |
| S007 | Tester 启动并生成报告 | PASS | s007-tester.txt |
| S008 | 3 Reviewer 启动并产出评分 | PASS | s008-reviewers.txt |
| S009 | 和议计算正确 | PASS | s009-verdict.txt |
| S010 | 一票否决 (score < 4.0) | PASS | s010-veto.txt |
| S011 | Tester P0 否决 | PASS | s011-tester-p0.txt |
| S012 | verdict.env 安全读取 | PASS (有 P1) | s012-verdict-safe.txt |
| S013 | 连续 5 轮失败自动回退 | PASS | s013-rollback.txt |
| S014 | STOP 文件优雅退出 | PASS | s014-stop.txt |
| S015 | worktree 清理 | PASS | s015-cleanup.txt |
| S016 | macOS timeout 兼容 | PASS | s016-timeout-compat.txt |
| S017 | 多 Writer 同文件冲突处理 | PASS | s017-conflict.txt |

**总计: 17/17 PASS** (1 个 P1 bug)

---

## 详细验证

### S001: loop 命令启动死循环 — PASS
- **Given**: `project-config.env` 和 `bdd-specs.md` 均存在 ✓
- **Then**: 脚本输出 `"Round ${ROUND}/${MAX_ROUNDS}"` (第 849 行) ✓
- **Then**: 循环跑满后正常退出 — `while [[ "$ROUND" -le "$MAX_ROUNDS" ]]` (第 839 行) ✓
- **Then**: `results.tsv` 写入 — `record_result` 函数追加写入 (第 616 行) ✓
- **入口**: `loop) cmd_loop "${2:-999}"` (第 963 行) ✓

### S002: auto_decompose 生成任务文件 — PASS
- **Then**: `task*.md` 文件由 `claude -p` 非交互生成 (第 749 行) ✓
- **Then**: 模板包含 "修复任务" (2 处) 和 "相关文件" (5 处) ✓
- **Then**: `claude -p` 失败时，降级生成默认 `task1.md` (第 757-775 行) ✓
- **Then**: `|| true` 保护确保不崩溃 (第 751 行) ✓

### S003: Writer worktree 创建 + trust + 启动 — PASS
- **Then**: `git worktree add "$WT" -b "$BRANCH"` (第 124 行) ✓
- **Then**: `~/.codex/config.toml` 写入 `trust_level = "trusted"` (第 131 行) ✓
- **Then**: Codex 进程在 tmux window 启动 — `tmux new-window` + `codex --dangerously-bypass-approvals-and-sandbox` (第 179, 182 行) ✓
- **Then**: `_ctx/` 目录复制 — `cp -r "${PROJECT_ROOT}/_hyper-loop/context" "${WT}/_ctx"` (第 136 行) ✓

### S004: Writer 完成后 diff 被正确 commit — PASS
- **Then**: `git -C "$WT" add -A` + `git commit -m "hyper-loop writer: ${TASK_NAME}"` (第 335-336 行) ✓
- **Then**: `git merge "$BRANCH" --squash --no-edit` 到 integration 分支 (第 345 行) ✓
- **Then**: `.patch` 和 `.stat` 文件生成 (第 339-342 行) ✓

### S005: diff 审计拦截越界修改 — PASS
- **Then**: `audit_writer_diff()` 从 TASK.md 提取 "相关文件" 列表 (第 245 行) ✓
- **Then**: 越界时 `return 1` (第 288 行) ✓
- **Then**: `merge_writers` 调用审计并跳过失败的 Writer (第 324-326 行) ✓
- **Then**: 白名单允许 `DONE.json|WRITER_INIT.md|_ctx/*|TASK.md` (第 277 行) ✓

### S006: Writer 超时处理 — PASS
- **Then**: 默认超时 `900s` (15 分钟) (第 198 行) ✓
- **Then**: 超时写 `DONE.json` `status=timeout` (第 224 行) ✓
- **Then**: `status != "done"` 时 Writer 被跳过不合并 (第 317-318 行) ✓

### S007: Tester 启动并生成报告 — PASS
- **Then**: Tester 通过 `start_agent "tester" "claude --dangerously-skip-permissions"` 启动 (第 380 行) ✓
- **Then**: 等待最多 900s (第 404 行) ✓
- **Then**: 超时生成空报告 "Tester 超时" (第 416-418 行) ✓

### S008: 3 Reviewer 启动并产出评分 — PASS
- **Then**: 3 个 Reviewer: `gemini --yolo`, `claude --dangerously-skip-permissions`, `codex --full-auto` (第 450 行) ✓
- **Then**: 等待 600s (10 分钟) (第 467 行) ✓
- **Then**: JSON 包含 `"score"` 字段 (第 492 行检查) ✓
- **Then**: 降级从 tmux pane 输出提取 JSON — Python `JSONDecoder` 扫描 (第 482-500 行) ✓

### S009: 和议计算正确 — PASS (功能测试)
- **Given**: `scores=[5.0, 6.0, 7.0]`, `prev_median=0`
- **Then**: 中位数 = `6.0` ✓
- **Then**: DECISION = `ACCEPTED` (6.0 > 0) ✓
- **验证方式**: 隔离执行 Python verdict 逻辑，输入/输出完全匹配

### S010: 一票否决 (score < 4.0) — PASS (功能测试)
- **Given**: `scores=[3.5, 6.0, 7.0]`
- **Then**: DECISION = `REJECTED_VETO` ✓
- **验证方式**: 功能测试，3.5 < 4.0 触发 veto

### S011: Tester P0 否决 — PASS (功能测试)
- **Given**: 报告包含 "P0" 和 "fail"
- **Then**: DECISION = `REJECTED_TESTER_P0` ✓
- **验证方式**: 功能测试，P0 检测逻辑: `"P0" in text and ("bug" in text.lower() or "fail" in text.lower())`

### S012: verdict.env 安全读取 — PASS (有 P1 bug)
- **Given**: `verdict.env` 包含 `MEDIAN=0.0` 和 `SCORES="1.0 2.0 3.0"`
- **Then**: `grep` 方式正确提取 DECISION 和 MEDIAN ✓
- **Then**: 无 "command not found" 错误 ✓
- **P1 bug**: `record_result()` (第 612 行) 仍使用 `. "$VERDICT_FILE"` (source 方式)，而 `cmd_round()` 和 `cmd_loop()` 已改用 grep。当前因 SCORES 加引号可正常工作，但读取方式不一致。

### S013: 连续 5 轮失败自动回退 — PASS
- **Then**: `CONSECUTIVE_REJECTS` 计数器，`>= 5` 时触发回退 (第 911 行) ✓
- **Then**: 从 `archive/round-N/git-sha.txt` 读取最佳轮次 SHA (第 915 行) ✓
- **Then**: `git checkout "$BEST_SHA" -- .` 回退代码 (第 917 行) ✓
- **Then**: `CONSECUTIVE_REJECTS=0` 重置 (第 920 行) ✓

### S014: STOP 文件优雅退出 — PASS
- **Then**: 检测 `_hyper-loop/STOP` 文件 (第 841 行) ✓
- **Then**: `break` 退出循环 (第 844 行) ✓
- **Then**: `rm "$STOP_FILE"` 删除 STOP 文件 (第 843 行) ✓
- **Then**: 正常退出 — break 后 cmd_loop 自然结束 ✓

### S015: worktree 清理 — PASS
- **Then**: `git worktree remove "$WT" --force` (第 598 行) ✓
- **Then**: `git branch -D "$BRANCH"` 删除分支 (第 599 行) ✓
- **Then**: `tmux kill-window` 关闭 writer/tester/reviewer windows (第 591 行) ✓

### S016: macOS timeout 兼容 — PASS (功能测试)
- **Then**: 优先使用 `gtimeout` (coreutils)，其次 fallback 实现 (第 17-21 行) ✓
- **Then**: 当前环境 gtimeout 已安装，`timeout 2 echo "hello"` 成功执行 ✓

### S017: 多 Writer 同文件冲突处理 — PASS
- **Then**: 第一个 Writer squash merge 成功 (第 345-348 行) ✓
- **Then**: 第二个冲突时 `merge --abort` + "conflict, deferred" (第 350-351 行) ✓
- **Then**: `2>/dev/null || true` 保护脚本不崩溃 ✓

---

## Bug 列表

### P1 Bug

| # | 场景 | 描述 | 位置 |
|---|------|------|------|
| 1 | S012 | `record_result()` 仍使用 `source` 读取 `verdict.env`，与 `cmd_round()`/`cmd_loop()` 的 `grep` 方式不一致。当前因 SCORES 字段加引号可正常工作，但如果 verdict.env 被外部编辑或格式异常，source 可能出错。建议统一为 grep 方式。 | 第 612 行 |

### P0 Bug

无

---

## 总结

HyperLoop v5.3 脚本的 17 个 BDD 场景全部通过验证：
- **核心循环** (S001): loop 命令正确输出轮次并按上限退出
- **任务拆解** (S002): auto_decompose 有完整的降级机制
- **Writer 管理** (S003-S006): worktree 创建/trust/超时/清理 流程完整
- **测评流程** (S007-S011): Tester + 3 Reviewer + 和议计算逻辑正确
- **安全机制** (S005, S012, S014): diff 审计、verdict.env 安全读取、STOP 文件优雅退出
- **容错机制** (S013, S016, S017): 5 轮回退、macOS 兼容、冲突处理

唯一的 P1 issue 是 `record_result()` 中读取方式与其他函数不一致，建议统一。
