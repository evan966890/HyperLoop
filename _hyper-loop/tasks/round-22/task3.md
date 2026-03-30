## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] S013 回退逻辑不跨 loop 重启——`BEST_ROUND` 和 `BEST_MEDIAN` 只在当次 `cmd_loop` 内存中跟踪。脚本崩溃重启后这两个变量重置为 0，使得连续 5 轮失败回退条件 `$BEST_ROUND -gt 0` 永远不满足。

BDD S013 要求：从 `archive/round-N/git-sha.txt` 找最高分轮次回退。

### 相关文件
- scripts/hyper-loop.sh（第 846-848 行附近，`cmd_loop` 函数开头初始化 `BEST_ROUND=0` 和 `BEST_MEDIAN=0` 处）

### 约束
- 只修指定文件
- 不改 CSS
- 在 `cmd_loop` 的 `BEST_ROUND=0` / `BEST_MEDIAN=0` 初始化之后，添加从 `results.tsv` + `archive/` 恢复逻辑：
  1. 遍历 `results.tsv`，找出 median 最高且对应 `archive/round-N/git-sha.txt` 存在的轮次
  2. 用该轮次的 round 和 median 设置 `BEST_ROUND` 和 `BEST_MEDIAN`
- 不要改动回退触发逻辑本身（第 924-935 行附近），只改初始化部分
- 修改后 `bash -n scripts/hyper-loop.sh` 必须通过

### 验收标准
引用 BDD 场景 S013: 脚本重启后，`BEST_ROUND` 和 `BEST_MEDIAN` 能从 `results.tsv` 和 `archive/` 目录恢复，连续 5 轮失败时能正确回退到最佳轮次。
