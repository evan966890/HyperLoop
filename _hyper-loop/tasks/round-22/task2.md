## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] `auto_decompose()` 和 `archive_round()` 中引用 bdd-specs.md 和 contract.md 的路径缺少 `/context/` 路径段，导致拆解器读不到 BDD 规格和评估契约。这是 21 轮全部 0 分的根本原因之一。

具体位置：
1. `auto_decompose()` 第 719 行：`${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` → 应为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
2. `auto_decompose()` 第 720 行：`${PROJECT_ROOT}/_hyper-loop/contract.md` → 应为 `${PROJECT_ROOT}/_hyper-loop/context/contract.md`
3. `archive_round()` 第 797 行：`${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` → 应为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`

### 相关文件
- scripts/hyper-loop.sh（第 719-720 行，第 797 行）

### 约束
- 只修指定文件
- 不改 CSS
- 只改这 3 处路径引用，不动其他逻辑
- 修改后 `bash -n scripts/hyper-loop.sh` 必须通过
- 用 `grep -n '_hyper-loop/bdd-specs\|_hyper-loop/contract' scripts/hyper-loop.sh` 确认无遗漏

### 验收标准
引用 BDD 场景 S002: auto_decompose 生成的 prompt 正确引用 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`，使拆解器能读到 BDD 规格和评估契约。
