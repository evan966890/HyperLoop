## 修复任务: TASK-5
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] `cmd_loop()` 中 `DECISION` 和 `MEDIAN` 变量在循环体内未用 `local` 声明，
且在 BUILD_FAILED 分支和正常分支之间不一致地设置，导致变量泄漏到外层作用域。

具体问题：
1. 第 890-891 行：`DECISION` 和 `MEDIAN` 通过 grep 设置，但只在 else 分支（构建成功时）。
   BUILD_FAILED 分支（第 874-880 行）不设置这两个 shell 变量。
2. 如果某轮构建成功（ACCEPTED, median=7.5），下一轮构建失败，
   第 928 行的 `${MEDIAN:-0}` 仍是 7.5（上一轮值），可能误判为达标并退出循环。
3. 第 890-891 行缩进不一致（少了 6 个空格），影响可读性。

### 相关文件
- scripts/hyper-loop.sh (第 874-912 行, `cmd_loop` 循环体的 if/else 块)
- scripts/hyper-loop.sh (第 928 行, median >= 8.0 检查)

### 约束
- 只修 `cmd_loop` 函数中上述循环体部分
- 在每轮循环开始时重置 DECISION="" MEDIAN=0
- 修正第 890-891 行缩进
- 不改 CSS

### 验收标准
- S001: 循环跑满后正常退出
- S013: 连续失败时不会因 MEDIAN 泄漏误判达标
- 评估契约：代码可读性
