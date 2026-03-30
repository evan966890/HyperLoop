## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] auto_decompose 的 heredoc 中变量转义错误 — 上一轮评分无法注入 decompose prompt

`auto_decompose()` 用非引号 heredoc (`<<DPROMPT`) 生成拆解 prompt，其中嵌套了
`$(for f in ...)` 命令替换。在 heredoc 内部用 `\$f` 试图延迟 `$f` 的展开，
但在嵌套的 `$(basename "\$f")` 和 `$(cat "\$f")` 中，`\$f` 变成了字面量 `$f`，
再被内层 `$(...)` 命令替换执行时，`$f` 已经不在 for 循环作用域内，导致为空。

结果：拆解 prompt 中缺少上一轮评分信息，任务拆解器看不到之前哪里出了问题。

修复方案：将 heredoc 中嵌套命令替换部分提取为函数，在 heredoc 外部调用并将结果存入变量，
然后在 heredoc 中直接引用变量。

### 相关文件
- scripts/hyper-loop.sh (行 706-789, auto_decompose 函数)

### 约束
- 只修 `auto_decompose()` 函数
- 保持 claude -p 调用方式不变
- 不改 CSS
- 不改其他函数

### 验收标准
- decompose prompt 中正确包含上一轮各 reviewer 的评分 JSON 内容
- `bash -n scripts/hyper-loop.sh` 语法通过
- 引用 BDD 场景 S002（auto_decompose 生成任务文件）
