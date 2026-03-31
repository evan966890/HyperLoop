# HyperLoop 改进日志 — 2026-03-30/31 → 04-01

## v5.5 突破：从全拒到 9.0 (2026-03-31 session)

### 结果
| Round | Median | Gemini | Claude | Codex | Writers | 决策 |
|-------|--------|--------|--------|-------|---------|------|
| 1-10  | 5.0-6.3| 5.0(fb)| 3.0-8.5| 4.0-6.5| 1/4  | 全REJECTED |
| 11    | 6.5    | 6.8    | 6.5    | 6.5   | 4/4    | ACCEPTED |
| 12    | 9.0    | 9.4    | 9.0    | 8.4   | 4/4    | ACCEPTED |

### 根因分析：为什么前 10 轮全部失败
1. **tester_p0 子串匹配永远 True** — `"P0" in text` 命中每份报告的 `## P0 Bugs` 标题。这是唯一阻塞因素，修复后立即 ACCEPTED
2. **Gemini 收不到 prompt** — `gemini -y -p ""` 传了空字符串，实际 prompt 在 stdin 但 gemini 不读 stdin。改为 `-p "$(cat file)"`
3. **75% Writer 产出浪费** — DONE.json/TASK.md 等元数据随 `git add -A` 进入 writer 分支，导致 squash merge 冲突。3 行 `rm -f` 修复
4. **脚本启动不了第二轮** — mktemp 的 `.md` 后缀在 macOS 上不兼容（X 必须在末尾）；dirty working tree 阻止 merge to main；`loop 5` 语义是"跑到第 5 轮"而非"再跑 5 轮"

### 修复清单 (3 commits)
| Commit | 问题 | 修复 |
|--------|------|------|
| e371019 | P0 检测假阳性 | 子串匹配 → 结构化计数 `### P0` headings + BDD FAIL 阈值 |
| e371019 | 审计白名单缺 .sh | 加 sh/bash/toml/json/md/yaml/yml |
| e371019 | 构建失败跳过 archive_round | 补调用 + SCORES 行 |
| e371019 | cmd_status 重复定义 | 删除死代码版 |
| e371019 | Gemini prompt 未送达 | `-p ""` → `-p "$(cat file)"` |
| e371019 | Codex reviewer CLI arg 过长 | 改 stdin 管道 |
| e371019 | PREV_MEDIAN 非数字崩溃 | 正则校验 |
| e371019 | MEDIAN 残留导致误退出 | 每轮开头重置 |
| e371019 | 0 Writer 合并仍跑评审 | merge-count 检查 |
| e371019 | BDD S004/S017 过时 | 更新规格反映元数据清理 |
| bde898f | mktemp .md 后缀 macOS 不兼容 | 去掉 .md 后缀 |
| 8fe161d | (Round 12 Writer) 死代码 start_agent/kill_agent | 删除 |
| 8fe161d | (Round 12 Writer) audit 不检测 untracked 文件 | 加 `git ls-files --others` |
| 8fe161d | (Round 12 Writer) build_app cd 污染父进程 cwd | 改 subshell |
| 8fe161d | (Round 12 Writer) loop 冷启动丢失历史最佳 | 启动时读 results.tsv 恢复状态 |

### 三个质变时刻
1. **v5.2: SKILL.md → bash 脚本** — AI 行为靠程序约束，不靠文字请求
2. **v5.4: tmux 交互 → 管道模式** — AI 间通信走管道不走交互
3. **v5.5: 评估管道 bug 修复** — 评估逻辑的 bug 比被评估代码的 bug 更致命

### 工程经验
- 多 agent 系统瓶颈在胶水代码正确性，不在 AI 能力
- 148 行修复 → 评分从 5.0 飙到 9.0；3 行 rm -f → 合并率从 25% → 100%
- nohup 后台跑时 stderr 被吞，平台差异（mktemp）极难定位
- dirty working tree 阻止 git merge 在 `|| true` 下静默失败，但后续操作可能崩
- Writer 自改进有效：Round 12 的 4 个 Writer 独立发现了 dead code、cwd 污染、untracked 文件遗漏、冷启动状态丢失

---

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
