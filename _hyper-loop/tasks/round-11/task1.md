## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] TESTER_INIT.md 和 REVIEWER_INIT.md 文件路径不存在，导致 Tester 和 Reviewer 无法正确初始化。

`run_tester()` 函数（约384行）调用:
```
start_agent "tester" ... "${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md"
```
但实际文件位于 `_hyper-loop/context/agents/tester.md`。

`run_reviewers()` 函数（约460行）调用:
```
start_agent "$NAME" "$CLI" "${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md"
```
但实际文件位于 `_hyper-loop/context/agents/reviewer.md`。

这是前 10 轮全部 0.0 分的根本原因——Reviewer 和 Tester 无法读取角色定义文件，无法正确执行评审和测试。

### 相关文件
- scripts/hyper-loop.sh (384行: run_tester 中 TESTER_INIT.md 路径; 460行: run_reviewers 中 REVIEWER_INIT.md 路径)

### 约束
- 只修 scripts/hyper-loop.sh 中的两个路径引用
- 将 `TESTER_INIT.md` 改为 `agents/tester.md`
- 将 `REVIEWER_INIT.md` 改为 `agents/reviewer.md`
- 不新建文件，不改 CSS

### 验收标准
引用 BDD 场景 S007: Tester 能正确启动并读取角色文件
引用 BDD 场景 S008: 3 Reviewer 能正确启动并读取角色文件
