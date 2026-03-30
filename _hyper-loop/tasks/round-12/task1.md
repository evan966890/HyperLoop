## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] Tester 和 Reviewer 初始化路径不存在，导致 Tester/Reviewer 无法正确初始化，评分全部为 0.0

`run_tester()` 在 line 384 引用 `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md`，但该文件不存在。
`run_reviewers()` 在 line 460 引用 `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md`，但该文件不存在。

实际的角色定义文件在：
- `_hyper-loop/context/agents/tester.md`
- `_hyper-loop/context/agents/reviewer.md`

这是前 11 轮全部 0.0 分的根本原因。Round 11 已诊断并在 integration 分支修复，但因 REJECTED_VETO 未合并到 main。

### 相关文件
- scripts/hyper-loop.sh (lines 380-465)

### 约束
- 只修 scripts/hyper-loop.sh 中 run_tester() 和 run_reviewers() 函数内的路径引用
- 不改其他函数
- 不改 CSS
- 修改范围：lines 380-465

### 验收标准
引用 BDD 场景 S007 (Tester 启动并生成报告) 和 S008 (3 Reviewer 启动并产出评分)
- `start_agent` 调用中的初始化文件路径指向实际存在的文件
- `bash -n scripts/hyper-loop.sh` 语法检查通过
