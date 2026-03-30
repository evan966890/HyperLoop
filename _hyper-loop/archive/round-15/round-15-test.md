# Round 15 试用报告

**测试时间**: 2026-03-30
**测试对象**: scripts/hyper-loop.sh (git HEAD, 987 行)
**语法检查**: `bash -n` PASS (exit 0)

> **注意**: 工作副本 scripts/hyper-loop.sh 已被 `script` 命令覆写（仅 43 字节），本报告基于 git HEAD 版本测试。

---

## BDD 场景验证

| ID | 场景 | 结果 | 截图 |
|----|------|------|------|
| S001 | loop 命令启动死循环 | **PASS** | screenshots/round-15/s001.txt |
| S002 | auto_decompose 生成任务文件 | **PASS** (P1) | screenshots/round-15/s002.txt |
| S003 | Writer worktree 创建 + trust + 启动 | **PASS** | screenshots/round-15/s003.txt |
| S004 | Writer 完成后 diff 被正确 commit | **PASS** | screenshots/round-15/s004.txt |
| S005 | diff 审计拦截越界修改 | **PASS** | screenshots/round-15/s005.txt |
| S006 | Writer 超时处理 | **PASS** | screenshots/round-15/s006.txt |
| S007 | Tester 启动并生成报告 | **PASS** (P1) | screenshots/round-15/s007.txt |
| S008 | 3 Reviewer 启动并产出评分 | **PASS** | screenshots/round-15/s008.txt |
| S009 | 和议计算正确 | **PASS** | screenshots/round-15/s009.txt |
| S010 | 一票否决 (score < 4.0) | **PASS** | screenshots/round-15/s010.txt |
| S011 | Tester P0 否决 | **PASS** | screenshots/round-15/s011.txt |
| S012 | verdict.env 安全读取 | **PASS** | screenshots/round-15/s012.txt |
| S013 | 连续 5 轮失败自动回退 | **PASS** | screenshots/round-15/s013.txt |
| S014 | STOP 文件优雅退出 | **PASS** | screenshots/round-15/s014.txt |
| S015 | worktree 清理 | **FAIL** | screenshots/round-15/s015.txt |
| S016 | macOS timeout 兼容 | **PASS** | screenshots/round-15/s016.txt |
| S017 | 多 Writer 同文件冲突处理 | **PASS** | screenshots/round-15/s017.txt |

**通过率**: 16/17 (94.1%)

---

## Bug 列表

### P0

| # | 描述 | 位置 | 影响 |
|---|------|------|------|
| P0-1 | **工作副本 scripts/hyper-loop.sh 被 `script` 命令覆写** | scripts/hyper-loop.sh (磁盘) | 文件仅 43 字节，内容为 `Script started on Mon Mar 30 04:15:42 2026`。疑似 `script scripts/hyper-loop.sh` 误操作。Git HEAD 987 行版本完好。**脚本完全无法执行**。 |

### P1

| # | 描述 | 位置 | 影响 |
|---|------|------|------|
| P1-1 | **S015: cleanup_round 不删除 worktree 基目录** | line 600-609 | `git worktree remove` 只删子目录，`/tmp/hyper-loop-worktrees-rN/` 空目录残留。需追加 `rm -rf "$WORKTREE_BASE" 2>/dev/null`。 |
| P1-2 | **cmd_status 重复定义** | line 697 和 line 957 | 第一个 cmd_status (line 697) 无最佳轮次显示，被第二个 (line 957) 覆盖。应删除第一个。 |
| P1-3 | **auto_decompose 路径引用不一致** | line 719-720 | 用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，而其他函数用 `_hyper-loop/context/` 路径。虽然两个位置都有文件，但不一致易混淆且 Claude 可能读不到正确版本。 |
| P1-4 | **Tester 超时消息错误** | line 421 | 实际超时 900s=15 分钟，但错误消息写 "Tester 未在 10 分钟内完成"。 |
| P1-5 | **archive_round 路径不一致** | line 797 | `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 应为 `_hyper-loop/context/bdd-specs.md`。 |
| P1-6 | **cmd_loop 中 grep verdict.env 无 || true 防护** | line 897-898 | 在 `set -euo pipefail` 下，如果 verdict.env 异常缺少 DECISION= 行，grep 会 exit 1 导致整个脚本崩溃。虽然 compute_verdict 正常情况总写 DECISION，但缺乏防御性编程。 |

---

## 评估维度

### 客观指标 (80%)
- **bash -n 语法检查**: PASS
- **BDD 场景通过率**: 16/17 = 94.1%
- 加权得分: 0.8 * (1.0 * 0.5 + 0.941 * 0.5) = **0.776**

### 主观维度 (20%, 上限 7.0)
- **代码可读性**: 良好。函数结构清晰，中文注释充分，heredoc 用法恰当。
- **错误处理完整性**: 较好。`set -e` + subshell + `|| true` 使用得当。但 grep verdict.env 缺防护、cmd_status 重复定义等细节扣分。
- 主观评分: **5.5/7.0**
- 加权得分: 0.2 * 5.5 = **1.1**

### 总分估算: 0.776 * 10 + 1.1 = **~6.5**

---

## 修复建议优先级

1. **P0-1**: `git checkout HEAD -- scripts/hyper-loop.sh` 恢复工作副本
2. **P1-1**: cleanup_round 末尾加 `rm -rf "$WORKTREE_BASE" 2>/dev/null`
3. **P1-2**: 删除 line 697-703 的第一个 cmd_status
4. **P1-3/P1-5**: 统一路径为 `_hyper-loop/context/`
5. **P1-4**: 修改 "10 分钟" 为 "15 分钟"
6. **P1-6**: grep 加 `|| true` 防护
