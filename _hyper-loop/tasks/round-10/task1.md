## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] Tester P0 误拒：`compute_verdict` 中 `tester_p0` 判定逻辑使用全局子串匹配（`"P0" in text and ("bug" in text.lower() or "fail" in text.lower())`），导致报告中出现 "0 个 P0 bug"、"P0: none"、"No P0 bugs found" 等**否定性描述**时仍然触发 REJECTED_TESTER_P0。这是 9 轮中 7 轮被误拒的根本原因，是当前最严重的阻塞问题。

### 相关文件
- scripts/hyper-loop.sh (525-534)

### 修复方向
将全局子串匹配替换为精确的结构化匹配。Tester 报告的 Bug 以 `### P0` 或 `### P0-` 开头作为标题行。正确做法：
1. 用正则 `re.search(r'^###\s+P0', text, re.MULTILINE)` 检测是否存在 P0 级别 Bug 标题
2. 或者检查 "## Bugs Found" section 下是否有 P0 开头的子标题
3. 确保 "0 个 P0"、"P0: 无"、BDD 表格中出现的 "P0" 字样不会误触发

### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- Python 代码嵌在 heredoc 中，注意缩进和引号转义
- 不能改变 verdict.env 的输出格式

### 验收标准
引用 BDD 场景 S011：Given Tester 报告包含 "P0" 和 "fail" → DECISION = REJECTED_TESTER_P0
- 当报告确实有 `### P0-1: xxx bug` 时，仍然正确触发 REJECTED_TESTER_P0
- 当报告仅在统计/否定语境中提到 "P0"（如 "0 个 P0 bug"、"No P0 issues"）时，不触发
