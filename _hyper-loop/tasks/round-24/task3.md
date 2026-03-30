## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] auto_decompose 函数中的拆解提示 (line 719-720) 引用了错误路径：
- `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` → 应为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
- `${PROJECT_ROOT}/_hyper-loop/contract.md` → 应为 `${PROJECT_ROOT}/_hyper-loop/context/contract.md`

同样，archive_round 函数 (line 797) 引用了错误路径：
- `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` → 应为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`

脚本其他位置 (line 75-76, 152-153, 393, 438-439) 已经使用正确的 `context/` 路径，仅这三处遗漏。导致 Claude 拆解任务时读不到 BDD 规格和契约，S002 场景 FAIL。
### 相关文件
- scripts/hyper-loop.sh (line 719, line 720, line 797)
### 约束
- 只修改这三行的路径，加上 `context/` 子目录前缀
- 不改动其他逻辑
- 不改 CSS
### 验收标准
引用 BDD 场景 S002: auto_decompose 被调用时，Claude 能正确读取 bdd-specs.md 和 contract.md，生成包含"修复任务"和"相关文件"段落的 task*.md 文件
