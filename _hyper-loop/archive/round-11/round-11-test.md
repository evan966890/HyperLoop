# Round 11 — Tester BDD 验证报告

## 语法检查

`bash -n scripts/hyper-loop.sh` — **PASS** (无语法错误)

## R11 变更摘要

4 个 task 提交：
1. **task1** (+11/-4): `build_app` 用子 shell 隔离 `cd`，`cmd_round` 补充 `archive_round` 调用，`merge_writers` commit 加 `|| true` 容错
2. **task2** (+2): `audit_writer_diff` 增加 untracked 文件检测（`git ls-files --others`）
3. **task3** (-41): 删除已废弃的 `start_agent`/`kill_agent` 函数（Writer 已改为 `codex exec` 后台模式）
4. **task4** (+5/-4): BDD 规格更新（tmux → 非交互模式描述，Reviewer fallback 说明）

---

## BDD 场景逐条验证

| ID | 结果 | 原因 |
|----|------|------|
| S001 | **PASS** | `cmd_loop` 接收 MAX_ROUNDS 参数，循环输出 "Round X/N"，`record_result` 每轮写 results.tsv |
| S002 | **PASS** | `auto_decompose` 调用 `claude -p` 拆解，失败时降级生成含"修复任务"和"相关文件"的 task1.md |
| S003 | **PASS** | `start_writers` 创建 worktree、trust config.toml、复制 `_ctx/`、后台 `codex exec` 启动 |
| S004 | **FAIL** | merge 流程本身正确（元数据清理→commit→squash），但 `audit_writer_diff` 会因 `_writer_prompt.md` 被误判越界而拒绝合并（**见 P0-1**） |
| S005 | **PASS** | `audit_writer_diff` 提取 ALLOWED_FILES、比对实际修改、返回非零码时跳过合并 |
| S006 | **PASS** | `wait_writers` 900s 超时后杀进程、写 timeout DONE.json、status!=done 时跳过 |
| S007 | **PASS** | `run_tester` 用 `claude -p` 管道模式 + `timeout 600`，无输出时生成默认报告 |
| S008 | **PASS** | 3 个 Reviewer 并行子进程（gemini/claude/codex），Python 管道提取 JSON，fallback 中立分 5 |
| S009 | **PASS** | Python 中位数计算正确，median > prev_median → ACCEPTED，verdict.env 用 grep 安全读取 |
| S010 | **PASS** | `any(s < 4.0)` → REJECTED_VETO，`record_result` 写入 results.tsv |
| S011 | **PASS*** | tester_p0 判定逻辑存在但阈值与 BDD 描述不一致（**见 P1-1**） |
| S012 | **PASS** | verdict.env 全部用 grep+cut 读取（record_result/cmd_round/cmd_loop），不再 source |
| S013 | **PASS*** | 5 轮失败回退逻辑正确，但 BEST_ROUND 不从历史初始化（**见 P1-2**） |
| S014 | **PASS** | STOP 文件在循环顶部检查，删除后 break，exit 0 |
| S015 | **PASS** | `cleanup_round` 删除 worktree + 分支 + worktree 父目录 |
| S016 | **PASS** | 脚本顶部检测 gtimeout，无则用纯 bash sleep+kill fallback |
| S017 | **PASS** | 元数据预删除防止假冲突，真冲突 `merge --abort` 并标记 deferred，脚本不崩溃 |

**统计**: 16 PASS / 1 FAIL（S004 因 P0-1 导致）

---

## P0 Bugs

### P0-1: `_writer_prompt.md` 未加入 `audit_writer_diff` 白名单（R11 回归）

**位置**: `scripts/hyper-loop.sh:319-321`（`audit_writer_diff` 的 case 语句）

**原因**: R11 task2 增加了 untracked 文件检测（`git ls-files --others --exclude-standard`），但 case 白名单只有：
```
DONE.json|WRITER_INIT.md|_ctx/*|TASK.md
```
遗漏了 `_writer_prompt.md`。该文件由 `start_writers`（line 178-219）为每个 Writer 自动生成，是 untracked 文件。

**影响**: 每个 Writer worktree 都包含脚本生成的 `_writer_prompt.md`，审计时被判定为越界修改 → **所有 Writer 产出被拒绝合并** → 整个 round 产出为零。这是一个阻塞性回归。

**修复**: case 语句加入 `_writer_prompt.md`：
```bash
case "$changed" in
  DONE.json|WRITER_INIT.md|TASK.md|_writer_prompt.md|_ctx/*) FOUND=true ;;
esac
```

---

## P1 Bugs

### P1-1: S011 Tester P0 否决阈值与 BDD 规格不一致

**位置**: `scripts/hyper-loop.sh:587-592`（`compute_verdict` Python 代码）

**原因**: BDD S011 规定"报告包含 P0 和 fail → REJECTED_TESTER_P0"，但实现要求：
- `len(p0_bugs) >= 2`（需 2+ 个 `### P0` heading）
- 或 `len(p0_bugs) >= 1 and len(bdd_fails) > 3`（1 个 P0 + >3 BDD FAIL）

单个 P0 bug + 3 个以下 BDD fail 不会触发否决。

**影响**: 低频但严重——单个致命 P0 bug 可能不触发自动否决，需要人工介入。

**建议**: 要么降低阈值（1 个 P0 即否决），要么更新 BDD S011 规格匹配实际行为。

### P1-2: S013 `BEST_ROUND` 不从历史结果初始化

**位置**: `scripts/hyper-loop.sh:1056-1058`（`cmd_loop` 初始化）

**原因**: `BEST_ROUND=0, BEST_MEDIAN=0` 硬编码初始值。`cmd_loop` 重启后不读取 `results.tsv` 或 `archive/` 中的历史最佳轮次。`BEST_ROUND` 仅在当前 session 中有 ACCEPTED 轮次时才更新。

**影响**: 重启 loop 后，如果连续 5 轮失败，因 `BEST_ROUND=0` 条件 `BEST_ROUND > 0` 不满足，不会回退到历史最佳状态。

**建议**: 启动时从 `results.tsv` 扫描 ACCEPTED 轮次中 median 最高的作为初始 `BEST_ROUND`/`BEST_MEDIAN`：
```bash
if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
  while IFS=$'\t' read -r r med _ dec; do
    if [[ "$dec" == ACCEPTED* ]] && python3 -c "exit(0 if float('${med}') > float('${BEST_MEDIAN}') else 1)" 2>/dev/null; then
      BEST_ROUND=$r; BEST_MEDIAN=$med
    fi
  done < "${PROJECT_ROOT}/_hyper-loop/results.tsv"
fi
```
