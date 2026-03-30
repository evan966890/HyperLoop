## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] `auto_decompose` 和 `archive_round` 函数引用了不规范的 bdd-specs.md 路径。虽然 `_hyper-loop/bdd-specs.md` 文件确实存在（是 `_hyper-loop/context/bdd-specs.md` 的副本），但应统一引用 `_hyper-loop/context/` 下的版本以保持一致性，因为 `_ctx/` 复制的是 `_hyper-loop/context/` 目录。

具体问题：
1. `auto_decompose` prompt（约 line 719-720）引用 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`
2. `archive_round`（约 line 797）复制 `_hyper-loop/bdd-specs.md`

### 相关文件
- scripts/hyper-loop.sh（line 719-720: auto_decompose prompt 路径；line 797: archive_round cp 路径）

### 修复方案
1. `auto_decompose` 中 DECOMPOSE_PROMPT 的路径引用改为 context/ 下：
   ```
   # 旧：
   - BDD 行为规格：${PROJECT_ROOT}/_hyper-loop/bdd-specs.md
   - 评估契约：${PROJECT_ROOT}/_hyper-loop/contract.md
   # 新：
   - BDD 行为规格：${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md
   - 评估契约：${PROJECT_ROOT}/_hyper-loop/context/contract.md
   ```

2. `archive_round` 中 cp 路径改为 context/ 下：
   ```
   # 旧：
   cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
   # 新：
   cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
   ```

### 约束
- 只修 scripts/hyper-loop.sh 中上述三处路径
- 不改函数逻辑

### 验收标准
引用 BDD 场景 S002（auto_decompose 生成任务文件）：Claude 拆解任务时能正确读到 BDD 规格和评估契约。
