# HyperLoop 安装指南

## 安装 Skill + Command

```bash
# 复制 skill
mkdir -p ~/.claude/skills/hyper-loop
cp SKILL.md ~/.claude/skills/hyper-loop/
cp -r templates ~/.claude/skills/hyper-loop/
cp hyper-loop.sh ~/.claude/skills/hyper-loop/
chmod +x ~/.claude/skills/hyper-loop/hyper-loop.sh
cp -r hooks ~/.claude/skills/hyper-loop/

# 复制 slash command
cp commands/hyper-loop.md ~/.claude/commands/
```

## 安装 Guard Hook（防止 Claude 直接改源码）

在目标项目的 `.claude/settings.json` 中添加：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/skills/hyper-loop/hooks/guard-no-direct-edit.sh"
          }
        ]
      }
    ]
  }
}
```

这个 hook 会阻止 Claude 直接用 Edit/Write 修改业务代码文件，强制它把任务写到 `_hyper-loop/tasks/` 让 Writer 来改。

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

## 使用

在目标项目中：

```bash
cd ~/Desktop/ClawMom1-setup
claude
# 输入: /hyper-loop 安装向导完整流程
```

Phase 0 完成后，每轮循环：
1. Claude 拆任务 → 写 `_hyper-loop/tasks/round-N/taskM.md`
2. Claude 跑 `PROJECT_ROOT=$(pwd) ~/.claude/skills/hyper-loop/hyper-loop.sh round N`
3. Claude 读 `_hyper-loop/tasks/round-N/verdict.env` → 决策 → 下一轮
