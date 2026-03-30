## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] 工作副本 scripts/hyper-loop.sh 被 `script` 命令覆盖，仅 43 字节。同时根目录下存在 `started` 文件（`script` 会话产物）需清理。

当前工作副本内容为 `Script started on Mon Mar 30 07:00:32 2026`，不是有效 bash 脚本。这导致后续所有轮次的 `BUILD_CMD="bash -n scripts/hyper-loop.sh"` 对一个空壳文件做语法检查，永远通过但毫无意义。

### 相关文件
- scripts/hyper-loop.sh （整个文件需从 git HEAD 恢复）
- started （根目录垃圾文件，需删除）

### 约束
- 执行 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复工作副本
- 删除根目录下的 `started` 文件
- 不改动脚本逻辑，只恢复文件

### 验收标准
- scripts/hyper-loop.sh 恢复为 987 行的完整脚本
- `bash -n scripts/hyper-loop.sh` PASS
- 根目录下不存在 `started` 文件
- 引用 BDD 场景 S001（脚本能正常启动循环）
