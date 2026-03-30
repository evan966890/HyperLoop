# Round 2 — BDD 场景测试报告

语法检查: `bash -n scripts/hyper-loop.sh` — **PASS** (无错误)

## 逐场景结果

| ID | 结果 | 原因 |
|------|------|------|
| S001 | PASS | `cmd_loop` (L798) 接收 MAX_ROUNDS 参数，循环跑满后正常退出，`record_result` 每轮写 results.tsv |
| S002 | **FAIL** | `auto_decompose` (L693-694) 引用路径 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，实际路径是 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。Claude 无法读取正确的 BDD 规格，任务拆解质量严重下降。降级 fallback 机制 (L741) 存在且正确 |
| S003 | PASS | `start_writers` (L101): `git worktree add` 创建 worktree (L124)，`~/.codex/config.toml` trust 配置 (L130-133)，Codex 在 tmux window 启动 (L179-182)，`_ctx/` 目录复制 (L136) |
| S004 | PASS | `merge_writers` (L299): `git add -A && git commit` (L338-339) 确保 Writer 改动被 commit，squash merge 到 integration 分支 (L348)，patch/stat 文件生成 (L342-345) |
| S005 | PASS | `audit_writer_diff` (L242): 提取 TASK.md 允许文件列表 (L248)，对比实际修改文件 (L258)，越界返回非零 (L291)，merge_writers 中跳过合并 (L327-330) |
| S006 | PASS | `wait_writers` (L196): 超时写 `{"status":"timeout"}` (L224)，merge_writers 中 status!=done 跳过 (L320-323)。注：默认超时 300s (5 分钟)，BDD 写 15 分钟 |
| S007 | PASS | `run_tester` (L379): Claude 管道模式 `-p` (L404)，timeout 600s，超时生成空报告 (L411-413) 而非崩溃 |
| S008 | **FAIL** | `run_reviewers` (L417): 3 个 Reviewer 用后台子进程 `()&` 运行 (L454-471)，**不在 tmux 中启动** (与 BDD 不符，但为 v5.4 设计变更)。**P1 Bug**: fallback JSON 写 `"score":5` (L479) 但日志输出 `"fallback to score 3"` (L480)，分数与日志矛盾 |
| S009 | PASS | `compute_verdict` (L486): Python 排序后取中位数 (L519)，ACCEPTED 判断 median > prev_median (L538)，verdict.env 用 key=value 格式安全写入 (L550-556) |
| S010 | PASS | Python 逻辑 `any(s < 4.0 for s in scores)` (L523) → `REJECTED_VETO` (L531)，经 `record_result` 写入 results.tsv |
| S011 | PASS | Python 检查报告中同时含 "P0" 和 ("bug"/"fail") (L528-529) → `REJECTED_TESTER_P0` (L533) |
| S012 | PASS | `record_result` (L586) 用 `grep + cut` 读 verdict.env (L594-596)，`cmd_loop` 中同样用 grep (L872-873)，不 source，不会出 "command not found" |
| S013 | PASS | `cmd_loop` (L897): `CONSECUTIVE_REJECTS >= 5 && BEST_ROUND > 0` 时读 archive git-sha.txt，`git checkout` 回退，`CONSECUTIVE_REJECTS` 重置为 0 (L906) |
| S014 | PASS | STOP 检查在 init_dirs 之前 (L827)，当前轮不执行，`rm "$STOP_FILE"` (L829) 后 break 正常退出 |
| S015 | PASS | `cleanup_round` (L563): subshell+set+e 容错，`git worktree remove --force` (L577) 删目录，`git branch -D` (L578) 删分支，tmux kill-window (L570) 关窗口 |
| S016 | PASS | L17-21: 优先用 `gtimeout`，其次检查系统 `timeout`，最后用纯 bash `sleep+kill` polyfill |
| S017 | PASS | `merge_writers` (L348-356): squash merge 失败时 `merge --abort` (L353)，标记 "conflict, deferred" (L354)，FAILED 计数器递增，脚本继续不崩溃 |

## 汇总

- **PASS: 15/17**
- **FAIL: 2/17** (S002, S008)

---

## P0 Bug

### BUG-P0-1: auto_decompose 中 BDD/contract 路径错误 (S002)

- **位置**: `scripts/hyper-loop.sh:693-694`
- **现象**: decompose prompt 给 Claude 的文件路径是:
  - `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` (不存在)
  - `${PROJECT_ROOT}/_hyper-loop/contract.md` (不存在)
- **正确路径**:
  - `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
  - `${PROJECT_ROOT}/_hyper-loop/context/contract.md`
- **影响**: Claude 无法读取 BDD 规格和评估契约，任务拆解质量严重退化，整个 loop 的改进方向可能错误
- **修复**: 在路径中加入 `context/` 子目录

## P1 Bug

### BUG-P1-1: Reviewer fallback 分数与日志不一致 (S008)

- **位置**: `scripts/hyper-loop.sh:479-480`
- **现象**: fallback JSON 写入 `"score":5`，但下一行 echo 输出 `"fallback to score 3"`
- **影响**: 运维人员看日志以为 fallback 是 3 分，实际是 5 分，调试时造成困惑
- **修复**: 统一为 `"fallback to score 5"` 或改 JSON 为 `"score":3`（取决于设计意图）

### BUG-P1-2: archive_round 中 bdd-specs.md 路径错误

- **位置**: `scripts/hyper-loop.sh:770`
- **现象**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 路径缺少 `context/`
- **影响**: 归档时 BDD 规格文件不会被复制（因 `|| true` 静默失败），archive 不完整
- **修复**: 改为 `_hyper-loop/context/bdd-specs.md`

### BUG-P1-3: cmd_status 函数重复定义

- **位置**: `scripts/hyper-loop.sh:670` 和 `scripts/hyper-loop.sh:932`
- **现象**: 两处定义 `cmd_status()`，第二个覆盖第一个，第一个成为死代码
- **影响**: 无功能性影响（第二个版本功能更全），但增加维护混乱
- **修复**: 删除 L670-676 的第一个定义
