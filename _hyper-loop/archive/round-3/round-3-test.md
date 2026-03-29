# Round 3 试用报告

测试时间：2026-03-30
测试方式：bash -n 语法检查 + BDD 场景逐条代码审计 + python3 单元验证

---

## 语法检查

```
bash -n scripts/hyper-loop.sh → exit 0 (syntax ok)
```

**结果：PASS**

---

## BDD 场景验证

### S001: loop 命令启动死循环 — PASS
- `cmd_loop` 函数存在（L822），接受 MAX_ROUNDS 参数
- 输出 `"LOOP: Round ${ROUND}/${MAX_ROUNDS}"` (L857)
- while 循环条件 `ROUND -le MAX_ROUNDS` (L847) 确保跑满退出
- `record_result` 写入 results.tsv (L889)
- 截图：`screenshots/round-3/s001-syntax-check.txt`

### S002: auto_decompose 生成任务文件 — PASS
- `auto_decompose` 函数存在 (L703)，被 cmd_loop 调用 (L865)
- Round 3 下有 3 个 task*.md，每个包含"修复任务"和"相关文件"段落
- 降级逻辑存在 (L764-783)：当 claude -p 失败时生成默认 task1.md
- 截图：`screenshots/round-3/s002-task-files.txt`

### S003: Writer worktree 创建 + trust + 启动 — PASS
- `git worktree add` (L124) 创建 worktree 到 `/tmp/hyper-loop-worktrees-rN/taskM`
- `~/.codex/config.toml` trust 预配置 (L130-131)
- Codex `--dangerously-bypass-approvals-and-sandbox` 启动 (L182)
- `_ctx/` 复制到 worktree (L136)
- 截图：`screenshots/round-3/s003-worktree-trust.txt`

### S004: Writer 完成后 diff 被正确 commit — PASS
- `git add -A && git commit` (L335-336) 确保 Writer 改动被提交
- squash merge 到 integration 分支 (L345)
- `.patch` 和 `.stat` 文件生成 (L339-342)
- 截图：`screenshots/round-3/s004-commit-merge.txt`

### S005: diff 审计拦截越界修改 — PASS
- `audit_writer_diff` 函数 (L239) 从 TASK.md 提取"相关文件"列表
- 越界文件检测 + VIOLATIONS 记录 (L264-283)
- 返回非零退出码 `return 1` (L288) → 合并被跳过 (L324-326)
- 允许 DONE.json/WRITER_INIT.md/_ctx/*/TASK.md (L277)
- 截图：`screenshots/round-3/s005-diff-audit.txt`

### S006: Writer 超时处理 — PASS
- 默认 TIMEOUT=900 (15分钟) (L198)
- 超时后写 `{"status":"timeout"}` 到 DONE.json (L224)
- merge_writers 检查 status≠done 则跳过 (L317-319)
- 截图：`screenshots/round-3/s006-timeout.txt`

### S007: Tester 启动并生成报告 — PASS (有 P0 前置条件缺陷)
- `run_tester` (L376) 启动 Claude 子进程
- 等待 REPORT_FILE 最多 900s (L404)
- 超时生成空报告 (L416-418)
- **但 TESTER_INIT.md 不存在** → 见 P0-001
- 截图：`screenshots/round-3/s007-tester.txt`

### S008: 3 Reviewer 启动并产出评分 — PASS (有 P0 前置条件缺陷)
- 3 个 Reviewer 配置正确：gemini/claude/codex (L450)
- 等待评分文件最多 600s (L467)
- 降级 pane 提取 JSON 逻辑完整 (L478-500)
- **但 REVIEWER_INIT.md 不存在** → 见 P0-001
- 截图：`screenshots/round-3/s008-reviewers.txt`

### S009: 和议计算正确 — PASS
- Python 中位数计算正确：`scores=[5.0,6.0,7.0] → median=6.0` (验证通过)
- ACCEPTED 条件：`median > prev_median` (L564)
- 截图：`screenshots/round-3/s009-median-test.txt`

### S010: 一票否决 (score < 4.0) — PASS
- `veto = any(s < 4.0 for s in scores)` (L547)
- `scores=[3.5,6.0,7.0] → veto=True → REJECTED_VETO` (验证通过)
- 截图：`screenshots/round-3/s010-veto-test.txt`

### S011: Tester P0 否决 — PASS
- `tester_p0 = "P0" in text and ("bug" in text.lower() or "fail" in text.lower())` (L553)
- 正向/反向验证均通过
- 截图：`screenshots/round-3/s011-p0-test.txt`

### S012: verdict.env 安全读取 — PASS
- 使用 `grep + cut` 而非 `source` (L618-620, L672-673, L894-895)
- 实测 SCORES="1.0 2.0 3.0" 正确提取，无 bash 解析错误
- 截图：`screenshots/round-3/s012-verdict-safe-read.txt`

### S013: 连续 5 轮失败自动回退 — PASS
- `CONSECUTIVE_REJECTS -ge 5 && BEST_ROUND -gt 0` (L919)
- 从 `archive/round-N/git-sha.txt` 读取 SHA 回退 (L923)
- `CONSECUTIVE_REJECTS=0` 重置 (L928)
- 截图：`screenshots/round-3/s013-rollback.txt`

### S014: STOP 文件优雅退出 — PASS
- 检测 `_hyper-loop/STOP` 文件 (L849)
- 输出"检测到 STOP 文件，优雅退出" (L850)
- `rm "$STOP_FILE"` 删除 (L851)
- `break` 退出循环而非 `exit` (L852) → 后续总结代码仍执行
- 截图：`screenshots/round-3/s014-stop-file.txt`

### S015: worktree 清理 — PASS
- `cleanup_round` (L587) 使用 subshell + `set +e` 防止清理失败终止循环
- `git worktree remove --force` (L601)
- `git branch -D` (L602)
- tmux writer/tester/reviewer windows 关闭 (L593-595)
- 截图：`screenshots/round-3/s015-cleanup.txt`

### S016: macOS timeout 兼容 — PASS
- 优先使用 `gtimeout` (L17-18)
- 其次检查原生 `timeout` (L19)
- 降级：自定义 timeout 函数 (L20)
- 当前系统已安装 gtimeout，验证通过
- 截图：`screenshots/round-3/s016-macos-timeout.txt`

### S017: 多 Writer 同文件冲突处理 — PASS
- `git merge --abort` 回滚冲突 (L350)
- 输出 "conflict, deferred" (L351)
- `FAILED++` 计数但不崩溃 (L352)
- 截图：`screenshots/round-3/s017-conflict.txt`

---

## Bug 列表

### P0-001: TESTER_INIT.md 和 REVIEWER_INIT.md 文件缺失
- **严重级别**: P0
- **位置**: `scripts/hyper-loop.sh` L381, L457
- **描述**: `run_tester` 引用 `_hyper-loop/context/TESTER_INIT.md`，`run_reviewers` 引用 `_hyper-loop/context/REVIEWER_INIT.md`，但这两个文件不存在。Tester 和 Reviewer 启动后无法读取角色定义，只能靠注入的 BDD spec 和 contract 工作。虽然脚本不会崩溃（文件路径只是作为文本注入给 agent），但 agent 缺少角色上下文会严重影响评审质量。
- **影响**: 历史两轮均 0.0/REJECTED_VETO，可能与此直接相关——Reviewer 不知道自己是谁、该怎么评分。
- **截图**: `screenshots/round-3/bug-missing-init-files.txt`

### P1-001: cmd_status 函数重复定义
- **严重级别**: P1
- **位置**: L694 和 L954
- **描述**: `cmd_status` 定义了两次。Bash 中后者覆盖前者，所以功能上不报错。但第一个版本缺少"最佳轮次"输出，属于死代码。应删除 L694-700 的第一个定义。
- **影响**: 功能无影响（第二个版本更完整），但属于代码质量问题。

### P1-002: auto_decompose heredoc 中变量转义错误
- **严重级别**: P1
- **位置**: L729
- **描述**: 在非引号 heredoc (`<<DPROMPT`) 中，`\$f` 导致 for 循环中的文件变量无法正确展开。`[[ -f "\$f" ]]` 测试的是字面字符串 `$f` 而非循环变量。结果是 auto_decompose 生成的 prompt 中不会包含上一轮评分详情。
- **影响**: Claude 拆解任务时缺少上一轮评分上下文，但由于 results.tsv 和 report 仍可参考，影响有限。
- **修复建议**: 将 heredoc 改为 quoted (`<<'DPROMPT'`) 并用其他方式注入变量，或提取该段为独立函数。

### P1-003: auto_decompose 中 bdd-specs/contract 路径不一致
- **严重级别**: P1 (降级为 P2：因为两个路径都有文件存在)
- **位置**: L716-717
- **描述**: `auto_decompose` 的 DECOMPOSE_PROMPT 中引用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`（无 context/ 前缀），但其他地方（L75-76, L435-436）统一用 `_hyper-loop/context/` 前缀。当前两处都有文件存在所以不报错，但路径不一致有维护风险。

---

## 总结

| 指标 | 结果 |
|------|------|
| bash -n 语法检查 | PASS |
| BDD 场景通过率 | 17/17 PASS (100%) |
| P0 Bug | 1 (TESTER_INIT.md/REVIEWER_INIT.md 缺失) |
| P1 Bug | 3 (cmd_status 重复、heredoc 变量转义、路径不一致) |
| 代码可读性 | 良好：函数分层清晰、注释充分、中文命名直观 |
| 错误处理 | 较完整：subshell 防崩溃、set +e 清理、降级逻辑、|| true 兜底 |

**关键发现**: 前两轮 0.0 分极可能与 P0-001 直接相关——Tester 和 Reviewer 缺少角色定义文件，导致 agent 无法正确执行评审流程。修复此问题应是 Round 4 的最高优先级。
