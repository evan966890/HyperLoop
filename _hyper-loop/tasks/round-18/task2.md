## 修复任务: TASK-2
### 上下文
先读 _hyper-loop/context/ 下所有文件。
### 问题
[P0-2] Tester 和 Reviewer 的角色定义文件路径不存在。

脚本引用：
- line 384: `_hyper-loop/context/TESTER_INIT.md`
- line 460: `_hyper-loop/context/REVIEWER_INIT.md`

实际文件位于：
- `_hyper-loop/context/agents/tester.md`
- `_hyper-loop/context/agents/reviewer.md`

Tester 和 Reviewer Agent 启动时读不到角色定义，以无上下文状态运行，导致评分不可靠（所有轮次评分 0.0）。
### 相关文件
- scripts/hyper-loop.sh (line 380-390, line 455-470)
### 约束
- 只修改 scripts/hyper-loop.sh 中 start_agent 调用处的路径参数
- 路径改为 `${PROJECT_ROOT}/_hyper-loop/context/agents/tester.md` 和 `${PROJECT_ROOT}/_hyper-loop/context/agents/reviewer.md`
- 不修改 agent 文件本身
### 验收标准
引用 BDD 场景 S007: Tester 能读到角色定义并正确生成报告
引用 BDD 场景 S008: 3 个 Reviewer 能读到角色定义并产出有效评分
