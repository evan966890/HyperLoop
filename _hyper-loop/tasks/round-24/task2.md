## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] run_tester (line 384) 和 run_reviewers (line 460) 引用 `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md` 和 `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md`，但这两个文件实际路径在 `_hyper-loop/context/templates/` 子目录下。Agent 启动时 inject 文件指向不存在的路径，导致 Tester 和 Reviewer 无法获得角色上下文，S007 和 S008 场景 FAIL。
### 相关文件
- scripts/hyper-loop.sh (line 384, line 460)
### 约束
- 只修改这两行的路径：`context/TESTER_INIT.md` → `context/templates/TESTER_INIT.md`，`context/REVIEWER_INIT.md` → `context/templates/REVIEWER_INIT.md`
- 不改动其他逻辑
- 不改 CSS
### 验收标准
引用 BDD 场景 S007: Tester 启动时能读到 TESTER_INIT.md，生成 reports/round-N-test.md
引用 BDD 场景 S008: 3 个 Reviewer 启动时能读到 REVIEWER_INIT.md，各自生成评分 JSON
