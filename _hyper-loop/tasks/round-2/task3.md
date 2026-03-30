## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件，特别是 bdd-specs.md 中 S008 场景。

### 问题
[P1] reviewer-c 的 codex 命令同时通过 stdin pipe 和命令行参数传入 prompt

位置: scripts/hyper-loop.sh L468
```
echo "$REVIEW_PROMPT" | timeout 300 codex exec -a never "$REVIEW_PROMPT"
```

问题: prompt 同时通过 stdin 管道和命令行参数 `"$REVIEW_PROMPT"` 传入。`codex exec` 的行为取决于它优先读哪个输入源，可能导致 prompt 被截断、重复、或忽略。对比 reviewer-a (L454) 和 reviewer-b (L461) 都只用 stdin 管道传入。

### 相关文件
- scripts/hyper-loop.sh (L467-471) — reviewer-c 的 codex 启动块

### 约束
- 只修 L468 的 codex 命令调用方式
- 保持与 reviewer-a/reviewer-b 一致的 stdin pipe 模式
- `codex exec -a never` 后面不要再传 prompt 参数，只从 stdin 读取
- 不改 CSS

### 验收标准
- S008: 3 个 Reviewer 都能正常启动并产出评分 JSON
- reviewer-c 的 prompt 传入方式与 reviewer-a/b 保持一致（仅 stdin pipe）
