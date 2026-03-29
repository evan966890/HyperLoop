## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] TESTER_INIT.md 和 REVIEWER_INIT.md 文件不存在，导致 Tester 和 Reviewer Agent 启动时缺少角色定义上下文。

`start_agent` 在 L74 会将 `${INIT}` 路径注入给 Agent 作为"角色定义"。
- `run_tester` (L381) 传入 `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md`
- `run_reviewers` (L457) 传入 `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md`

这两个文件实际不存在。Agent 启动后读不到角色定义，缺少评估标准和输出格式约束，导致评分质量不稳定。

### 相关文件
- _hyper-loop/context/TESTER_INIT.md (需新建)
- _hyper-loop/context/REVIEWER_INIT.md (需新建)
- _hyper-loop/context/hyper-loop.sh L59-88 (start_agent 函数，只读参考)
- _hyper-loop/context/hyper-loop.sh L375-422 (run_tester，只读参考)
- _hyper-loop/context/hyper-loop.sh L424-507 (run_reviewers，只读参考)

### 约束
- 只新建上述两个 .md 文件
- 不修改 hyper-loop.sh
- TESTER_INIT.md 必须包含：角色说明、BDD 场景验证流程、报告输出格式（与现有 TREQ 模板兼容）、P0/P1 分级标准
- REVIEWER_INIT.md 必须包含：角色说明、评分维度（参考 contract.md: 客观80%+主观20%）、JSON 输出格式 `{"score":数字,"issues":[...],"summary":"..."}`、一票否决阈值说明

### 验收标准
引用 BDD 场景 S007（Tester 启动并生成报告）和 S008（3 Reviewer 启动并产出评分）：
- `ls _hyper-loop/context/TESTER_INIT.md` 和 `ls _hyper-loop/context/REVIEWER_INIT.md` 文件存在
- 文件内容与 run_tester / run_reviewers 的注入流程兼容
