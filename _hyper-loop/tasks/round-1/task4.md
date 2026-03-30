## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] 两个独立问题，都在 scripts/hyper-loop.sh 中：

**问题 A: `cmd_status` 重复定义**
`cmd_status` 函数在脚本中定义了两次：
- 第一次约在行 670（简版，只有 tmux + results.tsv）
- 第二次约在行 930（完整版，额外有"最佳轮次"输出）
Bash 用最后定义的覆盖前面的，所以第一个是死代码。应删除第一个定义。

**问题 B: `cmd_round` 缺少 `archive_round` 调用**
`cmd_loop` 在每轮结束时调用 `archive_round "$ROUND"`（约行 890），会保存 bdd-specs、scores、report、verdict.env、git-sha.txt 到 archive 目录。
但 `cmd_round`（单轮模式）没有调用 `archive_round`，只调了 `cleanup_round`。
这意味着：
- 单轮模式下 `archive/round-N/git-sha.txt` 不会被写入
- S013（连续 5 轮失败自动回退）依赖 `archive/round-N/git-sha.txt` 存在
- 如果用户混用 `round` 和 `loop` 命令，回退功能会断

### 相关文件
- scripts/hyper-loop.sh (行 607-668, cmd_round 函数; 行 670-676, 第一个 cmd_status)

### 修复方案
1. 删除第一个 `cmd_status` 定义（约行 670-676）
2. 在 `cmd_round` 的 `cleanup_round "$ROUND"` 之前加入 `archive_round "$ROUND"`

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 cmd_loop 或其他函数
- 不改 CSS

### 验收标准
引用 BDD 场景 S013: archive/round-N/git-sha.txt 存在且得分最高时代码可回退
引用 BDD 场景 S001: 循环跑满 N 轮后正常退出
验证：`bash -n scripts/hyper-loop.sh` 语法通过；`grep -c 'cmd_status()' scripts/hyper-loop.sh` 应为 1
