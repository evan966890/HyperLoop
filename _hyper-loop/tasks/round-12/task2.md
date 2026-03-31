## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] `compute_verdict` 中 Tester P0 否决阈值与 BDD S011 规格不一致

BDD S011 规定：
> Given Tester 报告包含 "P0" 和 "fail"
> When compute_verdict 被调用
> Then DECISION = REJECTED_TESTER_P0

但实际 Python 实现（~line 586-592）要求：
- `len(p0_bugs) >= 2`（需 2+ 个 `### P0` heading）
- 或 `len(p0_bugs) >= 1 and len(bdd_fails) > 3`（1 个 P0 + >3 BDD FAIL）

这意味着单个致命 P0 bug（如 P0-1 这种阻塞性回归）不会触发自动否决，需人工介入。

**影响**: 严重的单个 P0 bug 可能因阈值过高而被放过，降低自动化质量门控的有效性。

### 相关文件
- scripts/hyper-loop.sh (行 568-620, `compute_verdict` 函数中的 Python 代码块)

### 修复策略
1. 定位 `compute_verdict` 函数中的 Python 代码（`python3 -` heredoc）
2. 找到 `tester_p0` 判定逻辑（约 line 592）
3. 修改为符合 BDD S011 的简单条件：**1 个 P0 heading + 至少 1 个 BDD FAIL 即触发否决**
   ```python
   tester_p0 = len(p0_bugs) >= 1 and len(bdd_fails) >= 1
   ```
4. 更新注释说明（删除旧的阈值解释注释）
5. 运行 `bash -n scripts/hyper-loop.sh` 确认语法正确

### 约束
- 只修 scripts/hyper-loop.sh 的 `compute_verdict` 函数内 Python heredoc（行 568-620）
- 不改 verdict.env 输出格式
- 不改 veto / max_diff / median 逻辑

### 验收标准
- BDD S011: Tester P0 否决——报告包含 P0 和 fail 时触发 REJECTED_TESTER_P0
- BDD S009/S010: 其他 verdict 逻辑不受影响
- `bash -n scripts/hyper-loop.sh` 通过
