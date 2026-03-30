# Round 21 试用报告

**测试时间**: 2026-03-30
**测试对象**: scripts/hyper-loop.sh (HEAD commit: 67e82df, 987 行)
**构建验证**: `bash -n` 通过 (exit 0)

---

## 工作副本异常

**P0**: `scripts/hyper-loop.sh` 工作副本被覆写为 1 行 (`Script started on Mon Mar 30 07:00:32 2026`)，疑似 `script` 命令输出误重定向。HEAD 版本 (987 行) 正常。以下测试基于 HEAD 版本。

---

## BDD 场景逐条验证

| 场景 | 标题 | 结果 | 截图 |
|------|------|------|------|
| S001 | loop 命令启动死循环 | PASS | screenshots/round-21/S001-syntax.txt |
| S002 | auto_decompose 生成任务文件 | **FAIL** | screenshots/round-21/S002-decompose-paths.txt |
| S003 | Writer worktree 创建 + trust + 启动 | PASS | screenshots/round-21/S003-worktree.txt |
| S004 | Writer 完成后 diff 被正确 commit | PASS | screenshots/round-21/S004-merge.txt |
| S005 | diff 审计拦截越界修改 | PASS | screenshots/round-21/S005-audit.txt |
| S006 | Writer 超时处理 | PASS | screenshots/round-21/S006-timeout.txt |
| S007 | Tester 启动并生成报告 | PASS | screenshots/round-21/S007-tester.txt |
| S008 | 3 Reviewer 启动并产出评分 | PASS | screenshots/round-21/S008-reviewers.txt |
| S009 | 和议计算正确 | PASS | screenshots/round-21/S009-S012-verdict.txt |
| S010 | 一票否决 (score < 4.0) | PASS | screenshots/round-21/S009-S012-verdict.txt |
| S011 | Tester P0 否决 | PASS | screenshots/round-21/S009-S012-verdict.txt |
| S012 | verdict.env 安全读取 | PASS | screenshots/round-21/S009-S012-verdict.txt |
| S013 | 连续 5 轮失败自动回退 | PARTIAL | screenshots/round-21/S013-rollback.txt |
| S014 | STOP 文件优雅退出 | PASS | screenshots/round-21/S014-stop.txt |
| S015 | worktree 清理 | PASS | screenshots/round-21/S015-cleanup.txt |
| S016 | macOS timeout 兼容 | PASS | screenshots/round-21/S016-timeout-compat.txt |
| S017 | 多 Writer 同文件冲突处理 | PASS | screenshots/round-21/S017-conflict.txt |

**通过率**: 15/17 (88.2%) — 1 FAIL, 1 PARTIAL

---

## Bug 列表

### P0 (阻塞)

**P0-1: auto_decompose 引用路径错误 (S002)**
- **位置**: 第 719-720 行
- **问题**: `auto_decompose()` 生成的 prompt 里引用 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 和 `${PROJECT_ROOT}/_hyper-loop/contract.md`，缺少 `/context/` 路径段。实际文件在 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。
- **影响**: Claude 拆解器找不到 BDD 规格和评估契约，导致任务拆解缺乏关键上下文。这是 20 轮全部 0 分的**根本原因之一**——拆解器无法读到 BDD specs，生成的任务与实际需求脱节。
- **修复**: 第 719 行改为 `_hyper-loop/context/bdd-specs.md`，第 720 行改为 `_hyper-loop/context/contract.md`。

**P0-2: archive_round 归档路径错误**
- **位置**: 第 797 行
- **问题**: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 缺少 `/context/`。归档不到 BDD specs，导致后续回退时丢失关键文件。
- **修复**: 改为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。

**P0-3: scripts/hyper-loop.sh 工作副本被覆写**
- **问题**: 工作副本只有 1 行 `Script started on Mon Mar 30 07:00:32 2026`，非法内容。
- **影响**: 脚本无法执行。
- **修复**: `git checkout HEAD -- scripts/hyper-loop.sh`。

### P1 (重要)

**P1-1: cmd_status() 重复定义**
- **位置**: 第 697 行和第 957 行
- **问题**: 同名函数定义两次，第二个覆盖第一个。第一个版本功能较简单（缺少"最佳轮次"显示）。
- **影响**: 不影响功能（bash 以最后定义为准），但代码冗余。
- **修复**: 删除第 697-703 行的旧定义。

**P1-2: Tester 超时文案不一致 (S007)**
- **位置**: 第 421 行
- **问题**: 超时报告写 "Tester 未在 10 分钟内完成" 但实际超时是 900s = 15 分钟。
- **修复**: 改为 "15 分钟"。

**P1-3: S013 回退逻辑不跨 loop 重启 (S013)**
- **位置**: 第 846-848 行
- **问题**: `BEST_ROUND` 和 `BEST_MEDIAN` 只在当次 `cmd_loop` 内存中跟踪。如果脚本崩溃重启，这两个变量重置为 0，使得连续 5 轮失败回退条件 `$BEST_ROUND -gt 0` 永远不满足。
- **BDD 要求**: S013 要求从 `archive/round-N/git-sha.txt` 找最高分轮次回退。
- **修复**: 在 loop 开始时从 `results.tsv` + `archive/` 目录恢复 `BEST_ROUND` 和 `BEST_MEDIAN`。

---

## 客观指标评估

- **bash -n 语法检查**: PASS (0 errors)
- **BDD 场景通过率**: 15/17 = 88.2%
  - S002 FAIL (路径错误导致功能失效)
  - S013 PARTIAL (逻辑存在但不完整)
- **加权客观分**: 88.2% × 8.0 (满分权重) = 7.06

## 主观维度评估

- **代码可读性**: 良好。函数拆分清晰，注释充分，中文 + 英文混用但可读。
- **错误处理**: 较好。`set +e` subshell 保护清理、`|| true` 防崩、Python 降级提取 JSON 等。但 S013 的跨重启恢复缺失是错误处理的盲区。
- **主观分**: 5.5/7.0

---

## 综合评估

这是一个 **架构完整、功能覆盖面广** 的编排脚本。17 个 BDD 场景中 15 个通过，核心循环逻辑（Writer/Tester/Reviewer/和议/归档/清理）运作正确。

**核心瓶颈**: P0-1（路径错误）是 20 轮全部 0 分的关键诱因——auto_decompose 读不到 BDD specs，生成的任务文件质量极差，Writer 产出无法对齐验收标准，最终 Reviewer 只能给 0 分。修复这 3 个路径 bug 后，循环质量应有显著提升。
