# Round 12 试用报告

**测试日期**: 2026-03-30
**测试对象**: scripts/hyper-loop.sh (HyperLoop v5.3)
**构建验证**: `bash -n scripts/hyper-loop.sh` → syntax ok ✓

---

## BDD 场景逐条验证

| 场景 | 描述 | 结果 | 截图 |
|------|------|------|------|
| S001 | loop 命令启动死循环 | **PASS** | screenshots/round-12/S001-loop-start.txt |
| S002 | auto_decompose 生成任务文件 | **PASS** | screenshots/round-12/S002-verify.txt |
| S003 | Writer worktree 创建 + trust + 启动 | **PASS** | screenshots/round-12/S003-verify.txt |
| S004 | Writer 完成后 diff 被正确 commit | **PASS** | screenshots/round-12/S004-verify.txt |
| S005 | diff 审计拦截越界修改 | **PASS** | screenshots/round-12/S005-verify.txt |
| S006 | Writer 超时处理 | **PASS** | screenshots/round-12/S006-verify.txt |
| S007 | Tester 启动并生成报告 | **PASS** | screenshots/round-12/S007-verify.txt |
| S008 | 3 Reviewer 启动并产出评分 | **PASS** | screenshots/round-12/S008-verify.txt |
| S009 | 和议计算正确 | **PASS** | screenshots/round-12/S009-verify.txt |
| S010 | 一票否决（score < 4.0） | **PASS** | screenshots/round-12/S010-verify.txt |
| S011 | Tester P0 否决 | **PASS** | screenshots/round-12/S011-verify.txt |
| S012 | verdict.env 安全读取 | **PASS** | screenshots/round-12/S012-verify.txt |
| S013 | 连续 5 轮失败自动回退 | **PASS** | screenshots/round-12/S013-verify.txt |
| S014 | STOP 文件优雅退出 | **PASS** | screenshots/round-12/S014-verify.txt |
| S015 | worktree 清理 | **PASS** | screenshots/round-12/S015-verify.txt |
| S016 | macOS timeout 兼容 | **PASS** | screenshots/round-12/S016-verify.txt |
| S017 | 多 Writer 同文件冲突处理 | **PASS** | screenshots/round-12/S017-verify.txt |

**总计: 17/17 PASS**

---

## 详细验证说明

### S001: loop 命令启动死循环
- `cmd_loop()` 接受 MAX_ROUNDS 参数（默认 999），line 826
- 输出格式 `"LOOP: Round ${ROUND}/${MAX_ROUNDS}"`，line 860
- `record_result()` 写 tab 分隔记录到 results.tsv，lines 613-627
- 循环条件 `while [[ "$ROUND" -le "$MAX_ROUNDS" ]]`，line 850

### S002: auto_decompose 生成任务文件
- `auto_decompose()` 调用 `claude -p` 生成任务，lines 706-789
- 降级：如果 claude 失败，自动生成包含"修复任务"和"相关文件"的 task1.md，lines 768-786
- Round 12 实际已有 4 个 task 文件（task1-task4.md）

### S003: Writer worktree 创建 + trust + 启动
- `git worktree add` 创建 `/tmp/hyper-loop-worktrees-rN/taskM`，line 124
- 写入 `~/.codex/config.toml` trust 配置，line 131
- `codex --dangerously-bypass-approvals-and-sandbox` 在 tmux 启动，line 182
- `cp -r context _ctx/`，line 136

### S004: Writer 完成后 diff 被正确 commit
- `git add -A && git commit` 在 worktree 执行，lines 338-339
- `git merge --squash` 到 integration 分支，line 348
- `.patch` 和 `.stat` 文件生成，lines 342-345

### S005: diff 审计拦截越界修改
- 从 TASK.md `### 相关文件` 提取允许列表，line 248
- 比对 `git diff --name-only`，line 258
- 越界返回 `return 1`，line 291
- merge 阶段检查并跳过，lines 327-330

### S006: Writer 超时处理
- 默认 900s（15 分钟），line 198
- 超时写 `{"status":"timeout"}` 到 DONE.json，line 224
- merge_writers 检查 status != done 则跳过，lines 319-321

### S007: Tester 启动并生成报告
- `start_agent "tester"` 在 tmux 启动 Claude，line 383
- 等待最多 900s（15 分钟），line 407
- 超时生成空报告 "Tester 超时"，lines 418-421

### S008: 3 Reviewer 启动并产出评分
- 3 个 Reviewer: `gemini --yolo / claude / codex --full-auto`，line 453
- 等待最多 600s（10 分钟），line 470
- 降级：从 tmux pane 用 Python 提取 JSON，lines 481-505
- 提取逻辑检查 `"score" in obj`，line 495

### S009: 和议计算正确
- Python median：`scores[n//2]`（奇数），`(scores[n//2-1]+scores[n//2])/2`（偶数），line 546
- ACCEPTED: `median > prev_median`，line 564
- 实测：`median([5.0, 6.0, 7.0]) = 6.0` ✓

### S010: 一票否决（score < 4.0）
- `veto = any(s < 4.0 for s in scores)`，line 550
- `REJECTED_VETO`，line 559（优先级最高）
- 实测：`[3.5, 6.0, 7.0]` → veto=True ✓

### S011: Tester P0 否决
- `"P0" in text and ("bug" in text.lower() or "fail" in text.lower())`，line 556
- `REJECTED_TESTER_P0`，line 561
- 实测：含 P0+fail 的报告 → detected ✓

### S012: verdict.env 安全读取
- 所有读取用 `grep + cut`，不用 `source`
- record_result: lines 621-623
- cmd_round: lines 675-676
- cmd_loop: lines 897-898
- 实测：grep 提取 DECISION/MEDIAN 正确 ✓

### S013: 连续 5 轮失败自动回退
- `CONSECUTIVE_REJECTS` 跟踪连续失败数，line 846
- `>= 5 && BEST_ROUND > 0` 触发回退，line 922
- 从 `archive/round-N/git-sha.txt` 读取 SHA，line 926
- `git checkout $SHA -- .` 恢复代码，line 928
- `CONSECUTIVE_REJECTS=0` 重置，line 931

### S014: STOP 文件优雅退出
- 每轮检查 `_hyper-loop/STOP`，line 852
- `rm "$STOP_FILE"` 删除 + `break` 退出，lines 854-855

### S015: worktree 清理
- `git worktree remove --force`，line 604
- `git branch -D`，line 605
- `tmux kill-window` 关闭 writer/tester/reviewer，line 597
- 包裹在 `set +e` subshell 中防崩溃，line 594

### S016: macOS timeout 兼容
- 优先 `gtimeout`，line 17
- 次选 native `timeout`
- 兜底：`sleep + kill` 实现，lines 19-20
- 本机测试：`timeout is /opt/homebrew/bin/timeout` ✓

### S017: 多 Writer 同文件冲突处理
- `merge --squash` 尝试合并，line 348
- 失败时 `merge --abort`，line 353
- 输出 "conflict, deferred"，line 354
- 循环继续（不 exit，不 crash）

---

## Bug 列表

### P1 (低优先级)

1. **cmd_status 重复定义** — lines 697 和 957 各有一个 `cmd_status()` 函数。第二个覆盖第一个。第一个成为死代码。不影响功能（第二个版本更完整，增加了"最佳轮次"显示），但代码不整洁。

2. **bdd-specs.md / contract.md 路径不一致** — `auto_decompose` (line 719-720) 和 `archive_round` (line 797) 使用 `_hyper-loop/bdd-specs.md`（根目录），而 `start_agent` (line 75) 和 `run_reviewers` (line 439) 使用 `_hyper-loop/context/bdd-specs.md`。当前两个位置都存在相同文件，不影响运行，但若有人只维护一份会导致数据分歧。

### P0 Bug: 无

---

## 评分建议

### 客观指标（80%权重）
- `bash -n` 语法检查: **PASS** ✓
- BDD 场景通过率: **17/17 = 100%** ✓

### 主观维度（20%权重，上限 7.0）
- 代码可读性: 良好。注释清晰，函数命名语义明确，结构层次分明
- 错误处理完整性: 优秀。`set +e` subshell、`|| true`、超时降级、pane 提取降级
- P1 问题: cmd_status 重复定义、路径不一致（不影响运行）

### 建议总分
- 客观: 10.0 × 0.8 = 8.0
- 主观: 6.5 × 0.2 = 1.3（因 P1 代码整洁问题扣 0.5）
- **总计: 9.3**（未封顶前）
- 契约主观上限 7.0 → 主观部分 = 7.0 × 0.2 = 1.4
- **封顶后总计: 8.0 + 1.4 = 9.4**
