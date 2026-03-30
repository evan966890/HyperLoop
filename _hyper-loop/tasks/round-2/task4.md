## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `cmd_loop()` 启动时 BEST_ROUND=0, BEST_MEDIAN=0，不从 results.tsv 读取历史最佳轮次。脚本崩溃重启后，连续 5 轮失败的回退机制 (S013) 找不到可回退的目标（BEST_ROUND=0 导致跳过回退）。

需要在 `cmd_loop()` 的 while 循环开始前，遍历 results.tsv 找到历史最高中位数对应的轮次，初始化 BEST_ROUND 和 BEST_MEDIAN。

### 相关文件
- scripts/hyper-loop.sh (L821-823, BEST_ROUND/BEST_MEDIAN 初始化位置)
- scripts/hyper-loop.sh (L897-907, 回退逻辑，依赖 BEST_ROUND > 0)

### 约束
- 只修 scripts/hyper-loop.sh
- 在 L823 之后、L825 (while 循环) 之前插入初始化逻辑
- 从 results.tsv 解析（格式：轮次\t中位数\t分数列表\t决定），取中位数最高的轮次
- 不改 CSS

### 验收标准
- S013: 脚本重启后仍能正确回退到历史最佳轮次
- BEST_ROUND 和 BEST_MEDIAN 在 loop 启动时从 results.tsv 正确初始化
