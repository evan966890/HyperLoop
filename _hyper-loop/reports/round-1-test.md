# Round 1 — Tester 报告

## 语法检查

```
bash -n scripts/hyper-loop.sh → PASS (无语法错误)
```

## BDD 场景逐条验证

| ID | 结果 | 原因 |
|----|------|------|
| S001 | **PASS** | `cmd_loop` (L798) 接受 MAX_ROUNDS 参数，while 循环跑到上限后退出，`record_result` 每轮追加 results.tsv |
| S002 | **FAIL** | `auto_decompose()` L693-694 引用路径错误：`_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，实际路径是 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。Claude 拿到错误路径会导致拆解失败。fallback 逻辑 (L740-758) 正确。 |
| S003 | **PASS** | `start_writers()` L124 创建 worktree，L129-133 写入 `~/.codex/config.toml` trust，L179-191 在 tmux 启动 Codex，L136 复制 `_ctx/` |
| S004 | **PASS** | `merge_writers()` L337-339 执行 `git add -A && git commit`，L348 squash merge 到 integration 分支，L342-345 生成 patch/stat 文件 |
| S005 | **PASS** | `audit_writer_diff()` L242-296 检查越界文件，L291 越界时 return 1，L327-330 拒绝合并 |
| S006 | **PASS** | `wait_writers()` L221-226 超时后写入 `{"status":"timeout"}` 到 DONE.json，merge_writers L320 跳过非 done 状态。注：默认超时 300s(5min) 与 BDD 的 15min 有偏差，但属于参数调整 |
| S007 | **PASS** | `run_tester()` L379-413 用 `claude -p -` 非交互模式运行（v5.4 从 tmux 改为管道模式），timeout 600s，空输出时 L411-413 生成默认报告 |
| S008 | **FAIL** | `run_reviewers()` L477-482 fallback 逻辑矛盾：L479 实际写入 `"score":5` 但 L480 日志输出 "fallback to score 3"，误导排查。其余逻辑（3 并行 reviewer、JSON 提取）正确 |
| S009 | **PASS** | `compute_verdict()` L517-519 中位数计算正确，L538 `median > prev_median` 时 ACCEPTED，L550-556 verdict.env 写入完整 |
| S010 | **PASS** | L523 `any(s < 4.0 for s in scores)` 触发否决，L531-532 DECISION=REJECTED_VETO |
| S011 | **PASS** | L525-529 检查报告中 "P0" + ("bug" or "fail")，L533-534 DECISION=REJECTED_TESTER_P0 |
| S012 | **PASS** | L593-596, L648-649, L872-873 均用 `grep + cut` 提取值，不 source verdict.env，不会出现 "command not found" |
| S013 | **PASS** (部分) | L897-907 检查 CONSECUTIVE_REJECTS >= 5 且 BEST_ROUND > 0，读取 git-sha.txt 回退。但 BEST_ROUND/BEST_MEDIAN (L822-823) 未从 results.tsv 初始化——若脚本重启则丢失最佳轮次记忆 |
| S014 | **PASS** | L827-830 检测 STOP 文件，删除后 break，当前轮不执行，脚本正常退出 exit 0 |
| S015 | **PASS** | `cleanup_round()` L577 `git worktree remove --force`，L578 `git branch -D`，L569-571 关闭 tmux windows |
| S016 | **PASS** | L17-21 检测 gtimeout → timeout → 自定义 fallback 函数 |
| S017 | **PASS** | `merge_writers()` L348-356 merge 失败时 `merge --abort` + 标记 deferred，脚本不崩溃 |

## 统计

- **PASS**: 15/17
- **FAIL**: 2/17 (S002, S008)

---

## P0 Bug

### P0-1: `auto_decompose()` 引用了错误的文件路径

- **位置**: `scripts/hyper-loop.sh` L693-694
- **现象**: decompose prompt 中 bdd-specs.md 和 contract.md 路径缺少 `context/` 目录
- **影响**: Claude 拿到不存在的路径，任务拆解大概率失败，只能靠 fallback 生成一个泛化 task1.md，导致 Writer 质量下降
- **修复**: `_hyper-loop/bdd-specs.md` → `_hyper-loop/context/bdd-specs.md`，`_hyper-loop/contract.md` → `_hyper-loop/context/contract.md`

## P1 Bug

### P1-1: Reviewer fallback 分数与日志不一致

- **位置**: `scripts/hyper-loop.sh` L479-480
- **现象**: fallback JSON 写入 `"score":5`，但日志打印 "fallback to score 3"
- **影响**: 排查评分问题时日志误导，以为 fallback 给了 3 分实际是 5 分
- **修复**: 统一为同一个值（建议保持 score 5，修改日志文本）

### P1-2: `cmd_status()` 重复定义

- **位置**: `scripts/hyper-loop.sh` L670-676 和 L932-944
- **现象**: 同名函数定义两次，第二个覆盖第一个
- **影响**: 第一个定义是死代码，增加维护混乱
- **修复**: 删除 L670-676 的第一个定义

### P1-3: `BEST_ROUND` 未从历史数据初始化

- **位置**: `scripts/hyper-loop.sh` L822-823
- **现象**: `cmd_loop()` 每次启动时 BEST_ROUND=0, BEST_MEDIAN=0，不从 results.tsv 读取历史最佳
- **影响**: 脚本崩溃重启后，连续 5 轮失败的回退机制找不到可回退的目标（BEST_ROUND=0 导致跳过回退）
- **修复**: 启动时遍历 results.tsv + archive 目录，初始化 BEST_ROUND 和 BEST_MEDIAN

### P1-4: `archive_round()` 引用错误路径

- **位置**: `scripts/hyper-loop.sh` L770
- **现象**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 路径缺少 `context/`，cp 静默失败
- **影响**: 归档目录缺少 bdd-specs.md，无法完整回溯历史轮次的评判标准
- **修复**: `_hyper-loop/bdd-specs.md` → `_hyper-loop/context/bdd-specs.md`

### P1-5: `build_app()` 污染全局 CWD

- **位置**: `scripts/hyper-loop.sh` L367
- **现象**: `cd "$BUILD_DIR"` 改变主进程工作目录到 integration worktree
- **影响**: `cleanup_round()` 删除该 worktree 后，主进程 CWD 变成悬空目录，后续轮次若用相对路径会出错
- **修复**: 在 subshell 中运行 build，或在 build 后 `cd "$PROJECT_ROOT"`
