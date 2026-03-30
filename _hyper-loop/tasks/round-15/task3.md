## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] archive_round() 引用错误的 bdd-specs.md 路径

`archive_round()` 函数（约第 797 行）中：
```bash
cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
```

实际文件路径应为：
```bash
cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
```

当前路径错误导致归档时无法复制 BDD 规格文件，archive 目录不完整。虽然有 `|| true` 不会崩溃，但归档数据缺失影响后续回退恢复（S013 依赖 archive 数据）。

### 相关文件
- scripts/hyper-loop.sh (archive_round 函数, 约第 791-806 行)

### 约束
- 只修改 scripts/hyper-loop.sh 中 archive_round() 函数内的 cp 路径
- 将 `_hyper-loop/bdd-specs.md` 改为 `_hyper-loop/context/bdd-specs.md`
- 不改动其他 cp 行或函数逻辑

### 验收标准
引用 BDD 场景 S013: archive 目录包含完整的 bdd-specs.md 副本，确保回退恢复时数据完整
