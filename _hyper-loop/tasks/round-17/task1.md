## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] scripts/hyper-loop.sh 工作副本被 `script` 命令覆写，只剩 1 行 `Script started on Mon Mar 30 04:15:42 2026`。HEAD 版本 987 行完好。同时根目录存在一个 `started` 文件（`script` 命令残留），需清理。

这是第一优先级——脚本文件不可用意味着整个循环无法运行，且 `BUILD_CMD=bash -n scripts/hyper-loop.sh` 验证的是损坏文件。

### 相关文件
- scripts/hyper-loop.sh（需从 HEAD 恢复全部内容）
- started（根目录，需删除）

### 修复步骤
1. 在 worktree 中执行 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复 987 行完整版本
2. 验证 `wc -l scripts/hyper-loop.sh` 输出 987
3. 验证 `bash -n scripts/hyper-loop.sh` 通过
4. 如果根目录存在 `started` 文件，删除它

### 约束
- 只修指定文件
- 不改脚本逻辑，仅恢复

### 验收标准
引用 BDD 场景 S001: `bash -n scripts/hyper-loop.sh` 通过且文件完整
