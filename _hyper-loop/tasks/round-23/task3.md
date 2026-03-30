## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 多处引用 bdd-specs.md 和 contract.md 的路径缺少 `context/` 子目录，导致文件找不到。

1. **auto_decompose prompt 路径错误**（行 719-720）：
   - 当前：`${PROJECT_ROOT}/_hyper-loop/bdd-specs.md`
   - 正确：`${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
   - 当前：`${PROJECT_ROOT}/_hyper-loop/contract.md`
   - 正确：`${PROJECT_ROOT}/_hyper-loop/context/contract.md`

2. **archive_round 复制 bdd-specs.md 路径错误**（行 797）：
   - 当前：`cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"`
   - 正确：`cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md"`

需要搜索整个脚本，修正所有 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md` 为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`（排除已经正确的 `_hyper-loop/context/bdd-specs.md` 引用）。
### 相关文件
- scripts/hyper-loop.sh (行 719, 720, 797 及可能的其他位置)
### 约束
- 只修改 scripts/hyper-loop.sh 中的路径引用
- 不改动任何逻辑
- 注意保留行 388-389 等处已经正确的 `_hyper-loop/context/bdd-specs.md` 引用
- 不改 CSS
### 验收标准
- 引用 BDD 场景 S002（auto_decompose 生成任务文件 — prompt 包含正确的 BDD/contract 路径）
- `grep '_hyper-loop/bdd-specs.md' scripts/hyper-loop.sh` 的每个结果都包含 `context/`
- `grep '_hyper-loop/contract.md' scripts/hyper-loop.sh` 的每个结果都包含 `context/`
