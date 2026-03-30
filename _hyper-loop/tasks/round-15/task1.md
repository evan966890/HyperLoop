## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] 工作副本被覆盖 — scripts/hyper-loop.sh 磁盘文件仅 43 字节

磁盘上的 `scripts/hyper-loop.sh` 被 `script` 命令的输出覆盖，内容为 `Script started on Mon Mar 30 04:15:42 2026`。
git HEAD 版本有 987 行是完整的，但工作副本已损坏。

**必须先恢复工作副本**，后续所有任务的修改才能生效。

执行：`git checkout HEAD -- scripts/hyper-loop.sh`

恢复后验证：`wc -l scripts/hyper-loop.sh` 应输出 987 行，`bash -n scripts/hyper-loop.sh` 应通过。

### 相关文件
- scripts/hyper-loop.sh (整个文件，当前仅 43 字节需恢复为 987 行)

### 约束
- 只操作 scripts/hyper-loop.sh
- 使用 git checkout 恢复，不要手动重写
- 恢复后不要做任何其他修改（其他 task 负责修 bug）

### 验收标准
引用 BDD 场景 S001: `bash -n scripts/hyper-loop.sh` 通过，且文件行数 >= 980 行
