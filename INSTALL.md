# HyperLoop 安装指南

## 方式 1：作为 Claude Code Plugin 安装（推荐）

```bash
# 注册为本地 plugin
claude plugin add --dir ~/Desktop/HyperLoop

# 或者手动复制到 plugins 目录
cp -r ~/Desktop/HyperLoop ~/.claude/plugins/hyper-loop
```

安装后 hook 自动生效：
- **SessionStart**: 进入有 `_hyper-loop/` 的项目时自动注入 Orchestrator 规则
- **PreToolUse(Edit|Write)**: 阻止直接修改业务代码
- **Stop**: 有未裁决的评分分歧时阻止退出

## 方式 2：手动安装

```bash
# Skill
mkdir -p ~/.claude/skills/hyper-loop
cp skills/hyper-loop/SKILL.md ~/.claude/skills/hyper-loop/

# 脚本
cp scripts/hyper-loop.sh ~/.claude/skills/hyper-loop/
chmod +x ~/.claude/skills/hyper-loop/hyper-loop.sh

# 模板
cp -r templates ~/.claude/skills/hyper-loop/

# Agent 定义
cp -r agents ~/.claude/skills/hyper-loop/

# Slash command
cp commands/hyper-loop.md ~/.claude/commands/

# Hook（需要手动配置 settings.json）
# 见下方"手动 Hook 配置"
```

### 手动 Hook 配置

在 `~/.claude/settings.json` 的 `hooks` 字段中添加：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/hyper-loop/hooks/pre-write-guard.sh"
          }
        ]
      }
    ]
  }
}
```

## 前置依赖

```bash
# 必须
codex --version    # Codex CLI
gemini --version   # Gemini CLI
tmux -V            # tmux
git worktree list  # git worktree

# 推荐
playwright --version   # Web 层 E2E
which cliclick         # macOS 鼠标模拟
which peekaboo         # macOS 截图
```

## 关键：在目标项目安装 Guard Hook

**不做这一步，Claude 会无视所有规则直接改代码。** 这是 v5.1 实测验证的教训。

```bash
# 在目标项目中创建 .claude/settings.json
mkdir -p ~/Desktop/ClawMom1-setup/.claude
cat > ~/Desktop/ClawMom1-setup/.claude/settings.json <<'HOOKEOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/hyper-loop/hooks/pre-write-guard.sh"
          }
        ]
      }
    ]
  }
}
HOOKEOF
```

## 使用

```bash
cd ~/Desktop/ClawMom1-setup  # 目标项目
claude
# 输入: /hyper-loop 安装向导完整流程
```

Phase 0 完成后，每轮循环：
1. Claude 拆任务 → 写 `_hyper-loop/tasks/round-N/taskM.md`
2. Claude 跑 `PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh round N`
3. Claude 读 `_hyper-loop/tasks/round-N/verdict.env` → 决策 → 下一轮

## Plugin 结构说明

```
hyper-loop/
├── .claude-plugin/plugin.json    # 插件元数据
├── hooks/
│   ├── hooks.json                # hook 声明
│   ├── session-start.sh          # SessionStart → 注入 Orchestrator 规则
│   ├── pre-write-guard.sh        # PreToolUse → 阻止直接写业务代码
│   └── stop-guard.sh             # Stop → 未裁决时阻止退出
├── scripts/
│   └── hyper-loop.sh             # 编排脚本（tmux/writer/tester/reviewer/和议）
├── skills/hyper-loop/SKILL.md    # Claude 的决策指南
├── agents/
│   ├── tester.md                 # Tester 子 agent 定义
│   └── reviewer.md               # Reviewer 子 agent 定义
├── templates/                    # 4 个角色初始化模板
└── commands/hyper-loop.md        # /hyper-loop 命令入口
```
