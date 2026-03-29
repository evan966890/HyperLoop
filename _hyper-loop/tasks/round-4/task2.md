## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] auto_decompose heredoc 中 `\$f` 转义错误，导致上一轮评分无法注入拆解 prompt

在 `auto_decompose` 函数（L703-786）中，heredoc `<<DPROMPT`（非引号形式）会展开变量。但 L727-729 中的 for 循环：

```bash
for f in "${PROJECT_ROOT}/_hyper-loop/scores/round-$((ROUND-1))"/*.json; do
    [[ -f "\$f" ]] && echo "$(basename "\$f"): $(cat "\$f" 2>/dev/null)"
done
```

`\$f` 是字面字符串 `$f`，不是循环变量的值。导致：
1. `[[ -f "\$f" ]]` 测试的是字面文件 `$f`，永远 false
2. `basename "\$f"` 和 `cat "\$f"` 同理无法工作
3. Claude 拆解任务时完全看不到上一轮各 Reviewer 的评分详情

### 相关文件
- scripts/hyper-loop.sh (L712-753, 特别是 L725-730)

### 约束
- 只修 scripts/hyper-loop.sh 中 `auto_decompose` 函数的 heredoc 部分
- 方案：将评分注入逻辑提到 heredoc 之前，用变量存储已拼装好的文本，heredoc 中直接引用该变量
- 不改 CSS

### 验收标准
- S002: auto_decompose 生成的 prompt 应包含上一轮评分 JSON 内容（当评分文件存在时）
- 用 `bash -n scripts/hyper-loop.sh` 验证语法无误
