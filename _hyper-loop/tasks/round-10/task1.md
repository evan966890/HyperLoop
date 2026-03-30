## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1-001] TESTER_INIT.md 和 REVIEWER_INIT.md 路径错误导致 Tester/Reviewer 无法读取角色定义

`run_tester` 第 384 行引用 `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md`，
`run_reviewers` 第 460 行引用 `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md`，
但实际文件在 `_hyper-loop/context/templates/` 子目录下。

这是连续 9 轮 REJECTED_VETO（全部 0.0 分）的根本原因：Tester/Reviewer agent 启动后
读不到角色定义文件，无法正确执行评估流程，导致评分全部为 0。

### 相关文件
- scripts/hyper-loop.sh (第 384 行: run_tester 中 start_agent 调用)
- scripts/hyper-loop.sh (第 460 行: run_reviewers 中 start_agent 调用)

### 约束
- 只改 scripts/hyper-loop.sh 的第 384 行和第 460 行
- 路径改为 `${PROJECT_ROOT}/_hyper-loop/context/templates/TESTER_INIT.md`
- 路径改为 `${PROJECT_ROOT}/_hyper-loop/context/templates/REVIEWER_INIT.md`
- 不改其他逻辑、不改 CSS

### 验收标准
- 引用 BDD 场景 S007: Tester 启动后能正确读取 TESTER_INIT.md
- 引用 BDD 场景 S008: 3 个 Reviewer 启动后能正确读取 REVIEWER_INIT.md
- `bash -n scripts/hyper-loop.sh` 语法检查通过
