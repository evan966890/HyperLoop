# Round 6 — Tester Report

**Date**: 2026-03-30
**Script**: `scripts/hyper-loop.sh`
**Syntax check**: `bash -n` PASS

---

## BDD Scenario Results

| ID | Result | Reason |
|----|--------|--------|
| S001 | PASS | `cmd_loop` (L798) accepts MAX_ROUNDS, 输出 "LOOP: Round N/M"，循环正常退出，`record_result` 每轮写入 results.tsv |
| S002 | PASS | `auto_decompose` (L679) 用 `claude -p -` 拆解，fallback 生成默认 task1.md (L740-758)，heredoc 内 `\$f` 转义正确 |
| S003 | PASS | `start_writers` (L101) 创建 worktree (L124)，写 `~/.codex/config.toml` trust (L130-132)，复制 `_ctx/` (L136)，Codex 在 tmux 中启动 (L179) |
| S004 | **FAIL** | `merge_writers` (L299) 的 echo 日志全输出到 stdout；`INTEGRATION_WT=$(merge_writers "$ROUND")` (L629/L854) 捕获了所有输出（含日志），导致 `build_app "$INTEGRATION_WT"` 的 `cd` 收到多行字符串而必定失败。**详见 P0-1** |
| S005 | **FAIL** | `audit_writer_diff` (L242) 用 `git diff --name-only HEAD` (L259) 只检测已跟踪文件的修改，Writer 新建的 untracked 文件完全绕过审计。**详见 P1-1** |
| S006 | PASS | `wait_writers` (L196) 超时后写入 `{"status":"timeout"}` (L224)，`merge_writers` 检查 status 跳过非 done (L320-324) |
| S007 | PASS | `run_tester` (L379) 用 `timeout 600 claude -p -` 运行，超时或空输出时生成默认报告 (L408-413)。BDD 说 tmux 但改为非交互管道模式，功能等价 |
| S008 | PASS | `run_reviewers` (L417) 并行跑 gemini/claude/codex 三个 Reviewer (L454-471)，fallback 给中立分 5 (L477-482)。BDD 说"从 pane 提取 JSON"但改为管道 + Python 提取，功能等价 |
| S009 | PASS | `compute_verdict` (L486) Python 计算中位数 (L519)，median > prev_median -> ACCEPTED (L538)，verdict.env 格式正确 (L551-556) |
| S010 | PASS | `veto = any(s < 4.0 for s in scores)` (L523) 正确检测，decision = REJECTED_VETO (L531) |
| S011 | PASS | `tester_p0 = "P0" in text and ("bug" in text.lower() or "fail" in text.lower())` (L529)，decision = REJECTED_TESTER_P0 (L533)。注意 veto 优先级高于 tester_p0 |
| S012 | PASS | 用 `grep + cut` 读取 verdict.env (L594-596, L648-649, L872-873)，不 source，安全 |
| S013 | **FAIL** | `BEST_ROUND` 仅在 ACCEPTED 时更新 (L882-885)；若所有轮次都被拒绝，BEST_ROUND=0，`BEST_ROUND > 0` 条件 (L897) 永不满足，回退逻辑永远不触发。**详见 P1-2** |
| S014 | PASS | `cmd_loop` (L827-830) 检测 STOP 文件，删除后 break，脚本正常退出 |
| S015 | PASS | `cleanup_round` (L563) 遍历 worktree 目录并 `git worktree remove --force` (L577) + `git branch -D` (L578)，tmux windows 也被 kill (L569-571) |
| S016 | PASS | L17-21 检测 gtimeout，缺失时定义纯 bash fallback 函数 |
| S017 | PASS | `merge_writers` (L348-356) squash merge 冲突时 `merge --abort` + "deferred"，FAILED 计数器递增，脚本不崩溃 |

---

## Bug List

### P0-1: `merge_writers` stdout 污染导致构建路径错误

**位置**: L299-361 (`merge_writers`), L629/L854 (调用方)
**影响**: 每轮构建必定失败，循环无法正常运行
**描述**:
`merge_writers` 内所有 `echo` 日志输出到 stdout：
```
合并 Writer 产出...                    # L311 -> stdout
  ✓ task1 merged                       # L350 -> stdout
合并完成: 1 merged, 0 failed/skipped   # L359 -> stdout
/tmp/hyper-loop-worktrees-r6/integration  # L360 -> stdout (期望的返回值)
```
调用方 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获全部 stdout，`build_app "$INTEGRATION_WT"` 收到多行字符串，`cd "$BUILD_DIR"` 必定失败。
**修复**: 将 merge_writers 的日志 echo 重定向到 stderr (`>&2`)，仅保留最后一行 path 输出到 stdout。

### P1-1: `audit_writer_diff` 未检测 untracked 新文件

**位置**: L259 (`git diff --name-only HEAD`)
**影响**: Writer 创建 TASK.md 范围外的新文件可绕过审计
**描述**: `git diff --name-only HEAD` 只检测已跟踪文件的变更，新创建的 untracked 文件不会出现在 diff 中。随后 `git add -A` (L338) 会将这些文件全部提交并合并，越界文件不被拦截。
**修复**: 在 diff 检查中加入 `git ls-files --others --exclude-standard` 获取 untracked 文件列表。

### P1-2: 连续失败回退在无 ACCEPTED 轮次时永不触发

**位置**: L882-885 (BEST_ROUND 更新), L897 (回退条件)
**影响**: 若所有轮次均被拒绝，5 轮失败回退逻辑失效，循环空转
**描述**: `BEST_ROUND` 仅在 DECISION=ACCEPTED 时更新。若循环从未接受过任何轮次，`BEST_ROUND` 保持 0，`BEST_ROUND > 0` 条件永不满足，回退永不触发。
**修复**: 改为追踪所有轮次中 median 最高的（不仅限 ACCEPTED），或在 BEST_ROUND=0 时使用初始 git sha 作为回退点。

### P1-3: `cmd_status` 重复定义

**位置**: L670-676 (第一次定义), L932-943 (第二次定义)
**影响**: 第一个定义是死代码，第二个覆盖第一个
**描述**: 两处 `cmd_status()` 函数定义，bash 使用最后一个。第一个 (L670) 功能较少，第二个 (L932) 多了"最佳轮次"显示。
**修复**: 删除 L670-676 的第一个定义。

### P1-4: `PREV_MEDIAN` 空值导致 Python 崩溃

**位置**: L846-848 (`PREV_MEDIAN` 读取), L521 (Python `float()`)
**影响**: results.tsv 存在但为空时，`PREV_MEDIAN` 为空字符串，Python `float('')` 抛出 ValueError，`set -e` 下脚本终止
**描述**: L846 只检查 `-f`（文件存在）不检查 `-s`（非空），而 L813 处用了 `-f && -s`。`cut -f2` 对空输入返回空字符串且 exit 0，`|| echo 0` 不触发。
**修复**: 将 L846 的 `-f` 改为 `-f ... && -s ...`，或在 Python 中加 `float(s or '0')`。

### P2-1: `archive_round` 复制 bdd-specs.md 路径错误

**位置**: L770
**影响**: 归档静默失败（`|| true`），archive 缺少 BDD 规格副本
**描述**: 代码写 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`，实际路径是 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。
**修复**: 改为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。

### P2-2: `build_app` 改变全局 CWD

**位置**: L367 (`cd "$BUILD_DIR"`)
**影响**: 后续操作在被删除的目录中执行（cleanup_round 删除 worktree 后），虽然当前代码全用绝对路径未崩溃，但很脆弱
**修复**: 用 `(cd "$BUILD_DIR" && eval ...)` subshell 隔离 CWD 变更。

---

## Summary

- **PASS**: 14/17 scenarios
- **FAIL**: 3/17 scenarios (S004, S005, S013)
- **P0 bugs**: 1 (merge_writers stdout 污染 -- 每轮构建必定失败)
- **P1 bugs**: 4 (audit 漏洞、回退逻辑缺陷、重复定义、空值崩溃)
- **P2 bugs**: 2 (路径错误、CWD 污染)
