## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] S007/S008: Tester 和 Reviewer 的 INIT 文件路径错误，导致 Agent 无法获取角色定义

`start_agent` 调用时传入的路径是：
- `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md` (line 381)
- `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md` (line 457)

但这两个文件实际位于 `context/templates/` 子目录：
- `_hyper-loop/context/templates/TESTER_INIT.md`
- `_hyper-loop/context/templates/REVIEWER_INIT.md`

路径缺少 `templates/`，导致 Tester 和全部 3 个 Reviewer 启动时无法读取角色定义。

### 相关文件
- scripts/hyper-loop.sh (line 376-382, run_tester 函数)
- scripts/hyper-loop.sh (line 450-458, run_reviewers 函数)

### 约束
- 只改 `scripts/hyper-loop.sh` 中上述两处路径
- 不改模板文件本身的位置或内容
- 不改 CSS

### 验收标准
- 引用 BDD 场景 S007: run_tester 中 INIT 路径指向实际存在的 `context/templates/TESTER_INIT.md`
- 引用 BDD 场景 S008: run_reviewers 中 INIT 路径指向实际存在的 `context/templates/REVIEWER_INIT.md`
- `bash -n scripts/hyper-loop.sh` 通过
