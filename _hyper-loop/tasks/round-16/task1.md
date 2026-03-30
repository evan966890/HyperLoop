## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] **工作副本 scripts/hyper-loop.sh 被 `script` 命令覆写，仅 43 字节**

磁盘上的 `scripts/hyper-loop.sh` 内容为 `Script started on Mon Mar 30 04:15:42 2026`，疑似 `script scripts/hyper-loop.sh` 误操作。Git HEAD 版本 (987 行) 完好。脚本完全无法执行。

修复方法：从 git HEAD 恢复工作副本。

### 相关文件
- scripts/hyper-loop.sh (整个文件)
### 约束
- 执行 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复
- 恢复后验证文件行数 >= 980 行
- 不改动任何其他文件
### 验收标准
- 恢复后 `wc -l scripts/hyper-loop.sh` >= 980
- `bash -n scripts/hyper-loop.sh` 返回 exit 0
- 引用 BDD 场景 S001（loop 命令启动死循环 — 脚本必须可执行）
