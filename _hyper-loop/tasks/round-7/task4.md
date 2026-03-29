## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] `auto_decompose` prompt 中引用路径不一致 — L708-710 使用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`（无 `context/` 前缀），而 `start_agent` (L75-76) 使用 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。

当前因为两个位置都有副本所以不影响，但维护两份文件是脆弱的：修改一处忘记同步另一处会导致拆解器和评审者看到不同的规格。

修复方案：将 `auto_decompose` 中的路径统一改为 `_hyper-loop/context/` 前缀，与 `start_agent` 注入的路径一致。同时删除根目录下的冗余副本（如果存在）。

### 相关文件
- _hyper-loop/context/hyper-loop.sh L704-710 (auto_decompose prompt 中的路径引用)

### 约束
- 只修改 _hyper-loop/context/hyper-loop.sh
- 只修改 `auto_decompose` 函数中 DECOMPOSE_PROMPT heredoc 里的文件路径
- 将 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 改为 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`
- 将 `${PROJECT_ROOT}/_hyper-loop/contract.md` 改为 `${PROJECT_ROOT}/_hyper-loop/context/contract.md`
- 将 `${PROJECT_ROOT}/_hyper-loop/results.tsv` 路径保持不变（results.tsv 在根目录是正确的）

### 验收标准
引用 BDD 场景 S002（auto_decompose 生成任务文件）：
- `grep 'context/bdd-specs.md' _hyper-loop/context/hyper-loop.sh` 在 auto_decompose 和 start_agent 中均匹配
- `grep 'context/contract.md' _hyper-loop/context/hyper-loop.sh` 在 auto_decompose 和 start_agent 中均匹配
- `bash -n _hyper-loop/context/hyper-loop.sh` 通过
