## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1-2] `auto_decompose` heredoc 中 `\$f` 变量不展开（第 725-730 行）

`<<DPROMPT` 是非引号 heredoc，bash 会展开变量。但代码中写了 `\$f`，反斜杠导致 `$f` 被转义为字面量，for 循环体输出为空。实测确认：`\$f` 输出空，`$f` 正常。

这导致 decompose prompt 中"上一轮评分"部分始终为空，拆解器无法参考评分，严重降低拆解质量。

### 相关文件
- scripts/hyper-loop.sh (行 725-730)

### 约束
- 只修 scripts/hyper-loop.sh
- 仅修改 heredoc 内的 `\$f` → `$f`（两处：第 728 行的 `[[ -f "\$f" ]]` 和 `$(basename "\$f")` 和 `$(cat "\$f" ...)`）
- 不影响 heredoc 外部逻辑

### 验收标准
引用 BDD 场景 S002: auto_decompose 生成的 prompt 中"上一轮评分"部分应包含实际 JSON 内容（而非空白）
