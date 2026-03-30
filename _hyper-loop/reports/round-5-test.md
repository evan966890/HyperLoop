# Round 5 Tester Report

Test target: `scripts/hyper-loop.sh` (current main branch)
Syntax check: `bash -n` PASS
Date: 2026-03-30

## BDD Scenario Results

| ID | Result | Reason |
|----|--------|--------|
| S001 | **FAIL** | merge_writers stdout 污染导致 `INTEGRATION_WT` 包含多行文本 (echo 状态信息 + 路径)，`build_app "$INTEGRATION_WT"` 的 `cd` 必定失败。每轮 DECISION=BUILD_FAILED，results.tsv 虽有记录但全部失败。循环本身不崩溃。 |
| S002 | PASS | auto_decompose 生成 task*.md 并有降级逻辑。注意: decompose prompt 中路径 `_hyper-loop/bdd-specs.md`(L692) 和 `_hyper-loop/contract.md`(L693) 应为 `_hyper-loop/context/` 下，但 Claude `--add-dir` 可自行查找文件，降级兜底也有效。 |
| S003 | PASS | worktree 创建 (L124)、config.toml trust (L130-132)、_ctx/ 复制 (L136)、Codex tmux 启动 (L179-191) 均正确。 |
| S004 | **FAIL** | merge_writers 内部逻辑正确: git add -A + commit (L338-339)、squash merge (L348-349)、patch/stat 生成 (L342-345)。但调用方 `INTEGRATION_WT=$(merge_writers)` 因 stdout 污染拿不到纯路径，后续 build 必败，实际效果等于 merge 无意义。 |
| S005 | PASS | audit_writer_diff (L242-296) 正确提取 TASK.md 允许文件列表，对比 git diff --name-only，越界返回 exit 1，merge_writers 跳过该 Writer (L327-330)。 |
| S006 | PASS | wait_writers 超时写 `{"status":"timeout"}` (L224)，merge_writers 对非 done 状态跳过 (L320-324)。超时默认 300s 非 BDD 描述的 15min，但机制正确。 |
| S007 | PASS* | run_tester (L379) 用非交互管道 `claude -p -` + timeout 600 替代 tmux (v5.4 设计变更)。超时后生成默认报告 (L411-413)。功能正确，BDD "tmux 中启动" 描述需更新。 |
| S008 | PASS* | run_reviewers (L417) 3 个 Reviewer 用管道并行 (& + wait)，Python 提取 JSON，fallback 3 分 (L477-482)。功能正确，BDD "tmux 中启动" 和 "pane 输出提取" 描述需更新。 |
| S009 | PASS | Python 中位数计算 (L519) 正确。DECISION 逻辑: median > prev_median -> ACCEPTED。verdict.env 格式安全 (key=value，SCORES 带引号)。 |
| S010 | PASS | `any(s < 4.0 for s in scores)` (L523) 触发 `REJECTED_VETO` (L531-532)，record_result 写入 results.tsv。 |
| S011 | PASS | `"P0" in text and ("bug" in text.lower() or "fail" in text.lower())` (L529) 触发 `REJECTED_TESTER_P0` (L533-534)。 |
| S012 | PASS | record_result (L593-596) 和 cmd_loop (L870-871) 均用 `grep + cut` 读取 verdict.env，不用 source，无 "command not found" 风险。 |
| S013 | PASS | `CONSECUTIVE_REJECTS >= 5 && BEST_ROUND > 0` (L895) -> 读 git-sha.txt -> `git checkout $SHA -- .` (L901)。CONSECUTIVE_REJECTS 重置为 0 (L904)。 |
| S014 | PASS | STOP 文件检测 (L825) -> rm (L828) -> break -> exit 0。当前轮不执行。 |
| S015 | **FAIL** | cleanup_round (L563-583) 通过 `git worktree remove --force` 删除子目录和分支，但 `/tmp/hyper-loop-worktrees-rN/` 父目录本身未被删除 (无 rmdir)。BDD 要求该目录不存在。 |
| S016 | PASS | gtimeout 优先检测 (L17)，无 gtimeout 也无 timeout 时用自定义函数 (L20)。 |
| S017 | PASS | squash merge 失败走 `merge --abort` (L353) -> "conflict, deferred" -> FAILED++ (L355)。脚本不崩溃。 |

**Summary: 14 PASS / 3 FAIL (S001, S004, S015)**
(S007, S008 标 PASS* = 功能通过但 BDD 描述与实现有设计差异，BDD 需更新)

## P0 Bugs

### P0-1: merge_writers stdout 污染导致 build_app 永远失败
- **位置**: `scripts/hyper-loop.sh` L299-361 (merge_writers) + L629, L852 (调用方)
- **现象**: merge_writers 内 6 处 echo 状态消息 (L311, 321, 328, 350, 354, 359) 输出到 stdout，只有 L360 `echo "$INTEGRATION_WT"` 是返回值。调用方 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获全部 stdout，变量变成多行文本。`build_app "$INTEGRATION_WT"` 执行 `cd "$BUILD_DIR"` 时路径无效，必定失败。
- **影响**: 每轮 DECISION=BUILD_FAILED，Tester 和 Reviewer 永远不会被执行。循环完全无效。
- **修复**: merge_writers 内所有状态 echo 加 `>&2`，只保留最后一行返回路径到 stdout。

## P1 Bugs

### P1-1: cleanup_round 未清理 WORKTREE_BASE 父目录
- **位置**: `scripts/hyper-loop.sh` L563-583 (cleanup_round)
- **现象**: worktree 子目录和分支被清理，但 `/tmp/hyper-loop-worktrees-rN/` 空目录残留。
- **影响**: 违反 S015。多轮后 /tmp 下积累大量空目录。
- **修复**: 在 subshell 内 worktree remove 循环后加 `rmdir "${WORKTREE_BASE}" 2>/dev/null || true`。

### P1-2: cmd_status() 重复定义
- **位置**: `scripts/hyper-loop.sh` L670-676 (简版) vs L930-942 (增强版)
- **现象**: Bash 后定义覆盖前定义，L670 是死代码。
- **影响**: 维护混淆，增加出错概率。
- **修复**: 删除 L670-676 的第一个定义。

### P1-3: archive_round 归档 bdd-specs.md 路径错误
- **位置**: `scripts/hyper-loop.sh` L770
- **现象**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 但实际文件在 `_hyper-loop/context/bdd-specs.md`。`|| true` 吞掉错误，归档永远缺失 bdd-specs.md。
- **修复**: 改为 `cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true`。

### P1-4: auto_decompose prompt 引用路径错误
- **位置**: `scripts/hyper-loop.sh` L692-693
- **现象**: `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md` 应为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。Claude 可能找不到文件，降级生成通用任务。
- **修复**: 修正两个路径加 `/context/`。
