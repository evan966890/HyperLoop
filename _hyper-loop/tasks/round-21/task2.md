## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] cmd_status() 函数重复定义。Line 697 有一个简版定义，Line 957 有一个完整版定义。bash 不报错但第一个定义成为死代码，逻辑混乱。

### 相关文件
- scripts/hyper-loop.sh (Line 697-703: 第一个 cmd_status 定义)

### 约束
- 只删除 Line 697-703 的第一个 cmd_status() 定义（6-7 行）
- 保留 Line 957 附近的第二个完整版定义不动
- 不改动其他任何代码

### 验收标准
- `grep -c 'cmd_status()' scripts/hyper-loop.sh` 输出 1（只有一个定义）
- `bash -n scripts/hyper-loop.sh` PASS
- 引用 BDD 场景 S001（脚本能正常启动，cmd_status 命令正常工作）
