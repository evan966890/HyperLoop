## 修复任务: TASK-1
### 上下文
先读 _hyper-loop/context/ 下所有文件，特别关注 templates/ 和 agents/ 子目录的文件结构。
### 问题
[P0] Tester 和 Reviewer 的 init 文件路径引用错误，导致 agent 启动后无法读取角色定义。

具体：
- `scripts/hyper-loop.sh:381` 引用 `${PROJECT_ROOT}/_hyper-loop/context/TESTER_INIT.md`
- `scripts/hyper-loop.sh:457` 引用 `${PROJECT_ROOT}/_hyper-loop/context/REVIEWER_INIT.md`
- 实际路径为 `_hyper-loop/context/templates/TESTER_INIT.md` 和 `_hyper-loop/context/templates/REVIEWER_INIT.md`（缺少 `templates/` 子目录）

### 相关文件
- scripts/hyper-loop.sh (行 379-382, run_tester 函数)
- scripts/hyper-loop.sh (行 456-458, run_reviewers 函数)
- _hyper-loop/context/templates/TESTER_INIT.md (正确路径，只读参考)
- _hyper-loop/context/templates/REVIEWER_INIT.md (正确路径，只读参考)

### 约束
- 只修改 scripts/hyper-loop.sh
- 只改路径字符串，不改逻辑
- 不改 CSS

### 验收标准
- S007: Tester 启动后能读取角色定义并生成 reports/round-N-test.md
- S008: 3 个 Reviewer 启动后能读取角色定义并产出评分 JSON
