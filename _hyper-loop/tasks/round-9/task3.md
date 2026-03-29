## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Tester P0 否决检测存在严重误报，导致即使 Tester 报告全 PASS 也触发 REJECTED_TESTER_P0

line 553 的检测逻辑：
```python
tester_p0 = "P0" in text and ("bug" in text.lower() or "fail" in text.lower())
```

Round 8 的 Tester 报告中：
- "### S011: Tester P0 否决 — PASS" 包含字面 "P0"（这是 BDD 场景标题，描述 P0 veto 功能本身）
- "merge_writers 视 timeout 为 failed 跳过" 包含 "fail"
- 两个条件都匹配 → `TESTER_P0=True` → 误报

修复方向：P0 检测应该匹配 Tester 实际报告的 bug，而不是场景标题。建议改为：
- 匹配 `[P0]` 或 `P0 bug` 或 `P0:` 等带标点的格式
- 或者只在 "bug" 段落/列表中匹配，不在 "### S0XX" 标题中匹配

### 相关文件
- scripts/hyper-loop.sh (line 549-553)

### 约束
- 只修 scripts/hyper-loop.sh 中 compute_verdict 函数内的 tester_p0 检测逻辑
- 不改其他 verdict 判断逻辑（veto、max_diff 等）

### 验收标准
引用 BDD 场景 S011（Tester P0 否决）
- 当报告只是描述 S011 场景（标题含 "P0"）但没有真正的 P0 bug 时，`TESTER_P0=False`
- 当报告实际列出 "[P0] xxx bug" 或 "P0 bug: xxx" 时，`TESTER_P0=True`
