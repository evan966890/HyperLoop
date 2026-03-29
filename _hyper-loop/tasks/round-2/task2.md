## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] `BUILD_FAILED` 路径写入的 `verdict.env` 缺少 `SCORES` 字段，且 shell 变量 `MEDIAN` 未重置。

具体位置有两处：
1. `cmd_round()` 第 653-654 行：只写 `DECISION=BUILD_FAILED` 和 `MEDIAN=0`，缺少 `SCORES=""`
2. `cmd_loop()` 第 876-877 行：同样缺少 `SCORES=""`

`record_result()` 第 616 行 `grep '^SCORES='` 得到空串，导致 `results.tsv` 的 scores 列为空。

此外，`cmd_loop()` 的 BUILD_FAILED 分支没有设置 shell 变量 `MEDIAN=0`，
导致第 928 行的 `>= 8.0` 检查可能使用上一轮的旧值，造成逻辑错误。

### 相关文件
- scripts/hyper-loop.sh (第 651-658 行, `cmd_round` BUILD_FAILED 路径)
- scripts/hyper-loop.sh (第 874-880 行, `cmd_loop` BUILD_FAILED 路径)

### 约束
- 只修上述两处 BUILD_FAILED 代码块
- 保持 verdict.env 格式与 `compute_verdict` 输出一致（6 个字段）
- 不改 CSS

### 验收标准
- S009: verdict.env 包含完整字段（DECISION, MEDIAN, MAX_DIFF, VETO, TESTER_P0, SCORES）
- S012: verdict.env 可被 `record_result` 的 grep 正确读取，results.tsv 无空列
