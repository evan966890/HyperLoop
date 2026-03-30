## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] Reviewer 和 Tester 的 INIT 文件路径错误，导致 24 轮连续 0.0 分

`start_agent` 函数（L384, L460）引用了不存在的文件：
- L384: `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md` — 不存在
- L460: `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md` — 不存在

实际文件位于：
- `${PROJECT_ROOT}/_hyper-loop/context/agents/tester.md`
- `${PROJECT_ROOT}/_hyper-loop/context/agents/reviewer.md`

因为 INIT 文件不存在，`start_agent` 告诉 agent 去读一个空路径。Agent 无法理解角色定义，reviewer 从不输出有效 JSON 评分。降级逻辑写入 `{"score":0}`，0 < 4.0 触发 REJECTED_VETO。这是 24 轮全部 0.0 分的根本原因。

### 相关文件
- scripts/hyper-loop.sh (L384, L460)

### 约束
- 只修 scripts/hyper-loop.sh 中这两处路径引用
- 不改 CSS
- 路径改为 `${PROJECT_ROOT}/_hyper-loop/context/agents/tester.md` 和 `${PROJECT_ROOT}/_hyper-loop/context/agents/reviewer.md`

### 验收标准
引用 BDD 场景 S007（Tester 启动并生成报告）和 S008（3 Reviewer 启动并产出评分）：
- start_agent 调用时传入的 INIT 文件路径指向实际存在的文件
- Reviewer 能读到角色定义，输出有效 JSON 评分（score > 0）
