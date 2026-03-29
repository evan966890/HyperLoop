#!/usr/bin/env bash
# ============================================================================
# HyperLoop Guard Hook
#
# 安装到 Claude Code settings.json 的 PreToolUse hook。
# 当 Claude 试图用 Edit/Write 修改业务代码文件时，阻止并提醒。
#
# 允许修改的文件：_hyper-loop/ 目录下的所有文件（任务、配置、BDD spec 等）
# 禁止修改的文件：项目源码（src/、daemon/、tauri-app/ 等）
# ============================================================================

set -euo pipefail

# 从 stdin 读取 hook input JSON
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_input',{}).get('file_path',''))" 2>/dev/null || echo "")

# 只检查 Edit 和 Write 工具
if [[ "$TOOL_NAME" != "Edit" && "$TOOL_NAME" != "Write" ]]; then
  exit 0
fi

# 允许修改 _hyper-loop/ 目录下的文件
if [[ "$FILE_PATH" == *"_hyper-loop/"* ]]; then
  exit 0
fi

# 允许修改 /tmp/ 下的文件
if [[ "$FILE_PATH" == /tmp/* ]]; then
  exit 0
fi

# 允许修改 SKILL.md 和模板（自身进化）
if [[ "$FILE_PATH" == *"hyper-loop/SKILL.md" ]] || [[ "$FILE_PATH" == *"hyper-loop/templates/"* ]]; then
  exit 0
fi

# 禁止修改其他文件
echo "⛔ HyperLoop Guard: Orchestrator 不允许直接修改业务代码文件。"
echo "   被阻止的文件: $FILE_PATH"
echo "   请把修复任务写到 _hyper-loop/tasks/round-N/taskM.md，然后调用 hyper-loop.sh round N"
echo ""
echo '{"error":"HyperLoop Guard: Orchestrator 禁止直接修改业务代码。请写任务文件让 Writer 修改。"}'
exit 2
