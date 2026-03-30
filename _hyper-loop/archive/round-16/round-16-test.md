# Round 16 试用报告

## 概要

- **bash -n 语法检查**: PASS (HEAD 版本 987 行通过)
- **BDD 场景**: 17 个中 14 PASS / 3 PASS_WITH_ISSUES
- **P0 bug**: 2 个
- **P1 bug**: 4 个
- **总评**: 脚本逻辑基本完整，但工作副本被破坏 + 关键 INIT 文件缺失阻碍实际运行

---

## BDD 场景逐条验证

### S001: loop 命令启动死循环 — PASS
- `cmd_loop` (line 825) 接受 MAX_ROUNDS 参数，默认 999
- 输出 "LOOP: Round ${ROUND}/${MAX_ROUNDS}" (line 860)
- while 循环检查 `ROUND -le MAX_ROUNDS` (line 850)
- `record_result` 写 results.tsv (line 625-628)
- 截图: `screenshots/round-16/s001-loop-structure.txt`

### S002: auto_decompose 生成任务文件 — PASS (有 P1)
- `auto_decompose` (line 706) 用 Claude -p 生成任务
- 降级生成默认 task1.md (line 770-785)
- 每个文件包含"修复任务"和"相关文件"(line 741, 746)
- **P1**: 传给 Claude 的 prompt 引用了错误路径 (见 P1-2)
- 截图: `screenshots/round-16/s002-auto-decompose.txt`

### S003: Writer worktree 创建 + trust + 启动 — PASS
- `git worktree add` 创建 /tmp/hyper-loop-worktrees-rN/taskM (line 124)
- trust 写入 ~/.codex/config.toml (line 131)
- Codex 在 tmux 中启动 (line 182)
- `_ctx/` 被复制 (line 136)
- 截图: `screenshots/round-16/s003-writer-worktree.txt`

### S004: Writer 完成后 diff 被正确 commit — PASS
- `git add -A && git commit` (line 338-339)
- squash merge 到 integration 分支 (line 348)
- `.patch` 和 `.stat` 文件生成 (line 342-345)
- 截图: `screenshots/round-16/s004-merge-writers.txt`

### S005: diff 审计拦截越界修改 — PASS
- `audit_writer_diff` (line 242) 检查越界
- 违规时 `return 1` (line 291)
- `merge_writers` 中调用，失败时跳过合并 (line 327-330)
- 截图: `screenshots/round-16/s005-diff-audit.txt`

### S006: Writer 超时处理 — PASS
- 默认 900s = 15 分钟 (line 198)
- 超时写 `{"status":"timeout"}` (line 224)
- 截图: `screenshots/round-16/s006-writer-timeout.txt`

### S007: Tester 启动并生成报告 — PASS (有 P0)
- `run_tester` (line 379) 启动 Claude 子进程
- 15 分钟超时 (line 407, 900s)
- 超时生成空报告 (line 419-421)
- **P0**: TESTER_INIT.md 文件不存在 (见 P0-2)
- 截图: `screenshots/round-16/s007-tester.txt`

### S008: 3 Reviewer 启动并产出评分 — PASS (有 P0)
- 3 个 Reviewer 定义 (line 453): gemini + claude + codex
- 10 分钟超时 (line 470)
- JSON 从 pane 提取有降级逻辑 (line 481-503)
- `"score" in obj` 检查 (line 495)
- **P0**: REVIEWER_INIT.md 文件不存在 (见 P0-2)
- 截图: `screenshots/round-16/s008-reviewers.txt`

### S009: 和议计算正确 — PASS
- 中位数计算逻辑正确 (Python3 验证: [5,6,7] → median=6.0)
- ACCEPTED 条件: median > prev_median (line 564)
- verdict.env 安全写入 (line 577-583)
- 截图: `screenshots/round-16/s009-verdict.txt`, `s009-s010-python-verify.txt`

### S010: 一票否决（score < 4.0）— PASS
- `any(s < 4.0 for s in scores)` (line 550)
- DECISION = REJECTED_VETO (line 559)
- Python 验证: [3.5, 6.0, 7.0] → veto=True
- 截图: `screenshots/round-16/s010-veto.txt`, `s009-s010-python-verify.txt`

### S011: Tester P0 否决 — PASS
- `"P0" in text and ("bug" in text.lower() or "fail" in text.lower())` (line 556)
- DECISION = REJECTED_TESTER_P0 (line 561)
- 截图: `screenshots/round-16/s011-tester-p0.txt`

### S012: verdict.env 安全读取 — PASS
- 全部使用 `grep '^KEY=' | cut -d= -f2` (line 621-623, 675-676, 897-898)
- 无 `source` 或 `. verdict.env`
- 不会出现 "command not found"
- 截图: `screenshots/round-16/s012-verdict-safe-read.txt`

### S013: 连续 5 轮失败自动回退 — PASS (条件性)
- `CONSECUTIVE_REJECTS >= 5 && BEST_ROUND > 0` (line 922)
- 回退到 BEST_ROUND 的 git-sha (line 926-929)
- `CONSECUTIVE_REJECTS` 重置为 0 (line 931)
- 注: 当前 15 轮全部 REJECTED_VETO，BEST_ROUND=0，回退不触发 (符合前置条件)
- 截图: `screenshots/round-16/s013-rollback.txt`

### S014: STOP 文件优雅退出 — PASS
- 检测 `_hyper-loop/STOP` (line 852)
- `rm "$STOP_FILE"` 删除 (line 854)
- `break` 退出循环 (line 855)，走正常退出路径
- 截图: `screenshots/round-16/s014-stop-file.txt`

### S015: worktree 清理 — PASS
- `worktree remove --force` (line 604)
- `branch -D` 删除分支 (line 605)
- `kill-window` 关闭 tmux (line 597)
- 全在 subshell + `set +e` 中运行 (line 594)
- 截图: `screenshots/round-16/s015-cleanup.txt`

### S016: macOS timeout 兼容 — PASS
- gtimeout 优先 (line 17-18)
- 自定义 timeout 函数作为终极降级 (line 20)
- 当前机器: gtimeout 和 timeout 都可用
- 截图: `screenshots/round-16/s016-timeout-compat.txt`

### S017: 多 Writer 同文件冲突处理 — PASS
- `merge --abort` 处理冲突 (line 353)
- "deferred" 提示 (line 354)
- `((FAILED++)) || true` 不崩溃 (line 355)
- 截图: `screenshots/round-16/s017-conflict.txt`

---

## P0 Bug 列表

### P0-1: 工作副本 scripts/hyper-loop.sh 被覆盖
- **现象**: 文件内容只有 1 行 `Script started on Mon Mar 30 04:15:42 2026`，应为 987 行
- **原因**: 疑似 `script` 命令误写入（根目录有 `started` 文件也佐证）
- **影响**: 当前工作副本的脚本不可用；`BUILD_CMD=bash -n scripts/hyper-loop.sh` 会"通过"但实际上测的是空文件
- **修复**: `git checkout HEAD -- scripts/hyper-loop.sh`
- **截图**: `screenshots/round-16/p0-missing-init-files.txt`

### P0-2: TESTER_INIT.md 和 REVIEWER_INIT.md 缺失
- **现象**: `_hyper-loop/context/TESTER_INIT.md` 和 `REVIEWER_INIT.md` 不存在
- **引用**: `run_tester` (line 384), `run_reviewers` (line 459) 通过 `start_agent` 注入
- **影响**: Tester 和 Reviewer Agent 启动后无角色定义，无法按预期评审。这可能是 15 轮全部 0 分的根本原因 — Agent 不知道自己该做什么。
- **修复**: 创建 TESTER_INIT.md 和 REVIEWER_INIT.md 模板文件
- **截图**: `screenshots/round-16/p0-missing-init-files.txt`

---

## P1 Bug 列表

### P1-1: auto_decompose 引用错误路径
- **位置**: line 719-720
- **现象**: 引用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`
- **正确**: `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`
- **影响**: Claude 拆解任务时读不到 BDD 规格和评估契约，降低任务质量
- **截图**: `screenshots/round-16/p1-wrong-paths.txt`

### P1-2: archive_round 引用错误路径
- **位置**: line 797
- **现象**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 路径不存在
- **正确**: `_hyper-loop/context/bdd-specs.md`
- **影响**: 归档时 bdd-specs.md 不会被复制（`|| true` 静默失败）
- **截图**: `screenshots/round-16/p1-wrong-paths.txt`

### P1-3: cmd_status 函数定义重复
- **位置**: line 697 和 line 957
- **现象**: 两处定义，第二个覆盖第一个
- **影响**: 第一个定义 (697-703) 是死代码
- **修复**: 删除第一个简单版本

### P1-4: Tester 超时消息不一致
- **位置**: line 421
- **现象**: 消息说 "Tester 未在 10 分钟内完成" 但实际超时是 900s = 15 分钟 (line 407)
- **修复**: 改为 "15 分钟"

---

## 评估总结

| 维度 | 评价 |
|------|------|
| bash -n 语法检查 | PASS (HEAD 版本) |
| BDD 场景通过率 | 14/17 clean PASS + 3/17 PASS with issues = 100% 逻辑存在 |
| 代码可读性 | 良好：中文注释、函数分离清晰、Python3 辅助计算 |
| 错误处理完整性 | 良好：subshell+set+e 防崩、|| true 容错、降级逻辑 |
| **关键阻塞** | P0-1 工作副本破坏 + P0-2 INIT 文件缺失导致循环无法正常运行 |

脚本架构完整，17 个 BDD 场景的逻辑都已实现。但 2 个 P0 bug 导致实际循环无法产出有效结果（解释了连续 15 轮 0 分的历史）。修复 P0-2（创建 INIT 文件）是打破 0 分循环的关键。
