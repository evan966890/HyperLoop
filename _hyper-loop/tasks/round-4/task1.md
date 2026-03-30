## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1 → 实际影响 P0] reviewer-c (codex) 命令同时通过 stdin pipe 和 CLI 参数传递 prompt，导致 codex 始终失败 fallback 3 分。

当前代码 line 468:
```bash
echo "$REVIEW_PROMPT" | timeout 300 codex exec -a never "$REVIEW_PROMPT" 2>/dev/null
```
问题：`codex exec` 从 CLI 参数读取指令（不读 stdin），stdin pipe 被浪费。当 REVIEW_PROMPT 很长时，CLI 参数可能超过 ARG_MAX 限制导致 "Argument list too long"。

这是连续 3 轮 REJECTED_VETO (median=3.0) 的根因之一：reviewer-c 始终 fallback 3 分。

同时将 reviewer-a (gemini) 和 reviewer-c (codex) 的「工具不可用」fallback 分从 3 改为 5。理由：不可用的 reviewer 不应触发 VETO（< 4.0），5 分是中性分不影响有效 reviewer 的合议。当前 line 477-479 的 fallback 逻辑对所有 reviewer 统一给 3 分，这会让不可用工具误触发 VETO。

### 相关文件
- scripts/hyper-loop.sh (line 467-470, line 477-482)

### 修复方案
1. 去掉 reviewer-c (line 468) 的 CLI 参数 `"$REVIEW_PROMPT"`，改为仅 stdin pipe 传参：
   `echo "$REVIEW_PROMPT" | timeout 300 codex exec -a never 2>/dev/null`
2. 在 reviewer-a 和 reviewer-c 的 subshell 开头加命令存在性检查，不可用时写 fallback JSON（score=5）
3. line 479 的统一 fallback 分从 3 改为 5

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 不改 reviewer-b (claude) 的逻辑
- 保持 3 个 reviewer 的并行结构和 timeout 300

### 验收标准
引用 BDD 场景 S008: 3 个 Reviewer 能正确启动，JSON 包含 score 字段，无输出时 fallback（现在给 5 分而非 3 分）
引用 BDD 场景 S010: 真正的低分（< 4.0）仍能触发 VETO
