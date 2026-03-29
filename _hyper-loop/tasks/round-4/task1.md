## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] TESTER_INIT.md 和 REVIEWER_INIT.md 文件路径错误导致 Tester/Reviewer 无法获取角色定义

`start_agent` 函数（L59-93）将 `$INIT` 路径注入给 agent，让 agent 读取角色定义文件。但：
- `run_tester`（L381）传入 `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md` — **该文件不存在**
- `run_reviewers`（L457）传入 `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md` — **该文件不存在**

实际文件在 `_hyper-loop/context/templates/TESTER_INIT.md` 和 `_hyper-loop/context/templates/REVIEWER_INIT.md`。

这是连续 3 轮 0.0 分 / REJECTED_VETO 的根本原因：Reviewer agent 读不到角色定义，不知道评分格式和标准，输出的 JSON 不合规或评分不合理。

### 相关文件
- scripts/hyper-loop.sh (L381, L457)

### 约束
- 只修 scripts/hyper-loop.sh 中 `run_tester` 和 `run_reviewers` 的 INIT 路径参数
- 不改 CSS
- 不移动模板文件（templates/ 目录是正确的组织结构）

### 验收标准
- S007: `run_tester` 引用的 INIT 文件路径必须指向存在的文件
- S008: `run_reviewers` 引用的 INIT 文件路径必须指向存在的文件
- 修复后执行 `ls -la` 确认路径对应的文件确实存在
