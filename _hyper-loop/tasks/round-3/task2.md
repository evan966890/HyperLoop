## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] reviewer-c 的 codex 命令同时通过 stdin 管道和命令行参数传递 prompt：
```bash
echo "$REVIEW_PROMPT" | timeout 300 codex exec -a never "$REVIEW_PROMPT"
```
`codex exec` 优先读取命令行参数，stdin 被忽略。且长 prompt 作为命令行参数可能超出 ARG_MAX 限制导致 reviewer-c 失败，触发 fallback 给 3 分（拉低总评分导致 REJECTED_VETO）。
### 相关文件
- scripts/hyper-loop.sh (L468, run_reviewers 函数中 reviewer-c 的启动命令)
### 修复方案
去掉命令行参数，改为纯 stdin 管道模式（与 reviewer-a 和 reviewer-b 保持一致）：
```bash
echo "$REVIEW_PROMPT" | timeout 300 codex exec -a never 2>/dev/null | \
```
如果 codex exec 不支持纯 stdin 读取，替代方案是写临时文件：
```bash
local CODEX_PROMPT_FILE="/tmp/hyper-loop-reviewer-c-r${ROUND}.md"
echo "$REVIEW_PROMPT" > "$CODEX_PROMPT_FILE"
timeout 300 codex exec -a never "$(cat "$CODEX_PROMPT_FILE")" 2>/dev/null | \
```
但首选方案是纯 stdin 管道。
### 约束
- 只修改 scripts/hyper-loop.sh 中 run_reviewers 函数的 reviewer-c 部分 (L467-471)
- 不改 reviewer-a 和 reviewer-b 的逻辑
- 不改 CSS
### 验收标准
引用 BDD 场景 S008: 3 个 Reviewer 均正常启动并产出评分 JSON，reviewer-c 不再因参数冲突而 fallback
