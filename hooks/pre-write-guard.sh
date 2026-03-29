#!/usr/bin/env bash
# ============================================================================
# HyperLoop PreToolUse Guard
#
# 在 Claude Code 每次调用 Edit/Write 之前触发。
# 如果目标是业务代码文件且不在 worktree 中，阻止并提醒。
#
# exit 0 = 允许
# exit 2 = 阻止 + 返回错误消息给 Claude
# ============================================================================

set -euo pipefail

INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")

# 只拦截 Edit 和 Write
[[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" ]] || exit 0

# 不在 HyperLoop 项目中 → 放行
[[ -d "_hyper-loop" ]] || exit 0

# 允许：_hyper-loop/ 目录（任务文件、BDD spec、配置等）
[[ "$FILE_PATH" == *"_hyper-loop/"* ]] && exit 0

# 允许：/tmp/ 临时文件
[[ "$FILE_PATH" == /tmp/* ]] && exit 0

# 允许：skill 自身文件（自进化）
[[ "$FILE_PATH" == *"hyper-loop/SKILL.md" ]] && exit 0
[[ "$FILE_PATH" == *"hyper-loop/templates/"* ]] && exit 0
[[ "$FILE_PATH" == *"hyper-loop/scripts/"* ]] && exit 0
[[ "$FILE_PATH" == *"hyper-loop/hooks/"* ]] && exit 0

# 允许：worktree 中的文件（Writer 在写）
# worktree 路径通常在 /tmp/hyper-loop-worktrees-*
[[ "$FILE_PATH" == /tmp/hyper-loop-worktrees-* ]] && exit 0

# 业务代码文件扩展名
case "$FILE_PATH" in
  *.svelte|*.rs|*.ts|*.js|*.tsx|*.jsx|*.css|*.scss|*.html|*.vue|*.py|*.go)
    echo "⛔ HyperLoop Guard: Orchestrator 不能直接修改业务代码。"
    echo ""
    echo "被阻止: $FILE_PATH"
    echo ""
    echo "正确做法："
    echo "1. 写任务文件: _hyper-loop/tasks/round-N/taskM.md"
    echo "2. 调用: PROJECT_ROOT=\$(pwd) ~/.claude/skills/hyper-loop/scripts/hyper-loop.sh round N"
    echo "3. 脚本会启动 Writer 在 worktree 中修改"
    exit 2
    ;;
esac

# 其他文件类型放行（如 .md、.json、.yaml 配置文件）
exit 0
