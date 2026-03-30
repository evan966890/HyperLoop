## 修复任务: TASK-1
### 上下文
先读 _hyper-loop/context/ 下所有文件，理解项目结构和脚本职责。
### 问题
[P0-1] scripts/hyper-loop.sh 工作副本被 `script` 命令覆盖，文件内容只有 1 行 `Script started on Mon Mar 30 04:15:42 2026`，脚本完全无法执行。

修复方法：执行 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复 git HEAD 版本（987 行）。

注意：恢复后需验证文件完整性（`bash -n scripts/hyper-loop.sh` 通过，行数 >= 980）。
### 相关文件
- scripts/hyper-loop.sh (整个文件——需从 git HEAD 恢复)
### 约束
- 只恢复 scripts/hyper-loop.sh，不改其他文件
- 恢复后运行 `bash -n` 验证语法正确
### 验收标准
引用 BDD 场景 S001: `bash -n` 通过，脚本可正常启动
