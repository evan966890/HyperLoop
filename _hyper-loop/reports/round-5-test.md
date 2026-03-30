# Round 5 — Tester Report

**测试时间**: 2026-03-30
**测试对象**: scripts/hyper-loop.sh (v5.3)
**语法检查**: `bash -n` PASS

---

## BDD 场景逐条检查

| ID | 结果 | 原因 |
|----|------|------|
| S001 | PASS | `cmd_loop` (L798) 接受 MAX_ROUNDS 参数，while 循环正确退出，`record_result` 每轮写 results.tsv |
| S002 | PASS | `auto_decompose` (L679) 用 Claude -p 拆解，fallback (L740-758) 生成默认 task1.md 含"修复任务"和"相关文件"段落 |
| S003 | PASS | `start_writers` (L101) 创建 worktree (L124)、trust codex config (L130-132)、复制 _ctx/ (L136)、tmux 启动 codex (L179-182) |
| S004 | **FAIL** | `merge_writers` (L299) 的 echo 日志污染 stdout。`INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获全部输出（含"合并 Writer 产出..."等日志），`build_app` 收到多行字符串导致 `cd` 失败。squash merge 和 patch 生成逻辑本身正确 |
| S005 | PASS | `audit_writer_diff` (L242) 检查越界文件返回 1 (L291)，merge_writers 据此跳过 (L327-330) |
| S006 | **FAIL** | 超时默认 300s (L198) 但 BDD 规格要求 15 分钟 (900s)。`wait_writers` 调用处 (L626, L851) 均未传超时参数，始终用默认值 |
| S007 | PASS | `run_tester` (L379) 用 `timeout 600 claude -p -` 非交互执行，超时或空输出时生成 fallback 报告 (L411-413) |
| S008 | PASS | `run_reviewers` (L417) 并行跑 3 个 reviewer (gemini/claude/codex)，JSON 通过 python 提取器保证含 score 字段，fallback 分 5 (L477-482) |
| S009 | PASS | `compute_verdict` (L486) python 中位数计算正确 (L519)，ACCEPTED 判定逻辑 (L538) 正确，verdict.env 用安全 grep 读取 |
| S010 | PASS | `veto = any(s < 4.0 for s in scores)` (L523) 正确触发 REJECTED_VETO (L531-532) |
| S011 | PASS | Tester P0 检测 (L525-529) 同时检查 "P0" 和 ("bug" or "fail")，REJECTED_TESTER_P0 (L533-534) |
| S012 | PASS | verdict.env 用 `grep + cut` 读取 (L593-596, L648-649, L872-873)，不 source，无 "command not found" 风险 |
| S013 | PASS | 连续 5 轮失败检测 (L897)，BEST_ROUND 追踪最高中位数 (L882-885)，回退 checkout (L903) 并重置计数器 (L906) |
| S014 | PASS | STOP 文件检查 (L827)，删除后 break (L829-830)，正常退出 |
| S015 | **FAIL** | `cleanup_round` (L563) 移除各 worktree 和分支，但未删除父目录 `/tmp/hyper-loop-worktrees-rN/`，该空目录会残留 |
| S016 | PASS | macOS 兼容 (L17-21)：优先 gtimeout，fallback 用 shell 内置 sleep+kill 模拟 |
| S017 | PASS | merge conflict 时 `git merge --abort` (L353) 后 log "conflict, deferred"，脚本继续不崩溃 |

---

## 统计
- **PASS**: 14/17
- **FAIL**: 3/17 (S004, S006, S015)

---

## P0 Bug

### P0-001: merge_writers stdout 污染导致 build_app 必然失败
- **位置**: L299-360 (`merge_writers`) + L629/L854 (调用处)
- **问题**: `merge_writers` 将日志 echo 和路径 echo 都写到 stdout。`INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获全部输出，导致 `build_app "$INTEGRATION_WT"` 执行 `cd` 时收到多行字符串（首行是"合并 Writer 产出..."而非路径），必然失败。
- **影响**: 每一轮 build 阶段都会失败，整个循环无法正常运行
- **修复**: merge_writers 的日志 echo 改为 `>&2` 输出到 stderr，仅 `echo "$INTEGRATION_WT"` 保留在 stdout

---

## P1 Bug

### P1-001: Writer 超时值与 BDD 规格不符
- **位置**: L198 `local TIMEOUT="${2:-300}"`
- **问题**: BDD S006 要求 15 分钟 (900s)，代码默认 300s (5min)。调用处 (L626, L851) 未传参覆盖。
- **修复**: 改为 `${2:-900}` 或在调用处显式传参

### P1-002: worktree 父目录未清理
- **位置**: L563-583 (`cleanup_round`)
- **问题**: 移除各 worktree 后，`/tmp/hyper-loop-worktrees-rN/` 空目录残留
- **修复**: cleanup 末尾加 `rmdir "${WORKTREE_BASE}" 2>/dev/null || true`

### P1-003: PREV_MEDIAN 空值导致 python 崩溃
- **位置**: L846-848
- **问题**: `tail -1 results.tsv | cut -f2 || echo 0` — 若 results.tsv 存在但为空，cut 返回空字符串（exit 0），`|| echo 0` 不触发。空字符串传入 compute_verdict 的 python `float('')` 引发 ValueError。
- **修复**: 改为 `PREV_MEDIAN=$(tail -1 ... | cut -f2); PREV_MEDIAN="${PREV_MEDIAN:-0}"`

### P1-004: archive_round 引用错误路径
- **位置**: L770
- **问题**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 但实际路径是 `_hyper-loop/context/bdd-specs.md`，复制静默失败
- **修复**: 加上 `context/` 路径段

### P1-005: cmd_status 重复定义
- **位置**: L670 和 L932
- **问题**: 两个 `cmd_status` 函数，后者覆盖前者。前者是简化版，后者含"最佳轮次"。死代码增加维护负担
- **修复**: 删除 L670-676 的旧版

### P1-006: fallback 分数注释不一致
- **位置**: L476 注释 "fallback 给 3 分" vs L479 实际代码给 5 分
- **问题**: 注释误导，代码实际写 `"score":5`
- **修复**: 注释改为"fallback 给 5 分"
