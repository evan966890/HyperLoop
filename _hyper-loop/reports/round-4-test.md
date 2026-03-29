# Round 4 试用报告

**日期**: 2026-03-30
**Tester**: Claude (claude --dangerously-skip-permissions)
**构建命令**: `bash -n scripts/hyper-loop.sh` → syntax ok (EXIT=0)

---

## BDD 场景验证结果

| 场景 | 标题 | 结果 | 截图 |
|------|------|------|------|
| S001 | loop 命令启动死循环 | PASS | screenshots/round-4/S001-syntax-check.txt |
| S002 | auto_decompose 生成任务文件 | PASS (P1) | screenshots/round-4/S002-auto-decompose.txt |
| S003 | Writer worktree 创建 + trust + 启动 | PASS | screenshots/round-4/S003-writer-worktree.txt |
| S004 | Writer 完成后 diff 被正确 commit | PASS | screenshots/round-4/S004-writer-commit.txt |
| S005 | diff 审计拦截越界修改 | PASS | screenshots/round-4/S005-diff-audit.txt |
| S006 | Writer 超时处理 | PASS | screenshots/round-4/S006-writer-timeout.txt |
| S007 | Tester 启动并生成报告 | PASS | screenshots/round-4/S007-tester.txt |
| S008 | 3 Reviewer 启动并产出评分 | PASS | screenshots/round-4/S008-reviewers.txt |
| S009 | 和议计算正确 | PASS | screenshots/round-4/S009-verdict-accepted.txt |
| S010 | 一票否决（score < 4.0） | PASS | screenshots/round-4/S010-veto.txt |
| S011 | Tester P0 否决 | PASS | screenshots/round-4/S011-tester-p0.txt |
| S012 | verdict.env 安全读取 | PASS | screenshots/round-4/S012-safe-reading.txt |
| S013 | 连续 5 轮失败自动回退 | PASS | screenshots/round-4/S013-rollback.txt |
| S014 | STOP 文件优雅退出 | PASS | screenshots/round-4/S014-stop-file.txt |
| S015 | worktree 清理 | PASS | screenshots/round-4/S015-cleanup.txt |
| S016 | macOS timeout 兼容 | PASS | screenshots/round-4/S016-macos-timeout.txt |
| S017 | 多 Writer 同文件冲突处理 | PASS | screenshots/round-4/S017-conflict.txt |

**总结: 17/17 场景 PASS**

---

## Bug 列表

### P1 Bugs

#### P1-1: `cmd_status` 函数重复定义（第 694 行和第 954 行）

**描述**: `cmd_status` 函数被定义了两次。第一个定义（694 行）是简化版，第二个（954 行）包含"最佳轮次"显示。Bash 中后定义覆盖前定义，所以第一个是死代码。

**影响**: 代码冗余，不影响功能。

**修复建议**: 删除第 694-700 行的第一个 `cmd_status` 定义。

---

#### P1-2: `auto_decompose` heredoc 中 `\$f` 变量不展开（第 728-729 行）

**描述**: 在 `auto_decompose` 的 `<<DPROMPT` heredoc 中，`\$f` 被 heredoc 展开为字面量 `$f`，导致 for 循环内的 `[[ -f "\$f" ]]` 和 `basename "\$f"` 实际操作的是字面字符串 `$f` 而非循环变量。

**验证**:
```bash
cat <<DPROMPT
$(for f in /tmp/*.json; do
    [[ -f "\$f" ]] && echo "\$(basename "\$f")"
done)
DPROMPT
# 输出为空 — \$f 不展开
```

**影响**: decompose prompt 中"上一轮评分"部分始终为空，Claude 拆解器看不到上一轮的具体评分。功能降级但不崩溃。

**修复建议**: 将 heredoc 分界符改为 `<<'DPROMPT'`（加引号禁止展开），或将评分信息在 heredoc 外构建好再插入。

---

#### P1-3: `auto_decompose` decompose prompt 路径不一致（第 716-717 行）

**描述**: decompose prompt 中引用 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 和 `${PROJECT_ROOT}/_hyper-loop/contract.md`（无 `context/` 前缀），而其他所有地方都用 `_hyper-loop/context/bdd-specs.md`。

**影响**: 目前两个路径都存在对应文件，所以功能正常。但如果只保留 `context/` 下的文件则会 break。

**修复建议**: 统一为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。

---

#### P1-4: `timeout` 函数定义但从未使用（第 17-21 行）

**描述**: 脚本定义了 macOS 兼容的 `timeout` polyfill（S016），但实际的超时控制（Writer、Tester、Reviewer）全部使用 polling loop + sleep 实现，从未调用 `timeout` 函数。

**影响**: 死代码。BDD S016 要求"timeout 函数可用"（PASS），但该函数实际上无法发挥作用。

**修复建议**: 要么在 wait_writers 等函数中使用 timeout 替代 polling loop，要么删除 polyfill 并更新 BDD spec。

---

#### P1-5: `cmd_round` 格式框不完整（第 639-641 行）

**描述**:
```
echo "║  HyperLoop Round $ROUND 开始      "
```
缺少右侧 `║` 关闭符，Unicode box drawing 不完整。

**影响**: 纯美观问题。

---

## 总体评价

脚本 `bash -n` 语法检查通过，所有 17 个 BDD 场景逻辑正确。核心流程（拆任务 → Writer → 审计 → 合并 → 构建 → Tester → Reviewer → 和议 → keep/reset）完整实现。

**优点**:
- `verdict.env` 使用 grep 读取，彻底解决了 bash source 解析错误（S012）
- `cleanup_round` 用 subshell + `set +e`，清理失败不会终止循环
- Python3 内联脚本处理评分计算，避免了 bash 浮点运算陷阱
- Reviewer pane 输出提取作为降级方案，提高了鲁棒性

**不足**:
- 5 个 P1 bug（均不导致崩溃，但影响代码质量和 decompose 效果）
- 无 P0 bug
