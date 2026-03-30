## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] cmd_status() 重复定义，第一个是死代码

cmd_status() 在 line 670-676 定义了简版，在 line 930-942 定义了增强版（含最佳轮次显示）。Bash 中后定义覆盖前定义，第一个是死代码，增加维护混淆风险。

### 相关文件
- scripts/hyper-loop.sh (line 670-676, 第一个 cmd_status 定义)

### 约束
- 只删除 line 670-676 的第一个 cmd_status 定义（含空行）
- 保留 line 930-942 的增强版定义不动
- 不改 CSS

### 验收标准
- 脚本中只有一个 cmd_status 定义（line 930 附近的增强版）
- `bash -n scripts/hyper-loop.sh` 语法检查通过
- `hyper-loop.sh status` 命令正常工作，显示最佳轮次信息
- 引用 BDD 场景 S001（脚本不崩溃）
