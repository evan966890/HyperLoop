## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] Tester 和 Reviewer 初始化文件路径错误，Agent 无法获得角色定义。

行 384 `start_agent` 调用引用 `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md`（不存在）。
行 460 `start_agent` 调用引用 `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md`（不存在）。

实际文件位于：
- `${PROJECT_ROOT}/_hyper-loop/context/agents/tester.md`
- `${PROJECT_ROOT}/_hyper-loop/context/agents/reviewer.md`

需要将两处路径修正为实际文件路径。
### 相关文件
- scripts/hyper-loop.sh (行 384, 行 460)
### 约束
- 只修改 scripts/hyper-loop.sh 中这两处路径引用
- 不改动 start_agent 函数逻辑
- 不改 CSS
### 验收标准
- 引用 BDD 场景 S007（Tester 启动并生成报告）
- 引用 BDD 场景 S008（3 Reviewer 启动并产出评分）
- `grep -n 'agents/tester.md' scripts/hyper-loop.sh` 能找到修正后的路径
- `grep -n 'agents/reviewer.md' scripts/hyper-loop.sh` 能找到修正后的路径
- `grep -c 'TESTER_INIT.md\|REVIEWER_INIT.md' scripts/hyper-loop.sh` 返回 0
