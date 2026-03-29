## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Agent 初始化文件路径错误，导致 Tester 和 Reviewer 无法读取角色定义

脚本中 `start_agent` 调用引用了不存在的文件：
- line 381: `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md` — 文件不存在
- line 457: `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md` — 文件不存在

实际文件位于：
- `${PROJECT_ROOT}/_hyper-loop/context/agents/tester.md`
- `${PROJECT_ROOT}/_hyper-loop/context/agents/reviewer.md`

这是连续 8 轮全部 0 分的根本原因之一：Reviewer 读不到角色定义，不知道自己该做什么。

### 相关文件
- scripts/hyper-loop.sh (line 380-381, line 456-457)

### 约束
- 只修 scripts/hyper-loop.sh
- 只改两处文件路径引用，不改其他逻辑

### 验收标准
引用 BDD 场景 S007（Tester 启动）和 S008（3 Reviewer 启动）
- `start_agent "tester"` 的 INIT 参数指向实际存在的 `agents/tester.md`
- `start_agent "$NAME"` 的 INIT 参数指向实际存在的 `agents/reviewer.md`
