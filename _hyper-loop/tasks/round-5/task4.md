## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `cmd_status` 函数被定义了两次（line 670-676 和 line 932-943），第二个定义覆盖第一个，第一个是死代码。虽无功能影响，但代码冗余会干扰后续 Writer 理解脚本结构，且 Reviewer 会因"代码可读性"扣分。
### 相关文件
- scripts/hyper-loop.sh (line 670-676: 第一个 cmd_status 定义——需删除)
- scripts/hyper-loop.sh (line 932-943: 第二个 cmd_status 定义——保留)
### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 删除 line 670-676 的第一个 `cmd_status` 函数定义（含花括号和内容）
- 保留 line 932-943 的第二个定义不动
### 验收标准
`grep -c 'cmd_status()' scripts/hyper-loop.sh` 返回 1（只有一个定义）
代码可读性提升，消除 Reviewer 扣分项
