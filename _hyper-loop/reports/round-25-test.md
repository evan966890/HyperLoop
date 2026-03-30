# Round 25 试用报告

## 测试环境
- 测试对象：`scripts/hyper-loop.sh` (git HEAD, 987 行)
- 测试方法：代码审查 + bash -n 语法检查
- 注意：**工作副本已损坏**（仅 1 行，被 `script` 命令覆盖），以下所有验证基于 git HEAD 版本

## bash -n 语法检查
**PASS** — committed 版本语法正确

---

## BDD 场景验证

| 场景 | 描述 | 结果 | 截图 |
|------|------|------|------|
| S001 | loop 命令启动死循环 | **PASS** | screenshots/round-25/S001-loop-cmd.txt |
| S002 | auto_decompose 生成任务文件 | **FAIL** | screenshots/round-25/S002-decompose.txt |
| S003 | Writer worktree 创建 + trust + 启动 | **PASS** | screenshots/round-25/S003-writer-worktree.txt |
| S004 | Writer 完成后 diff 被正确 commit | **PASS** | screenshots/round-25/S004-merge.txt |
| S005 | diff 审计拦截越界修改 | **PASS** | screenshots/round-25/S005-audit.txt |
| S006 | Writer 超时处理 | **PASS** | screenshots/round-25/S006-timeout.txt |
| S007 | Tester 启动并生成报告 | **FAIL** | screenshots/round-25/S007-tester.txt |
| S008 | 3 Reviewer 启动并产出评分 | **FAIL** | screenshots/round-25/S008-reviewers.txt |
| S009 | 和议计算正确 | **PASS** | screenshots/round-25/S009-verdict.txt |
| S010 | 一票否决 (score < 4.0) | **PASS** | screenshots/round-25/S010-veto.txt |
| S011 | Tester P0 否决 | **PASS** | screenshots/round-25/S011-tester-p0.txt |
| S012 | verdict.env 安全读取 | **PASS** | screenshots/round-25/S012-safe-read.txt |
| S013 | 连续 5 轮失败自动回退 | **PASS** | screenshots/round-25/S013-rollback.txt |
| S014 | STOP 文件优雅退出 | **PASS** | screenshots/round-25/S014-stop.txt |
| S015 | worktree 清理 | **PASS** | screenshots/round-25/S015-cleanup.txt |
| S016 | macOS timeout 兼容 | **PASS** | screenshots/round-25/S016-timeout-compat.txt |
| S017 | 多 Writer 同文件冲突处理 | **PASS** | screenshots/round-25/S017-conflict.txt |

**通过率: 14/17 (82.4%)**

---

## Bug 列表

### P0 — 阻断性问题

#### P0-1: 工作副本被 `script` 命令覆盖
- **位置**: `scripts/hyper-loop.sh` 工作副本
- **现象**: 文件仅含 `Script started on Mon Mar 30 07:00:32 2026`（1 行），987 行脚本丢失
- **影响**: `BUILD_CMD="bash -n scripts/hyper-loop.sh"` 对 1 行文本假通过，掩盖所有实际问题。这是 24 轮连续 0.0 分的根本原因——构建检查形同虚设
- **修复**: `git checkout HEAD -- scripts/hyper-loop.sh`

#### P0-2: TESTER_INIT.md / REVIEWER_INIT.md 路径错误
- **位置**: Line 384, Line 460
- **现象**: 脚本引用 `_hyper-loop/context/TESTER_INIT.md` 和 `_hyper-loop/context/REVIEWER_INIT.md`，但实际文件在 `_hyper-loop/context/templates/` 子目录下
- **影响**: Tester 和 Reviewer 启动时 start_agent 的 INIT 参数指向不存在的文件，Agent 无法获取角色定义和评估指令。这直接导致评分质量低劣
- **修复**: 改为 `_hyper-loop/context/templates/TESTER_INIT.md` 和 `_hyper-loop/context/templates/REVIEWER_INIT.md`

#### P0-3: auto_decompose prompt 引用错误路径
- **位置**: Line 719, Line 720
- **现象**: `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md` 不存在，正确路径为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`
- **影响**: Claude 拆解 prompt 缺少 BDD 规格和评估契约，任务拆解与评估标准脱节
- **修复**: 加 `context/` 路径段

### P1 — 功能缺陷

#### P1-1: cmd_status 重复定义
- **位置**: Line 697 和 Line 957
- **现象**: 两次定义 `cmd_status()`，第二次覆盖第一次。Line 697 的简版成为死代码
- **影响**: 无功能影响（第二版更完善），但增加维护困惑
- **修复**: 删除 Line 697 的第一个定义

#### P1-2: auto_decompose heredoc 变量转义错误
- **位置**: Line 731
- **现象**: `\$f` 在 `$(...)` 命令替换内产生字面量 `$f` 而非 for 循环变量值
- **影响**: "上一轮评分" 段落显示 `$f: $f` 而非实际文件名和分数内容
- **修复**: 将 heredoc 定界符改为 `<<'DPROMPT'`（引号禁止展开），或将评分读取逻辑移到 heredoc 外

#### P1-3: archive_round 路径错误
- **位置**: Line 797
- **现象**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` — 文件不存在
- **影响**: 归档不包含 bdd-specs.md 副本，但 cp 有 `|| true` 不会崩溃
- **修复**: 改为 `_hyper-loop/context/bdd-specs.md`

#### P1-4: Tester 超时注释不一致
- **位置**: Line 421
- **现象**: 注释说 "10 分钟" 但代码用 900s = 15 分钟
- **影响**: 无功能影响，但误导维护者
- **修复**: 注释改为 "15 分钟"

---

## 评分建议

### 客观指标 (80%)
- bash -n 语法检查: **PASS** (committed version)
- BDD 通过率: **14/17 = 82.4%**
- 客观得分: 0.8 × (0.5 × 10 + 0.5 × 8.24) ≈ **7.3**

### 主观维度 (20%, 上限 7.0)
- 代码可读性: **6.5/7.0** — 结构清晰，函数命名好，注释充分。cmd_status 重复和 heredoc 变量问题略扣
- 错误处理完整性: **5.5/7.0** — 有 set +e subshell、|| true、降级逻辑，但 INIT 路径错误和工作副本损坏是严重疏忽
- 主观得分: 0.2 × 6.0 = **1.2**

### 综合: 约 **5.5**

P0 bug 仍存在 3 个，其中 P0-1（工作副本损坏）和 P0-2（INIT 路径错误）直接导致循环无法正常产出有效评分。在这些 P0 修复之前，脚本无法达到"无人值守跑 50 轮不崩溃"的目标。
