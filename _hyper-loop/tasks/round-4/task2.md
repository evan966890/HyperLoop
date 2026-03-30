## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] `auto_decompose` 函数的 heredoc 中 `\$f` 阻止变量展开，导致上轮评分无法注入 decompose prompt。

当前代码 line 700-706:
```bash
$(if [[ -d "${PROJECT_ROOT}/_hyper-loop/scores/round-$((ROUND-1))" ]]; then
  echo "## 上一轮评分"
  for f in "${PROJECT_ROOT}/_hyper-loop/scores/round-$((ROUND-1))"/*.json; do
    [[ -f "\$f" ]] && echo "$(basename "\$f"): $(cat "\$f" 2>/dev/null)"
  done
fi)
```

在非引号 heredoc `<<DPROMPT` 中，`\$f` 产生字面量 `$f` 而非循环变量值。`basename "\$f"` 和 `cat "\$f"` 同样无法展开。实际效果是 decompose prompt 中评分信息全部缺失，拆解器看不到上轮反馈。

### 相关文件
- scripts/hyper-loop.sh (line 700-706)

### 修复方案
将评分注入逻辑移到 heredoc 之前。在 heredoc 之前用普通脚本循环生成评分文本到一个变量，然后在 heredoc 中引用该变量：
```bash
local PREV_SCORES=""
if [[ -d "${PROJECT_ROOT}/_hyper-loop/scores/round-$((ROUND-1))" ]]; then
  PREV_SCORES="## 上一轮评分"$'\n'
  for f in "${PROJECT_ROOT}/_hyper-loop/scores/round-$((ROUND-1))"/*.json; do
    [[ -f "$f" ]] && PREV_SCORES+="$(basename "$f"): $(cat "$f" 2>/dev/null)"$'\n'
  done
fi
```
然后在 heredoc 中用 `${PREV_SCORES}` 引用。

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 不改 heredoc 中其他已正常工作的部分
- 确保修改后 `bash -n` 仍然通过

### 验收标准
引用 BDD 场景 S002: auto_decompose 调用时，如果上轮有评分文件，decompose prompt 中能看到实际的评分 JSON 内容（而非字面量 `$f`）
