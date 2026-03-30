## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] 工作副本 `scripts/hyper-loop.sh` 被 Unix `script` 命令覆盖，当前仅 43 字节（内容为 "Script started on Mon Mar 30 07:00:32 2026"）。脚本完全不可运行。需要从 git HEAD (67e82df) 恢复完整的 987 行脚本。

操作：执行 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复工作副本。

同时检查项目根目录是否有 `started` 或 `typescript` 等 `script` 命令残留文件，如有则删除。
### 相关文件
- scripts/hyper-loop.sh (全文件 — 被覆盖)
- started (项目根目录残留文件，如存在则删除)
### 约束
- 只恢复 scripts/hyper-loop.sh 到 git HEAD 版本
- 删除 `script` 命令残留文件
- 不做任何其他代码修改
### 验收标准
- `bash -n scripts/hyper-loop.sh` 通过
- `wc -l scripts/hyper-loop.sh` 约为 987 行
- 引用 BDD 场景 S001（脚本可启动运行）
