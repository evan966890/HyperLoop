# Round 13 试用报告

**测试日期**: 2026-03-30
**测试对象**: scripts/hyper-loop.sh (hyper-loop/r13-integration branch, 1025 lines)
**构建验证**: `bash -n` → syntax ok
**测试基准**: HEAD (987 lines) + task2 merge (CLI fallback for reviewers, +38 lines)
**未合并**: task1 (无 patch), task3, task4 (patches exist but not merged)

---

## BDD 场景逐条验证

| 场景 | 描述 | 结果 | 截图 |
|------|------|------|------|
| S001 | loop 命令启动死循环 | **PASS** | screenshots/round-13/S001-loop-cmd.txt |
| S002 | auto_decompose 生成任务文件 | **PASS** | screenshots/round-13/S002-decompose.txt |
| S003 | Writer worktree 创建 + trust + 启动 | **PASS** | screenshots/round-13/S003-worktree.txt |
| S004 | Writer 完成后 diff 被正确 commit | **PASS** | screenshots/round-13/S004-merge.txt |
| S005 | diff 审计拦截越界修改 | **PASS** | screenshots/round-13/S005-audit.txt |
| S006 | Writer 超时处理 | **PASS** | screenshots/round-13/S006-timeout.txt |
| S007 | Tester 启动并生成报告 | **PASS** | screenshots/round-13/S007-tester.txt |
| S008 | 3 Reviewer 启动并产出评分 | **FAIL** | screenshots/round-13/S008-reviewer.txt |
| S009 | 和议计算正确 | **PASS** | screenshots/round-13/S009-verdict.txt |
| S010 | 一票否决（score < 4.0） | **PASS** | screenshots/round-13/S010-veto.txt |
| S011 | Tester P0 否决 | **PASS** | screenshots/round-13/S011-tester-p0.txt |
| S012 | verdict.env 安全读取 | **PASS** | screenshots/round-13/S012-safe-read.txt |
| S013 | 连续 5 轮失败自动回退 | **PASS** | screenshots/round-13/S013-rollback.txt |
| S014 | STOP 文件优雅退出 | **PASS** | screenshots/round-13/S014-stop.txt |
| S015 | worktree 清理 | **PASS** | screenshots/round-13/S015-cleanup.txt |
| S016 | macOS timeout 兼容 | **PASS** | screenshots/round-13/S016-timeout-compat.txt |
| S017 | 多 Writer 同文件冲突处理 | **PASS** | screenshots/round-13/S017-conflict.txt |

**总计: 16/17 PASS, 1 FAIL**

---

## Bug 列表

### P0 Bug

1. **[P0] Reviewer 评审请求不含具体输出文件路径 — 12 轮全部 0.0 分的根因未修复**
   - **位置**: `run_reviewers()` line 450
   - **问题**: `"把 JSON 写入文件 ${SCORES_DIR}/你的角色名.json"` — 三个 Reviewer 收到相同的共用评审请求文件，指示它们写到"你的角色名.json"，但 Reviewer Agent 不知道自己叫 reviewer-a / reviewer-b / reviewer-c。
   - **影响**: Reviewer 无法写入正确文件 → 降级提取也失败 → 全部得 0.0 → REJECTED_VETO → 循环永远无法成功。
   - **证据**: 12 轮连续 REJECTED_VETO，所有 reviewer scores 均为 `{"score":0,"issues":[],"summary":"未能获取评分"}`。
   - **Round 13 task1 正确识别了此问题**，要求为每个 Reviewer 生成独立的评审请求文件，明确写出 `${SCORES_DIR}/reviewer-a.json` 等路径。但 task1 没有生成 patch，修复未落地。
   - **Round 13 task2 只添加了 CLI 降级逻辑**（当 gemini/claude/codex 不可用时 fallback），完全没触及评审请求文件路径问题。
   - **修复方案**: 将 `REVIEW_REQ` 改为 per-reviewer 生成，每个文件明确包含 `${SCORES_DIR}/reviewer-a.json`（或 b/c），替换"你的角色名"。

### P1 Bug

1. **[P1] auto_decompose 引用路径不一致**
   - **位置**: lines 757-758
   - **问题**: 引用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，而其他函数（start_agent, run_reviewers）引用 `_hyper-loop/context/bdd-specs.md`。当前两个位置都存在文件所以不影响运行，但维护时只更新一处会导致数据分歧。

2. **[P1] cmd_status 重复定义**
   - **位置**: lines 735 和 995
   - **问题**: 两个 `cmd_status()` 函数，第二个覆盖第一个。第一个成为死代码。不影响功能但代码不整洁。

3. **[P1] 工作区 scripts/hyper-loop.sh 被 `script` 命令覆盖**
   - **位置**: 工作目录中的 scripts/hyper-loop.sh 被覆盖为 1 行 `Script started on Mon Mar 30 04:15:42 2026`
   - **影响**: 环境问题，不影响 git HEAD 或 integration 分支的代码，但意味着后续轮次如果基于工作目录构建会失败。

---

## 详细分析

### 为什么 12 轮都是 0.0?

```
run_reviewers() 生成 1 个共用 REVIEW_REQ 文件
  → 文件说 "把 JSON 写入 ${SCORES_DIR}/你的角色名.json"
  → Reviewer Agent 不知道自己是 reviewer-a / b / c
  → 无法写出 reviewer-a.json / reviewer-b.json / reviewer-c.json
  → 等待超时
  → 降级从 pane 提取 → 找不到有效 JSON
  → 写入 {"score":0}
  → compute_verdict: median=0.0, veto=True (0.0 < 4.0)
  → REJECTED_VETO
  → 12 轮循环，问题从未被修复
```

### Round 13 做了什么?

- **task1** (P0 reviewer 路径修复): 正确诊断了根因，但 Writer 未能产出 patch
- **task2** (CLI fallback): 成功 merge，为 reviewer CLI 添加了降级逻辑——当某个 CLI 不存在时用可用的替代。这是有用的改进，但没有解决核心问题
- **task3, task4**: 有 patches 但未 merge 到 integration

### 对"50 轮无人值守不崩溃"目标的评估

脚本结构上是健壮的——不会崩溃，错误处理完整（set+e subshell, || true, 超时降级）。但由于 P0 bug，循环虽然不崩溃，却**永远无法产出有效评分**，形成"稳定但无用"的死循环。

---

## 评分建议

### 客观指标（80% 权重）
- `bash -n` 语法检查: **PASS**
- BDD 场景通过率: **16/17 = 94.1%** (S008 FAIL)

### 主观维度（20% 权重，上限 7.0）
- 代码可读性: 良好（清晰注释、语义化函数名、分层结构）
- 错误处理完整性: 优秀（subshell 容错、超时降级、pane 提取降级）
- P0 问题: reviewer 路径 bug 直接导致系统不可用（12 轮无效循环）
- P1 问题: 路径不一致、重复定义（不影响运行）

### 建议总分
- 客观: 9.4 × 0.8 = 7.52 (94.1% 通过率)
- 主观: 5.0 × 0.2 = 1.0 (P0 导致系统不可用，虽然代码质量好但功能失效)
- **总计: 8.52** → 但 P0 bug 使系统不可用，实际价值大打折扣

注：与 Round 12 对比，Round 13 新增了 reviewer CLI 降级逻辑（有改进），但核心 P0 仍未修复。
