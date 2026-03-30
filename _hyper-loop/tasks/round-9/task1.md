## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] compute_verdict 的 Tester P0 检测存在严重误报——过去 8 轮中 6 轮因此被错误拒绝

`compute_verdict` 中 S011 的 P0 检测逻辑 (L529) 使用简单子串匹配：
```python
tester_p0 = "P0" in text and ("bug" in text.lower() or "fail" in text.lower())
```

当 Tester 报告包含以下任何一种情况时均会误报：
- "0 个 P0 bug"（表示零个 P0 bug）→ 匹配 "P0" + "bug"
- "**0 个 P0 bug**" → 同上
- "S011: Tester P0 否决 — PASS" → 匹配 "P0" + "fail"（PASS 行之前的其他行有 fail）
- BDD 场景标题本身含 "P0" → 全局搜索会命中

这是 8 轮中 6 轮 REJECTED_TESTER_P0 的根本原因。Round 8 明确报告 "0 个 P0 bug"，仍被判为 REJECTED_TESTER_P0。

### 相关文件
- scripts/hyper-loop.sh (L525-529, compute_verdict 函数内的 Python heredoc)

### 修复方案
将全局子串匹配改为**逐行扫描 + 排除误报行**：

```python
import re
tester_p0 = False
if report.exists():
    text = report.read_text()
    for line in text.splitlines():
        low = line.lower()
        # 跳过 BDD 场景标题行（"| S0xx" 或 "## S0xx"）
        stripped = line.strip()
        if stripped.startswith("| S0") or stripped.startswith("## S0") or stripped.startswith("### S0"):
            continue
        if "p0" in low and ("bug" in low or "fail" in low):
            # 排除 "0 个 P0 bug" 等表示数量为零的表述
            if re.search(r'(\*{0,2})0\s*个\s*p0', low):
                continue
            tester_p0 = True
            break
```

### 约束
- 只修 scripts/hyper-loop.sh 中 compute_verdict 函数的 Python heredoc 部分 (L525-529)
- 不改 veto、max_diff 等其他 verdict 判断逻辑
- 不改 CSS
### 验收标准
引用 BDD 场景 S011: 报告含真正 P0 bug 时 DECISION=REJECTED_TESTER_P0；报告含 "0 个 P0 bug" 或场景标题含 "P0" 时不误判
