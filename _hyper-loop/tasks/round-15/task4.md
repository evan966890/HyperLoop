## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] cmd_status() 函数定义重复 — 第 697 行和第 957 行各有一个定义

`cmd_status()` 被定义了两次：
1. 第一个定义在约第 697-704 行（简单版，在 auto_decompose 前面）
2. 第二个定义在约第 957-970 行（增强版，含"最佳轮次"显示）

Bash 中后定义覆盖前定义，所以第一个定义永远不会被执行。应删除第一个多余定义。

### 相关文件
- scripts/hyper-loop.sh (第 697-704 行，第一个 cmd_status 定义)

### 约束
- 只删除 scripts/hyper-loop.sh 中第一个 cmd_status() 定义（约第 697-704 行）
- 保留第二个定义（约第 957 行之后的增强版）不动
- 不改动任何其他函数

### 验收标准
引用 BDD 场景 S001: `bash -n scripts/hyper-loop.sh` 语法检查通过，且 `grep -c 'cmd_status()' scripts/hyper-loop.sh` 输出 1（只有一个定义）
