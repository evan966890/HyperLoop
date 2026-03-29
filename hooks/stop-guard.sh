#!/usr/bin/env bash
# ============================================================================
# HyperLoop Stop Guard
#
# 在 Claude Code 试图退出会话时触发。
# 如果 HyperLoop 循环未完成（有未处理的 verdict），阻止退出。
#
# exit 0 = 允许退出
# exit 2 = 阻止退出 + 返回消息
# ============================================================================

set -euo pipefail

# 不在 HyperLoop 项目中 → 放行
[[ -d "_hyper-loop" ]] || exit 0

# 没有 results.tsv → 还没开始，放行
[[ -f "_hyper-loop/results.tsv" ]] || exit 0

# 检查最后一轮的状态
LAST_LINE=$(tail -1 "_hyper-loop/results.tsv" 2>/dev/null || echo "")
[[ -z "$LAST_LINE" ]] && exit 0

LAST_DECISION=$(echo "$LAST_LINE" | cut -f4)

# 如果最后一轮是 PENDING_USER，不能退出——用户需要裁决
if [[ "$LAST_DECISION" == "PENDING_USER" ]]; then
  echo "⚠ HyperLoop: 最后一轮评分有分歧（PENDING_USER），需要用户裁决后才能退出。"
  echo ""
  echo "查看分歧: cat _hyper-loop/scores/round-*/reviewer-*.json"
  echo "裁决后手动标记: echo 'USER_RESOLVED' >> _hyper-loop/results.tsv"
  exit 2
fi

# 如果有活跃的 tmux session，提醒
if tmux has-session -t hyper-loop 2>/dev/null; then
  echo "⚠ HyperLoop: tmux session 'hyper-loop' 仍在运行。"
  echo "建议先: tmux kill-session -t hyper-loop"
  # 不阻止退出，只提醒
fi

exit 0
