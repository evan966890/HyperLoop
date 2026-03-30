## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] **路径引用不一致：auto_decompose 和 archive_round 用根目录 bdd-specs.md，其他函数用 context/ 子目录**

两处路径不一致：

1. **auto_decompose** (line ~719-720)：引用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，但其他函数用 `_hyper-loop/context/` 路径。
2. **archive_round** (line ~797)：`cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 应为 `_hyper-loop/context/bdd-specs.md` 以保持一致。

注意：auto_decompose 中的路径出现在传给 Claude 的 prompt heredoc 里（让 Claude 读取这些文件），改为 context/ 路径可确保 Claude 读到统一版本。

### 相关文件
- scripts/hyper-loop.sh (auto_decompose 函数 line ~715-740；archive_round 函数 line ~790-800)
### 约束
- 只修 scripts/hyper-loop.sh
- auto_decompose 中 heredoc 的路径改为 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`
- archive_round 中 cp 路径改为 `_hyper-loop/context/bdd-specs.md`
- 确保 `_hyper-loop/context/` 目录下确实有这些文件（如果没有则不改，保留原路径）
- 不改其他函数
### 验收标准
- `grep '_hyper-loop/bdd-specs.md' scripts/hyper-loop.sh` 中无直接根路径引用（均应为 `_hyper-loop/context/bdd-specs.md`）
- `bash -n scripts/hyper-loop.sh` PASS
- 引用 BDD 场景 S002（auto_decompose 生成任务文件 — 正确读取上下文）
