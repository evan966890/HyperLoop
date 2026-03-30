## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] PREV_MEDIAN 空字符串导致 Python float("") 崩溃

`cmd_loop` 中 (line 849-851):
```bash
PREV_MEDIAN=$(tail -1 "${PROJECT_ROOT}/_hyper-loop/results.tsv" | cut -f2 || echo 0)
```
当 results.tsv 存在但为空时，`tail -1 | cut -f2` 返回空字符串（管道成功，`|| echo 0` 不触发）。空字符串传入 `compute_verdict` 的 Python `float("")` 会抛 ValueError，导致整轮崩溃。这是脚本稳定性的最大隐患——results.tsv 为空在首轮或文件被清空时必然发生。

### 相关文件
- scripts/hyper-loop.sh (line 848-851，PREV_MEDIAN 赋值处)

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 PREV_MEDIAN 赋值那一行附近
- 不改 CSS

### 验收标准
引用 BDD 场景 S009: compute_verdict 接收 PREV_MEDIAN 后正确计算中位数和 DECISION；空 results.tsv 时 PREV_MEDIAN 默认为 0，不崩溃
