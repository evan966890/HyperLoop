## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] REVIEWER_INIT.md 模板中的 `{{placeholder}}` 未被替换，Reviewer 拿到的是原始模板而非实际项目信息

即使 TASK-1 修复了路径问题，Reviewer 读到的 `templates/REVIEWER_INIT.md` 仍然充满未替换的占位符：
- `{{PROJECT_NAME}}`, `{{PROJECT_TYPE}}`, `{{TECH_STACK}}`, `{{ARCHITECTURE}}`
- `{{PRD_FULL}}`, `{{DESIGN_FULL}}`, `{{UX_SPEC}}`, `{{CONTRACT}}`, `{{CHECKLIST}}`, `{{CODING_RULES}}`

这意味着 Reviewer 看到的是空白模板而非实际项目上下文。对于 HyperLoop 自优化场景，应该：
1. 在 `run_reviewers` 中生成一个渲染后的 REVIEWER_INIT 文件（替换占位符为实际值），或
2. 创建一个适配 HyperLoop 自身的精简 REVIEWER_INIT（不需要 Tauri/UI 相关内容，专注于 bash 脚本评审）

推荐方案 2：为 HyperLoop 创建专用的 Reviewer 角色定义，删除 Tauri/Playwright/视觉相关内容，聚焦在 bash 脚本 + BDD 场景验证。

同理 TESTER_INIT.md 也有类似问题（Playwright/Tauri/CDP 内容与 HyperLoop 自身无关），但 Tester 的主要指令来自 `run_tester` 注入的测试请求，影响较小，可在后续轮次处理。

### 相关文件
- scripts/hyper-loop.sh (L424-507, run_reviewers 函数)
- _hyper-loop/context/templates/REVIEWER_INIT.md (参考模板结构)

### 约束
- 修改 `run_reviewers` 函数，在调用 `start_agent` 之前生成渲染后的 REVIEWER_INIT
- 渲染内容应包含：项目名=HyperLoop、类型=bash 脚本自优化系统、评估契约内容、BDD 规格引用
- 或在 `_hyper-loop/context/` 下创建 `REVIEWER_INIT_RENDERED.md`（专为 HyperLoop 评审定制）
- 不改 CSS

### 验收标准
- S008: Reviewer 启动后能读到包含实际项目信息的角色定义（无 `{{placeholder}}`）
- S009: Reviewer 输出的 JSON 包含合理的 score 字段（不再是 0.0）
- `bash -n scripts/hyper-loop.sh` 通过
