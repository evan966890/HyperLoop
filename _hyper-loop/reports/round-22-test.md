# Round 22 试用报告

测试对象: `scripts/hyper-loop.sh` (git HEAD: 67e82df, 987 行)
测试时间: 2026-03-30
测试方法: `bash -n` 语法检查 + BDD 场景静态分析 + Python 逻辑单元测试

---

## P0 Bug 列表

### P0-1: 工作副本被覆盖，脚本不可运行
- **文件**: `scripts/hyper-loop.sh`
- **现象**: 工作副本内容为 `Script started on Mon Mar 30 07:00:32 2026`（43 字节），git 提交版本为 987 行完整脚本
- **原因**: Unix `script` 命令意外以该文件为输出目标，覆盖了全部内容
- **影响**: BUILD_CMD (`bash -n scripts/hyper-loop.sh`) 测的是被破坏的工作副本。虽然 `bash -n` 在 1 行文件上仍然通过（语法合法），但脚本完全不可执行
- **截图**: `screenshots/round-22/S000-syntax-check.txt`

### P0-2: Tester/Reviewer 初始化文件路径错误
- **代码**: 行 384 引用 `TESTER_INIT.md`，行 460 引用 `REVIEWER_INIT.md`
- **路径**: `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md` (不存在)
- **实际文件**: `${PROJECT_ROOT}/_hyper-loop/context/agents/tester.md` 和 `reviewer.md`
- **影响**: `start_agent` 注入的初始化指令引用不存在的文件，Tester/Reviewer 无法获得角色定义
- **截图**: `screenshots/round-22/S002-path-bugs.txt`

---

## P1 Bug 列表

### P1-1: auto_decompose 引用错误的 BDD/contract 路径
- **代码**: 行 719 `_hyper-loop/bdd-specs.md`，行 720 `_hyper-loop/contract.md`
- **正确路径**: `_hyper-loop/context/bdd-specs.md`，`_hyper-loop/context/contract.md`
- **影响**: 自动拆解的 prompt 中 Claude 找不到 BDD 规格和评估契约
- **截图**: `screenshots/round-22/S002-path-bugs.txt`

### P1-2: archive_round 复制 bdd-specs.md 路径错误
- **代码**: 行 797 `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"`
- **正确路径**: `_hyper-loop/context/bdd-specs.md`
- **影响**: 归档不含 BDD 规格（有 `|| true` 不崩溃）

### P1-3: S013 回退逻辑失效 — BEST_ROUND 仅在 ACCEPTED 时更新
- **代码**: 行 908 `BEST_ROUND=$ROUND` 仅在 ACCEPTED 分支内
- **现象**: 若所有轮次均 REJECTED（如当前 21 轮），`BEST_ROUND=0`，回退条件 `[[ "$BEST_ROUND" -gt 0 ]]` 永不满足
- **BDD S013 要求**: 回退到得分最高的轮次（不限 ACCEPTED）
- **截图**: `screenshots/round-22/S013-rollback-bug.txt`

### P1-4: cmd_status 重复定义
- **代码**: 行 697 和行 957 各定义了一次 `cmd_status()`
- **影响**: 第二个定义覆盖第一个，第一个版本的逻辑丢失

---

## BDD 场景逐条验证

| ID | 场景 | 结果 | 说明 |
|----|------|------|------|
| S001 | loop 命令启动死循环 | **PASS** | `cmd_loop` 输出 "LOOP: Round N/M"（行 860），循环结构正确，results.tsv 追加记录 |
| S002 | auto_decompose 生成任务文件 | **FAIL** | 功能实现完整（降级生成 task1.md OK），但 prompt 中 bdd-specs.md 和 contract.md 路径错误（P1-1） |
| S003 | Writer worktree 创建 + trust + 启动 | **PASS** | worktree add（行 124）、config.toml trust（行 130-131）、_ctx 复制（行 136）均正确 |
| S004 | Writer 完成后 diff 被正确 commit | **PASS** | git add -A + commit（行 338-339）、squash merge（行 348）、.patch/.stat 生成（行 342-345）均正确 |
| S005 | diff 审计拦截越界修改 | **PASS** | audit_writer_diff 检测越界返回 1（行 291），被合并跳过（行 328） |
| S006 | Writer 超时处理 | **PASS** | 超时写 `{"status":"timeout"}`（行 224），标记 failed |
| S007 | Tester 启动并生成报告 | **FAIL** | 功能逻辑正确（启动、等待、超时降级），但 TESTER_INIT.md 路径错误（P0-2），Tester 无角色定义 |
| S008 | 3 Reviewer 启动并产出评分 | **FAIL** | 3 个 Reviewer 启动逻辑正确（gemini/claude/codex），JSON 提取降级正确，但 REVIEWER_INIT.md 路径错误（P0-2） |
| S009 | 和议计算正确 | **PASS** | Python 中位数计算验证通过：[5,6,7]→6.0，ACCEPTED when > prev_median |
| S010 | 一票否决（score < 4.0） | **PASS** | [3.5,6,7] 正确触发 REJECTED_VETO |
| S011 | Tester P0 否决 | **PASS** | "P0" + "fail" 正确检测 tester_p0=True → REJECTED_TESTER_P0 |
| S012 | verdict.env 安全读取 | **PASS** | 全部使用 grep + cut 读取（行 621-623, 675-676, 897-898），不 source |
| S013 | 连续 5 轮失败自动回退 | **FAIL** | 回退条件 `BEST_ROUND > 0` 在全 REJECTED 场景下永不满足（P1-3） |
| S014 | STOP 文件优雅退出 | **PASS** | 检测 STOP → rm → break（行 852-855） |
| S015 | worktree 清理 | **PASS** | subshell + set+e 保护（行 594），worktree remove + branch -D |
| S016 | macOS timeout 兼容 | **PASS** | gtimeout 检查 + 纯 bash fallback（行 17-21） |
| S017 | 多 Writer 同文件冲突处理 | **PASS** | merge --abort + "conflict, deferred"（行 353-354），脚本不崩溃 |

---

## 统计

- **语法检查 (bash -n)**: PASS（git 提交版本）/ N/A（工作副本被破坏）
- **BDD 通过**: 13/17 (76.5%)
- **BDD 失败**: 4/17 (S002, S007, S008, S013)
- **P0 Bug**: 2
- **P1 Bug**: 4

---

## 评分建议（供 Reviewer 参考）

- 客观指标（80%）: bash -n 通过 + BDD 76.5% ≈ 6.1/8.0
- 主观维度（20%）: 代码结构清晰、错误处理有 subshell 保护、Python 逻辑正确 ≈ 1.2/2.0
- **综合估计: ~7.3/10**（未达 7.5 阈值）
- 阻断因素: P0-1（脚本不可运行）和 P0-2（Agent 初始化失败）使实际运行不可能

HYPERLOOP_TEST_DONE
