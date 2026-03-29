# CLI 参数速查（实际验证，2026-03-29）

## 核心原则
**不在 shell 里传文本。每个 agent 都能读文件。把文件路径给它，让它自己读。**

上下文文件统一放在 `_hyper-loop/context/` 下，prompt 只需说"先读那个目录"。

---

## Codex CLI (v0.117.0)

### 启动方式
```bash
# 交互模式（Writer 常驻用这个）
codex --full-auto -C $WORKTREE_PATH "先读 _hyper-loop/context/ 下的所有 .md 文件了解项目背景，然后读 TASK.md 执行修复任务"

# 非交互模式（一次性任务）
codex exec -a never -C $WORKTREE_PATH "先读 TASK.md 然后修复"
```

### 关键参数
| 参数 | 用途 |
|------|------|
| `-C $DIR` | 指定工作目录 |
| `--full-auto` | `-a on-request` + `--sandbox workspace-write` |
| `-a never` | 从不弹审批（无人值守） |
| `-s danger-full-access` | 沙箱完全关闭 |
| `--dangerously-bypass-approvals-and-sandbox` | 跳过一切（最危险） |
| `-i FILE` | 附带图片 |
| `-m MODEL` | 指定模型（默认 gpt-5.4） |
| `exec` 子命令 | 非交互，完成后退出 |

### 不存在的参数
- ~~`--file`~~ → 用 `-C` + prompt 里引用文件路径
- ~~`--system-prompt`~~ → prompt 里直接写角色说明

---

## Gemini CLI (v0.35.3)

### 启动方式
```bash
# 非交互评审（Reviewer 用这个）
gemini -y -p "先读 _hyper-loop/context/REVIEWER_INIT.md 了解你的角色和评分规则，再读 _hyper-loop/context/ 下的 PRD/设计文档了解项目，然后评审当前代码" -o json

# 交互模式（常驻 Reviewer）
gemini -y "先读 _hyper-loop/context/REVIEWER_INIT.md 了解你的角色"
```

### 关键参数
| 参数 | 用途 |
|------|------|
| `-y` / `--yolo` | 自动批准所有操作 |
| `-p "..."` | 非交互模式 |
| `-i "..."` | 交互模式但带初始 prompt |
| `-o json` | JSON 输出格式 |
| `-o stream-json` | 流式 JSON |
| `-m MODEL` | 指定模型 |
| `--include-directories DIR` | 额外工作目录 |
| `-r latest` | 恢复最近会话 |

### 不存在的参数
- ~~`--system-prompt`~~ → 在 prompt 中说明角色
- ~~`--approval-mode yolo`~~ → 直接用 `-y`

---

## Claude Code (v2.1.86)

### 启动方式
```bash
# 非交互评审（Reviewer 用这个）
claude --dangerously-skip-permissions -p "先读 _hyper-loop/context/ORCHESTRATOR_CHECKLIST.md 了解评审标准，然后评审当前项目" --add-dir $PROJECT_ROOT

# 带 worktree 的交互模式（Writer 用这个）
claude --dangerously-skip-permissions -w "task-name" --add-dir $PROJECT_ROOT "先读 _hyper-loop/context/WRITER_INIT.md"

# 非交互 + 系统提示
claude --dangerously-skip-permissions --system-prompt "你是 HyperLoop Reviewer" -p "评审 _hyper-loop/context/ 下的文件"
```

### 关键参数
| 参数 | 用途 |
|------|------|
| `--dangerously-skip-permissions` | 跳过所有权限检查 |
| `--system-prompt "..."` | 自定义系统提示 |
| `--append-system-prompt "..."` | 追加到默认系统提示 |
| `-p` / `--print` | 非交互模式，输出后退出 |
| `--add-dir DIR` | 额外允许访问的目录 |
| `-w` / `--worktree [name]` | 自动创建 git worktree |
| `--tmux` | 自动创建 tmux 会话（需要 `--worktree`） |
| `-C DIR` → 不存在 | 用 `--add-dir` 替代 |
| `--output-format json` | JSON 输出 |
| `--output-format stream-json` | 流式 JSON |
| `--model MODEL` | 指定模型 |
| `-c` / `--continue` | 续上一次对话 |
| `-n NAME` | 会话命名 |
| `--max-budget-usd N` | API 费用上限 |

### 特别好用的组合
```bash
# Claude 自带 worktree + tmux！不需要手动管理
claude --dangerously-skip-permissions -w "hyper-loop-task1" --tmux -p "..."

# 非交互 + JSON 输出（解析评分用）
claude --dangerously-skip-permissions -p "评审..." --output-format json
```
