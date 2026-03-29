---
description: 监控 HyperLoop 循环进度 — 查看 loop.log、results.tsv、Writer 状态
---

查看 HyperLoop 循环的当前状态。如果用户要求持续监控，用 `/loop 5m /hyper-loop-monitor` 设置定时。

```bash
echo "=== Loop Log (最近 30 行) ==="
tail -30 _hyper-loop/loop.log 2>/dev/null || echo "未启动"

echo ""
echo "=== Results ==="
cat _hyper-loop/results.tsv 2>/dev/null || echo "无结果"

echo ""
echo "=== 进程 ==="
ps aux | grep hyper-loop.sh | grep -v grep | head -3

echo ""
echo "=== Writer 状态 ==="
for wt in /tmp/hyper-loop-worktrees-*/task*; do
  [ -d "$wt" ] || continue
  NAME=$(basename "$wt")
  if [ -f "$wt/DONE.json" ]; then
    STATUS=$(python3 -c "import json; print(json.load(open('$wt/DONE.json'))['status'])" 2>/dev/null)
    echo "  $NAME: $STATUS"
  else
    echo "  $NAME: 进行中..."
  fi
done

echo ""
echo "=== tmux ==="
tmux list-windows -t hyper-loop 2>/dev/null || echo "无 tmux session"
```

$ARGUMENTS
