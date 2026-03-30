## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。重点关注 PREV_MEDIAN 的计算和 cmd_status 的定义。

### 问题
[P1] 两个独立但简单的问题:

**问题 A: PREV_MEDIAN 在 results.tsv 为空时变成空字符串**
位置: scripts/hyper-loop.sh L845
```bash
PREV_MEDIAN=$(tail -1 "${PROJECT_ROOT}/_hyper-loop/results.tsv" | cut -f2 || echo 0)
```
`|| echo 0` 是死代码 — `cut` 命令即使输入为空也返回 exit 0，所以 `|| echo 0` 永远不会执行。当 results.tsv 为空文件时，`PREV_MEDIAN=""` 而非 `"0"`。传给 Python 的 `float("")` 会抛 ValueError，verdict.env 不会生成。

修复: 在赋值后加 `PREV_MEDIAN="${PREV_MEDIAN:-0}"`

**问题 B: cmd_status 重复定义**
位置: L670-676 (第一个定义) 和 L930-942 (第二个定义，功能更完整)
第一个定义是死代码（被第二个覆盖），增加维护混乱。

修复: 删除 L670-676 的第一个定义。

### 相关文件
- scripts/hyper-loop.sh (L843-846) — PREV_MEDIAN 计算
- scripts/hyper-loop.sh (L670-676) — 第一个 cmd_status 定义（应删除）
- scripts/hyper-loop.sh (L930-942) — 第二个 cmd_status 定义（保留）

### 约束
- 只修指定的两处
- PREV_MEDIAN 修复后确保默认值为 "0" 而非空字符串
- 删除第一个 cmd_status 时不影响前后代码
- 不改 CSS

### 验收标准
- S009: compute_verdict 在首轮（results.tsv 为空）也能正常计算中位数
- S001: 首轮循环不会因 PREV_MEDIAN 为空而崩溃
