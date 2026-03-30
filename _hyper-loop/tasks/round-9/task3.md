## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Tester P0 否决检测存在严重误报，即使 Tester 报告全 PASS 也触发 REJECTED_TESTER_P0。

line 556 的检测逻辑：
```python
tester_p0 = "P0" in text and ("bug" in text.lower() or "fail" in text.lower())
```

Round 8 的 Tester 报告中：
- "### S011: Tester P0 否决 — PASS" 包含字面 "P0"（这是 BDD 场景标题，描述 P0 veto 功能本身）
- "### S010: 一票否决 (score < 4.0) — PASS" 标题也有 P0 附近内容
- "merge_writers 视 timeout 为 failed 跳过" 包含 "fail"
- 两个条件都匹配 → `tester_p0=True` → REJECTED_TESTER_P0

修复方向：P0 检测应该只匹配 Tester 实际报告的 bug，不匹配 BDD 场景标题中的描述性文字。建议：
- 用正则匹配 `\[P0\]` 或 `P0 bug` 或 `P0:` 等带标点/中括号的格式（Tester 模板要求的报告格式）
- 排除 `### S0` 开头的场景标题行

### 相关文件
- scripts/hyper-loop.sh (line 539-584, compute_verdict 函数内的 Python heredoc, 重点 line 552-556)

### 约束
- 只修 scripts/hyper-loop.sh 中 `compute_verdict` 函数内的 PYVERDICT heredoc
- 只改 `tester_p0` 检测逻辑（line 552-556）
- 不改 veto、max_diff 等其他 verdict 判断逻辑
- 不改 CSS

### 验收标准
引用 BDD 场景 S011（Tester P0 否决）
- 当报告只是在场景标题中出现 "P0"（如 "S011: Tester P0 否决 — PASS"）但没有真正的 P0 bug 时：`tester_p0=False`
- 当报告实际列出 "[P0] xxx bug" 或 "**P0**: xxx" 或 "P0 bug: xxx" 时：`tester_p0=True`
- `bash -n scripts/hyper-loop.sh` 语法检查通过
