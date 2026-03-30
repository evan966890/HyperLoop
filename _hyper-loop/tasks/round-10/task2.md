## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `PREV_MEDIAN` 空串导致 Python 崩溃：当 results.tsv 存在但为空（0 字节）时，`tail -1 | cut -f2` 返回空串（exit 0），`|| echo 0` 不会触发。随后 Python `float("")` 抛 ValueError，`set -e` 下脚本直接崩溃。影响两处：line 624-625（cmd_round）和 line 849-850（cmd_loop）。这直接违反"无人值守跑 50 轮不崩溃"的核心目标。

### 相关文件
- scripts/hyper-loop.sh (623-626, 848-851)

### 修复方向
在赋值后立即加默认值保护：
```bash
PREV_MEDIAN=$(tail -1 "${PROJECT_ROOT}/_hyper-loop/results.tsv" | cut -f2 || echo 0)
PREV_MEDIAN=${PREV_MEDIAN:-0}
```
或改用 `-s`（文件非空）代替 `-f`（文件存在）：
```bash
if [[ -s "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
```

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 两处 PREV_MEDIAN 赋值都要修

### 验收标准
引用 BDD 场景 S009：compute_verdict 被调用 → verdict.env 可以被安全读取（不崩 bash）
- results.tsv 为空文件时，PREV_MEDIAN 回退为 0，脚本不崩溃
- results.tsv 正常有数据时，行为不变
