# HyperLoop 改进日志 — 2026-03-30/31

## 本轮成果

### 自优化实测 (10 轮)
- 评分从全 0 提升到 5.0-6.3（Claude 最高 8.5）
- 3 Reviewer 合议管道首次全部产出真实评分
- Tester BDD 验证从 0/17 提升到 15/17 PASS

### ClawMom 实战 (7 轮)
- 评分 6.4 → 8.6，达到 8.5 目标
- ~3500 行代码改动，30+ 文件
- 27 个渲染组件全部视觉打磨

---

## 修复清单 (15 commits)

### P0 修复
| Commit | 问题 | 修复 |
|--------|------|------|
| 050f66e | S002 auto_decompose 路径错误 | `_hyper-loop/bdd-specs.md` → `context/bdd-specs.md` |
| 2e3c2de | S004 merge_writers stdout 污染 | 所有 echo 加 `>&2` |
| a1df1dd | S004 git commit/merge stdout 泄漏 | git 命令输出也 `>&2` |
| 2fd7c94 | Gemini 从未输出 JSON（10 轮 fallback 5） | `-p -` → `-p ""`，`--add-dir` → `--include-directories` |
| e7bdf07 | 多 Writer 元数据冲突（DONE.json/TASK.md） | merge 前 `rm -f` 清理 |
| 86e1fec | `_writer_prompt.md` 也导致冲突 | 加入清理列表 |
| b7ef288 | Writer tmux paste 不可靠（ClawMom 0 行改动） | 改为 `codex exec` 非交互模式 |
| 4f7adb3 | `find` 运算符优先级泄漏目录 | 加 `\( \)` 分组 |
| 4f7adb3 | 扫描结果含绝对路径 | `cd $PROJECT_ROOT && find .` 相对路径 |

### P1 修复
| Commit | 问题 | 修复 |
|--------|------|------|
| 050f66e | S008 fallback 日志 "score 3" 实际写 5 | 日志改为 "score 5" |
| 050f66e | results.tsv 空文件 crash | grep 数字行 + 空值兜底 |
| 2e3c2de | S006 Writer 超时 300s（BDD 要求 900s） | 改为 900s |
| 2e3c2de | S015 worktree 父目录残留 | 加 `rm -rf $WORKTREE_BASE` |
| db6bfd5 | Codex reviewer 无项目访问权限 | 加 `--full-auto -C $PROJECT_ROOT` |
| e7bdf07 | PREV_MEDIAN 空串 `float('')` crash | grep + 兜底 0 |
| e7bdf07 | archive_round 路径缺少 context/ | 修正路径 |
| 86e1fec | 超时 kill 只杀 subshell 不杀 codex | 改用进程组 kill |
| 4f7adb3 | 扫描遗漏 docs/research, sprint, runbook | 加入扫描列表 |
| 4f7adb3 | BMAD head -80 截断 | 改为 head -200 |
| 4f7adb3 | `claude -p -` 字面 "-" 作 prompt | 改为 `-p` |
| 4f7adb3 | stderr 被 2>/dev/null 吞掉 | 改为写日志文件 |
| 4f7adb3 | init 覆盖用户 brief 无备份 | 先 `.bak` 备份 |

### 功能新增
| Commit | 功能 |
|--------|------|
| 160c51c | Tester + 3 Reviewer 完整对话日志保存 |
| fcfd462 | 日志命名 `round-N_role_action_agent.log` |
| db6bfd5 | CLI 参考知识库 `cli-reference-verified.md` |
| 1baa2ee | 扫描式任务描述（grep all instances） |
| d77255d | `cmd_init` 项目扫描 → Claude 简报 → 持久化 |
| c3fbdc4 | Writer prompt 结构化注入（brief + BDD + contract + task） |
| f64d278 | mktemp 防并行冲突 + prompt 行数日志 |

---

## 架构变更

### Writer: tmux → codex exec
- 之前: tmux 启动 Codex → sleep 5 → paste-buffer 注入 → 轮询 DONE.json
- 现在: 构造 _writer_prompt.md → `cat | codex exec -C $WT -` → 后台并行 → jobs -r 检查
- 原因: paste-buffer 不可靠，ClawMom 首轮 4 个 Writer 全部 DONE 但 0 行改动

### 上下文注入: 原文复制 → Claude 提炼简报
- 之前: `cp -r context/ _ctx/` + `head -100` 每个文件
- 现在: `cmd_init` 扫描 → Claude 提炼 ≤300 行 project-brief.md → 持久化
- Writer prompt = WRITER_INIT + project-brief + BDD + contract + TASK

### Gemini/Codex CLI: 参数全部实测验证
- Gemini: `-p ""` (不是 `-p -`)，`--include-directories` (不是 `--add-dir`)
- Codex: `exec -` 读 stdin，`-C` 设工作目录，`--full-auto` 开写权限
- 保存为 `cli-reference-verified.md` 供脚本参考

### Ralph Loop: 彻底移除
- settings.json / installed_plugins.json / install-counts-cache.json 全部清理
- cache/data/marketplace 目录删除

---

## 下次继续时的注意事项
1. 重启 Claude Code 会话让 ralph-loop 清除生效
2. 在新项目上跑之前先 `hyper-loop.sh init` 生成 project-brief.md
3. Gemini reviewer 已修复 CLI flags，下次应该能出真实评分
4. 多 Writer 元数据冲突已修复，预期 merge 成功率从 25% 提升到 80%+
5. Writer 改为 codex exec 非交互模式，上下文通过 stdin 管道注入
