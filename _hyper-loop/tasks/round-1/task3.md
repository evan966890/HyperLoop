## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] `run_reviewers` 中 reviewer-c (Codex) 的 CLI 调用有语法问题：

```bash
echo "$REVIEW_PROMPT" | timeout 300 codex exec -a never "$REVIEW_PROMPT" 2>/dev/null | \
  python3 -c "$EXTRACT_PY" > "${SCORES_DIR}/reviewer-c.json" 2>/dev/null
```

问题分析：
1. `echo "$REVIEW_PROMPT"` 管道传给 `codex exec`，但 `codex exec` 的 prompt 是位置参数，不从 stdin 读取
2. `codex exec` 的 stdout 才会通过管道传给 `python3`，而不是 `echo` 的 stdout
3. 如果 `$REVIEW_PROMPT` 过长（包含 stat 输出），作为命令行参数可能超出 ARG_MAX 限制
4. `-a never` 应改为与其他 codex 调用一致的 `--full-auto` 或 `--dangerously-bypass-approvals-and-sandbox`

对比 reviewer-a/b 的正确写法（stdin → `-p -`）：
- reviewer-a: `echo "$REVIEW_PROMPT" | timeout 300 gemini -y -p - ...`
- reviewer-b: `echo "$REVIEW_PROMPT" | timeout 300 claude --dangerously-skip-permissions -p - ...`

### 相关文件
- scripts/hyper-loop.sh (行 467-471, reviewer-c 的子 shell)

### 修复方案
将 reviewer-c 改为写临时文件 + codex 读文件模式（codex 不支持 `-p -`）：
```bash
(
    local CODEX_PROMPT_FILE="/tmp/hyper-loop-codex-review-r${ROUND}.txt"
    echo "$REVIEW_PROMPT" > "$CODEX_PROMPT_FILE"
    timeout 300 codex --dangerously-bypass-approvals-and-sandbox --quiet "$CODEX_PROMPT_FILE" 2>/dev/null | \
      python3 -c "$EXTRACT_PY" > "${SCORES_DIR}/reviewer-c.json" 2>/dev/null
    echo "  ✓ reviewer-c (codex) done: ..."
) &
```
如果 codex 命令不可用或 CLI 参数不确定，应加降级逻辑（fallback 给默认分 3）。

### 约束
- 只修 scripts/hyper-loop.sh 的 run_reviewers 函数中 reviewer-c 部分
- 不改 reviewer-a 和 reviewer-b
- 不改 CSS

### 验收标准
引用 BDD 场景 S008: 3 个 Reviewer 各自生成 scores JSON，JSON 包含 "score" 字段
验证：`bash -n scripts/hyper-loop.sh` 语法通过
