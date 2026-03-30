## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] scripts/hyper-loop.sh 工作副本被覆写为 1 行（`Script started on Mon Mar 30 07:00:32 2026`），疑似 `script` 命令输出误重定向。脚本完全无法执行。

### 相关文件
- scripts/hyper-loop.sh（整个文件——需要从 git HEAD 恢复）

### 约束
- 只修指定文件
- 不改 CSS
- 执行 `git checkout HEAD -- scripts/hyper-loop.sh` 恢复 HEAD 版本（987 行）
- 恢复后用 `bash -n scripts/hyper-loop.sh` 验证语法正确
- 不要手动编辑内容，只做恢复操作

### 验收标准
引用 BDD 场景 S001: `bash -n` 语法检查通过，脚本可被 bash 正常解析
