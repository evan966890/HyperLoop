## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] scripts/hyper-loop.sh 工作副本被 Unix `script` 命令输出覆盖，仅剩 1 行 `Script started on Mon Mar 30 07:00:32 2026`。同时项目根目录存在 `started` 文件（`script` 命令产物）。committed HEAD 版本（987 行）完好，但工作副本已被毁坏，导致后续轮次的所有构建检查 (`bash -n`) 误判为通过。
### 相关文件
- scripts/hyper-loop.sh (整个文件 — 需从 HEAD 恢复)
- started (项目根目录 — 需删除)
### 约束
- 执行 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复脚本
- 删除根目录的 `started` 文件
- 不改动脚本任何逻辑
- 不改 CSS
### 验收标准
引用 BDD 场景 S001: 恢复后 `wc -l scripts/hyper-loop.sh` 应返回 987 行，`bash -n scripts/hyper-loop.sh` 通过，`started` 文件不再存在
