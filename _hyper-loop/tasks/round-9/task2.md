## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] archive_round 归档 bdd-specs.md 路径错误，BDD 规格永远不会被归档

L773 的路径是错的：
```bash
cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
```

bdd-specs.md 实际位于 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。`|| true` 让错误静默通过，导致归档目录中永远缺少 bdd-specs.md。

### 相关文件
- scripts/hyper-loop.sh (L773, archive_round 函数)

### 修复方案
将 L773 改为：
```bash
cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
```

### 约束
- 只修 scripts/hyper-loop.sh 中 archive_round 函数的这一行
- 不改 CSS
### 验收标准
引用 BDD 场景 S001 — 归档后 archive/round-N/ 下应包含 bdd-specs.md 文件
