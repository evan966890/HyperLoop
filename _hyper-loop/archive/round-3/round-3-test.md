# Round 3 — Tester 报告

## 语法检查
`bash -n scripts/hyper-loop.sh` — **PASS** (无语法错误)

## BDD 场景逐条检查

| ID | 结果 | 原因 |
|----|------|------|
| S001 | **PASS** | `cmd_loop` (L798) 接收 MAX_ROUNDS 参数，输出 "Round N/M"，循环跑满后正常退出，`record_result` 写入 results.tsv |
| S002 | **PASS** | `auto_decompose` (L679) 用 Claude -p 拆解任务，降级时生成 task1.md（L743），包含"修复任务"和"相关文件"段落 |
| S003 | **PASS** | `start_writers` (L101) 创建 /tmp/hyper-loop-worktrees-rN/taskM，写入 ~/.codex/config.toml trust 配置，复制 _ctx/ 到 worktree，在 tmux window 中启动 Codex |
| S004 | **FAIL** | **P0** — `merge_writers` 的信息输出（L311/321/350/359 的 echo）和返回值（L360 的 echo "$INTEGRATION_WT"）共用 stdout。`cmd_loop` L854 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获全部 stdout，导致变量包含多行垃圾文本而非纯路径。后续 `build_app "$INTEGRATION_WT"` 的 `cd` 必定失败。详见 P0-001 |
| S005 | **FAIL** | **P1** — `audit_writer_diff` (L259) 使用 `git diff --name-only HEAD` 只能检测已跟踪文件的修改，无法发现 Writer 新建的未跟踪文件。如果 Writer 在允许列表外新建文件，审计不会拦截，但后续 `git add -A` 会将其提交。详见 P1-001 |
| S006 | **PASS** | `wait_writers` (L196) 超时后写入 `{"status":"timeout"}` 到 DONE.json (L224)，merge_writers 跳过 status!=done 的 Writer |
| S007 | **PASS** | `run_tester` (L379) 用 `timeout 600 claude -p` 非交互模式运行，生成 reports/round-N-test.md，超时/无输出时生成默认报告（L411-413） |
| S008 | **PASS** | `run_reviewers` (L417) 并行启动 3 个 Reviewer（gemini/claude/codex），管道提取 JSON，fallback 给中立分 5（L479）。注：BDD 说"从 pane 输出提取"，实际已改为管道模式直接提取，功能等价 |
| S009 | **PASS** | `compute_verdict` (L486) 的 Python 脚本正确计算中位数、检查 ACCEPTED 条件（median > prev_median），verdict.env 用 grep+cut 安全读取 |
| S010 | **PASS** | Python 脚本 L523 `veto = any(s < 4.0 for s in scores)` → L531 `DECISION = "REJECTED_VETO"`，记录到 results.tsv |
| S011 | **PASS** | Python 脚本 L525-529 检查报告中包含 "P0" 且包含 "bug"/"fail" → L533 `DECISION = "REJECTED_TESTER_P0"` |
| S012 | **PASS** | `record_result` (L593-596) 和 `cmd_loop` (L872-873) 均使用 `grep+cut` 读取 verdict.env，不 source，不会出现 "command not found" |
| S013 | **PASS** | `cmd_loop` L897-906 检查 `CONSECUTIVE_REJECTS >= 5 && BEST_ROUND > 0`，从 archive 读取 git-sha.txt 并 checkout，重置 consecutive_rejects=0 |
| S014 | **PASS** | `cmd_loop` L827-830 检查 STOP 文件存在 → 删除 → break 退出循环，脚本正常结束（exit 0） |
| S015 | **FAIL** | **P1** — `cleanup_round` (L563) 移除各个 worktree 和分支，但未删除基目录 `/tmp/hyper-loop-worktrees-rN/` 本身。BDD 要求该目录不存在。详见 P1-002 |
| S016 | **PASS** | L17-21 依次检查 gtimeout → timeout → 自定义 fallback 函数，macOS 兼容 |
| S017 | **PASS** | `merge_writers` L348-356 squash merge 失败时 `merge --abort` + 标记 "conflict, deferred"，`((FAILED++)) || true` 防崩溃 |

## 发现的 Bug

### P0-001: merge_writers stdout 污染导致 build_app cd 失败 (致命)
- **位置**: `merge_writers()` L299-361 + 调用方 L629/L854
- **原因**: `merge_writers` 的所有 echo 信息输出（"合并 Writer 产出…"、"✓ task1 merged" 等）和返回路径（`echo "$INTEGRATION_WT"`）共用 stdout。当 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获输出时，变量变成多行文本：
  ```
  合并 Writer 产出...
    ✓ task1 merged
  合并完成: 1 merged, 0 failed/skipped
  /tmp/hyper-loop-worktrees-r1/integration
  ```
- **影响**: `build_app "$INTEGRATION_WT"` 中 `cd "$BUILD_DIR"` 必定失败。由于在 `if ! build_app` 上下文中 `set -e` 被抑制，cd 失败后构建命令在错误目录执行——所有后续流程（Tester、Reviewer、verdict）基于错误状态运行。
- **修复**: 将 merge_writers 中所有信息性 echo 改为 `echo "..." >&2`（输出到 stderr），只保留最后一行 `echo "$INTEGRATION_WT"` 输出到 stdout。

### P1-001: audit_writer_diff 漏检新建文件
- **位置**: `audit_writer_diff()` L259
- **原因**: `git diff --name-only HEAD` 只显示已跟踪文件的改动，不包含新建的未跟踪文件
- **影响**: Writer 可以在允许列表外新建文件而不被审计拦截
- **修复**: 追加 `git ls-files --others --exclude-standard` 到 CHANGED_FILES

### P1-002: worktree 基目录未清理
- **位置**: `cleanup_round()` L563-583
- **原因**: 只移除 task*/integration 子目录，未删除 `/tmp/hyper-loop-worktrees-rN/` 本身
- **修复**: 在循环结束后加 `rmdir "$WORKTREE_BASE" 2>/dev/null || true`

### P1-003: cmd_status 重复定义
- **位置**: L670-676（第一次）和 L932-944（第二次）
- **原因**: 第一个定义被第二个覆盖，成为死代码
- **修复**: 删除 L670-676 的第一个 cmd_status 定义

### P1-004: archive_round 复制路径错误
- **位置**: `archive_round()` L770
- **原因**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 但实际文件在 `_hyper-loop/context/bdd-specs.md`
- **影响**: 归档时 bdd-specs.md 始终复制失败（被 `|| true` 静默吞掉）
- **修复**: 改为 `cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md"`

## 总结

- **17 个 BDD 场景**: 14 PASS / 3 FAIL
- **P0 bug**: 1 个（merge_writers stdout 污染 — 阻断整个流程）
- **P1 bug**: 4 个（审计漏检、目录残留、重复定义、路径错误）
