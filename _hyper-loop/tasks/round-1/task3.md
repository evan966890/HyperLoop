## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] cmd_status() 函数定义了 3 次，造成死代码；cmd_round 缺少 archive_round 调用。

问题 A: cmd_status 重复定义
- 第 670-676 行: 第一个定义（简版）
- 第 932-944 行: 第二个定义（完整版，含最佳轮次）
- 后定义覆盖前定义，第 670 行版本是死代码
- Reviewer 审查时会因死代码扣分

问题 B: cmd_round 缺少 archive_round
- cmd_loop 在每轮结束时调 archive_round（第 892 行），保存 git-sha.txt 等
- cmd_round（第 607-668 行）只调 cleanup_round，没调 archive_round
- S013 回退功能依赖 archive/round-N/git-sha.txt 存在
- 混用 round 和 loop 命令时回退功能会断

### 相关文件
- scripts/hyper-loop.sh (第 670-676 行: 重复的 cmd_status 第一个定义)
- scripts/hyper-loop.sh (第 607-668 行: cmd_round 函数)

### 修复方案
1. 删除第 670-676 行的第一个 cmd_status() 定义
2. 在 cmd_round 的 `cleanup_round "$ROUND"`（约第 661 行）前加 `archive_round "$ROUND"`

### 约束
- 只修 scripts/hyper-loop.sh
- 只删第一个 cmd_status + 给 cmd_round 加 archive_round 调用
- 不改 cmd_loop 或第二个 cmd_status

### 验收标准
引用 BDD 场景 S001: 循环跑满 N 轮后正常退出
引用 BDD 场景 S013: archive/round-N/git-sha.txt 存在时代码可回退
验证：`bash -n scripts/hyper-loop.sh` 通过；`grep -c 'cmd_status()' scripts/hyper-loop.sh` 应为 1
