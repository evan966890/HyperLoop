## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] scripts/hyper-loop.sh 工作副本被 `script` 命令覆盖，仅剩 43 字节

工作副本内容为 `Script started on Mon Mar 30 07:00:32 2026`（43 字节），987 行脚本仅存在于 git HEAD。系统从工作目录运行时完全不工作。

### 相关文件
- scripts/hyper-loop.sh (整个文件)

### 约束
- 执行 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复工作副本
- 恢复后运行 `bash -n scripts/hyper-loop.sh` 确认语法正确
- 不做其他修改

### 验收标准
引用 BDD 场景 S001（loop 命令启动死循环）：
- `scripts/hyper-loop.sh` 工作副本恢复为 987 行完整脚本
- `bash -n scripts/hyper-loop.sh` 退出码为 0
