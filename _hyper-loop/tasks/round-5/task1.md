## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `auto_decompose` heredoc 中 `\$f` 变量不展开（第 728-729 行）

在 `<<DPROMPT` heredoc 内部，`\$f` 被转义为字面量 `$f`，导致 for 循环里的 `[[ -f "\$f" ]]` 和 `basename "\$f"` 操作的是字符串 `$f` 而非循环变量的值。结果是 decompose prompt 中"上一轮评分"部分始终为空，拆解器看不到上一轮的具体评分，降级了拆解质量。

根因：heredoc 分界符 `<<DPROMPT` 不带引号，bash 会展开 `$` 变量；但 `\$f` 又用反斜杠阻止了展开，导致字面量 `$f` 被写入。

### 相关文件
- scripts/hyper-loop.sh (第 725-730 行，auto_decompose 函数)

### 修复方案
将评分信息在 heredoc 外部预先构建到一个变量中，然后在 heredoc 内部用 `${SCORES_SECTION}` 插入。这样既保留 heredoc 内其他变量的展开，又确保 for 循环在当前 shell 正确执行。

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 不改变 decompose prompt 的语义和输出格式

### 验收标准
引用 BDD 场景 S002：auto_decompose 生成任务文件 — 确保上一轮评分信息能正确出现在 decompose prompt 中
