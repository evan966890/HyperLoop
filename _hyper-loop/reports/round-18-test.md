# Round 18 试用报告

**日期**: 2026-03-30
**测试对象**: `scripts/hyper-loop.sh` (git HEAD, 987 行)
**bash -n 语法检查**: PASS

---

## 重要发现

**P0: 工作副本被破坏** — `scripts/hyper-loop.sh` 工作副本仅 43 字节，被 `script` 命令输出覆盖。git HEAD 版本完好。本报告基于 HEAD 版本评估。

---

## BDD 场景逐条验证

| 场景 | 标题 | 结果 | 截图 |
|------|------|------|------|
| S001 | loop 命令启动死循环 | **PASS** | screenshots/round-18/S001-syntax-check.txt |
| S002 | auto_decompose 生成任务文件 | **FAIL** | screenshots/round-18/S002-auto-decompose.txt |
| S003 | Writer worktree 创建 + trust + 启动 | **PASS** | screenshots/round-18/S003-writer-worktree.txt |
| S004 | Writer 完成后 diff 被正确 commit | **PASS** | screenshots/round-18/S004-writer-commit-merge.txt |
| S005 | diff 审计拦截越界修改 | **PASS** | screenshots/round-18/S005-diff-audit.txt |
| S006 | Writer 超时处理 | **PASS** | screenshots/round-18/S006-writer-timeout.txt |
| S007 | Tester 启动并生成报告 | **PASS** | screenshots/round-18/S007-tester.txt |
| S008 | 3 Reviewer 启动并产出评分 | **PASS** | screenshots/round-18/S008-reviewers.txt |
| S009 | 和议计算正确 | **PASS** | screenshots/round-18/S009-verdict-calc.txt |
| S010 | 一票否决（score < 4.0） | **PASS** | screenshots/round-18/S010-veto.txt |
| S011 | Tester P0 否决 | **PASS** | screenshots/round-18/S011-tester-p0.txt |
| S012 | verdict.env 安全读取 | **PASS** | screenshots/round-18/S012-verdict-safe-read.txt |
| S013 | 连续 5 轮失败自动回退 | **PASS** | screenshots/round-18/S013-rollback.txt |
| S014 | STOP 文件优雅退出 | **PASS** | screenshots/round-18/S014-stop-file.txt |
| S015 | worktree 清理 | **FAIL** | screenshots/round-18/S015-worktree-cleanup.txt |
| S016 | macOS timeout 兼容 | **PASS** | screenshots/round-18/S016-macos-timeout.txt |
| S017 | 多 Writer 同文件冲突处理 | **PASS** | screenshots/round-18/S017-merge-conflict.txt |

**通过率**: 15/17 (88.2%)

---

## Bug 列表

### P0 — 致命

| # | 描述 | 位置 | 影响 |
|---|------|------|------|
| P0-1 | 工作副本被破坏：`scripts/hyper-loop.sh` 被 `script` 命令输出覆盖，仅 43 字节 | 工作目录 | 脚本无法从工作副本执行。需 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复 |

### P1 — 严重

| # | 描述 | 位置 | 影响 |
|---|------|------|------|
| P1-1 | `auto_decompose` 引用错误路径：`_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，正确路径应为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md` | line 719-720 | Claude 拆解任务时读不到 BDD spec 和 contract，导致任务质量下降。这可能是 17 轮全部 REJECTED_VETO 的根因之一 |

### P2 — 一般

| # | 描述 | 位置 | 影响 |
|---|------|------|------|
| P2-1 | `archive_round` 引用错误路径 `_hyper-loop/bdd-specs.md`（缺 `context/`） | line 797 | 归档缺少 bdd-specs.md，但因 `\|\| true` 不崩溃 |
| P2-2 | `cleanup_round` 未清理 WORKTREE_BASE 父目录 `/tmp/hyper-loop-worktrees-rN/` | line 590-610 | 空目录残留，违反 S015 spec |
| P2-3 | `run_tester` 超时消息写 "10 分钟" 但实际超时 900s = 15 分钟 | line 421 | 误导性日志 |
| P2-4 | `cmd_status` 函数重复定义（line 697 和 line 957），第一个是死代码 | line 697-703 | 代码冗余，不影响功能 |

---

## 综合评估

**客观指标 (80%)**:
- bash -n 语法检查: PASS
- BDD 场景通过率: 15/17 = 88.2%
- 客观分 = 0.8 × (0.5 × 1.0 + 0.5 × 0.882) × 10 = **7.53**

**主观维度 (20%)**:
- 代码可读性: 良好 — 函数划分清晰，注释充分，中文命名贴合场景
- 错误处理: 良好 — `set +e` subshell、`|| true`、超时降级等机制完善
- 存在路径引用错误和死代码，扣分
- 主观分 = **6.0**

**综合估分**: 7.53 × 0.8 + 6.0 × 0.2 = **7.22**

---

## 改进建议（优先级排序）

1. **恢复工作副本** (P0): `git checkout HEAD -- scripts/hyper-loop.sh`
2. **修复 auto_decompose 路径** (P1): 将 line 719-720 的 `_hyper-loop/bdd-specs.md` 改为 `_hyper-loop/context/bdd-specs.md`（contract.md 同理）
3. **修复 archive_round 路径** (P2): line 797 同上
4. **cleanup_round 添加 rmdir** (P2): 在 subshell 末尾加 `rmdir "$WORKTREE_BASE" 2>/dev/null`
5. **修正 Tester 超时消息** (P2): "10 分钟" → "15 分钟"
6. **删除重复的 cmd_status** (P2): 删除 line 697-703
