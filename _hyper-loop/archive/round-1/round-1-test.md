# Round 1 — Tester 报告

测试时间: 2026-03-30
脚本版本: HyperLoop v5.3
语法检查: `bash -n scripts/hyper-loop.sh` → **PASS** (无语法错误)

---

## BDD 场景逐条检查

| 场景 | 结果 | 原因 |
|------|------|------|
| S001 | **PASS** | `cmd_loop` (L798) 正确接收 MAX_ROUNDS 参数，while 循环条件 `ROUND <= MAX_ROUNDS` 正确，`record_result` 每轮写 results.tsv |
| S002 | **FAIL** | `auto_decompose` (L693-694) 中 BDD spec 路径写成 `_hyper-loop/bdd-specs.md`，实际位于 `_hyper-loop/context/bdd-specs.md`；contract.md 同理。Claude 拿到错误路径会找不到文件，降级 fallback 功能正常(L740-758) |
| S003 | **PASS** | `start_writers` (L101): worktree 创建(L124)、trust 写入 config.toml(L130-132)、Codex 在 tmux 启动(L182)、_ctx/ 复制(L136) 均正确 |
| S004 | **PASS** | `merge_writers` (L338-339) 先 `git add -A && git commit`，再 squash merge(L348)，patch/stat 文件生成(L342-345) 正确 |
| S005 | **PASS** | `audit_writer_diff` (L242) 检测越界文件返回 1(L292)，merge_writers 跳过该 Writer(L327-330) |
| S006 | **PASS** | `wait_writers` (L196) 超时后写 `{"status":"timeout"}` 到 DONE.json(L224)，merge_writers 检查 status!=done 跳过。注：BDD 要求 15min，实际 300s(5min)，设计变更 |
| S007 | **PASS** | `run_tester` (L379) 用 `timeout 600 claude -p -` 非交互模式，空输出时生成默认报告(L411-413)。注：BDD 要求 15min，实际 10min |
| S008 | **FAIL** | `run_reviewers` (L417): 3 个 Reviewer 并行启动(L454-471) + fallback(L477-482) 正确，但 reviewer-c(L468) 同时用 stdin pipe 和命令参数传入 prompt，`codex exec` 行为不确定。BDD 要求"从 pane 输出提取 JSON"未实现（v5.3 改为管道模式，不再有 pane） |
| S009 | **PASS** | `compute_verdict` (L486) Python 计算中位数(L518-519)正确，ACCEPTED 条件 `median > prev_median`(L538)，verdict.env 格式正确(L550-556) |
| S010 | **PASS** | Python `veto = any(s < 4.0 for s in scores)` (L523)，决策 REJECTED_VETO(L531-532)，record_result 记录到 results.tsv |
| S011 | **PASS** | Python 检查 `"P0" in text and ("bug"/"fail" in text.lower())` (L525-529)，决策 REJECTED_TESTER_P0(L533-534) |
| S012 | **PASS** | `record_result`(L586) 和 `cmd_loop`(L870-871) 均用 `grep + cut` 读取 verdict.env，不 source，不会触发 "command not found" |
| S013 | **PASS** | L895-905: `CONSECUTIVE_REJECTS >= 5 && BEST_ROUND > 0` 时读取 archive 中 git-sha.txt 并 checkout，重置计数器为 0 |
| S014 | **PASS** | L825-829: 检测 STOP 文件 → 删除 → break 退出循环 → 脚本正常结束(exit 0) |
| S015 | **PASS** | `cleanup_round` (L563): subshell+set+e 中删除 tmux windows(L569-571)、git worktree remove(L577)、branch -D(L578)。轻微: WORKTREE_BASE 空目录可能残留 |
| S016 | **PASS** | L17-21: 优先用 gtimeout，其次内置 timeout，最后 fallback 自定义函数。三级降级正确 |
| S017 | **PASS** | `merge_writers` (L348-356): squash merge 失败时执行 `merge --abort`(L353)，计数 FAILED++，脚本不崩溃 |

---

## 发现的 Bug

### P0 (阻塞性)

**P0-1: `auto_decompose` 中 BDD spec 和 contract 路径错误**
- 位置: `scripts/hyper-loop.sh` L693-694
- 现状: `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 和 `${PROJECT_ROOT}/_hyper-loop/contract.md`
- 正确: `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md` 和 `${PROJECT_ROOT}/_hyper-loop/context/contract.md`
- 影响: Claude 拿到错误路径 → 找不到核心规格文件 → 拆解质量严重下降，每轮都受影响
- 修复: 补上 `context/` 路径段

**P0-2: `build_app` 用 `cd` 改变全局工作目录**
- 位置: `scripts/hyper-loop.sh` L367 `cd "$BUILD_DIR"`
- 影响: build_app 后脚本 cwd 变为 integration worktree；cleanup_round 删除该 worktree 后 cwd 指向已删除目录；后续轮次依赖相对路径的操作将失败
- 修复: 改为 `(cd "$BUILD_DIR" && eval ...)` 用 subshell 隔离，或用 `pushd/popd`

### P1 (重要)

**P1-1: `cmd_status` 重复定义**
- 位置: L670-676 和 L930-942 各定义一次
- 影响: 第一个定义是死代码（被第二个覆盖），不影响运行但增加维护混乱
- 修复: 删除 L670-676 的第一个定义

**P1-2: `archive_round` 中 bdd-specs.md 路径错误**
- 位置: L770 `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"`
- 正确: `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
- 影响: 归档时 BDD spec 拷贝失败（被 `|| true` 吞掉），archive 不完整

**P1-3: reviewer-c 的 codex 命令双传 prompt**
- 位置: L468 `echo "$REVIEW_PROMPT" | timeout 300 codex exec -a never "$REVIEW_PROMPT"`
- 问题: prompt 同时通过 stdin pipe 和命令行参数传入；codex exec 的行为取决于它优先读哪个，可能导致 prompt 被截断或忽略
- 修复: 只用一种方式传入（推荐去掉 echo 管道，只用参数）

**P1-4: PREV_MEDIAN 在 results.tsv 为空文件时导致 Python 崩溃**
- 位置: L845 `PREV_MEDIAN=$(tail -1 ... | cut -f2 || echo 0)`
- 问题: `|| echo 0` 是死代码——cut 永远返回 0，空文件时 PREV_MEDIAN="" 而非 "0"；传给 Python 后 `float("")` 抛 ValueError，verdict.env 不会生成
- 修复: 改为 `PREV_MEDIAN=$(tail -1 ... 2>/dev/null | cut -f2)` + `PREV_MEDIAN="${PREV_MEDIAN:-0}"`

---

## 总结

- **通过: 15/17** 场景
- **失败: 2/17** (S002, S008)
- **P0 bug: 2 个** — 路径错误 + cd 污染 cwd
- **P1 bug: 4 个** — 重复定义、路径错误、双传 prompt、空值处理
