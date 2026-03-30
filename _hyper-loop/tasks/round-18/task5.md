## 修复任务: TASK-5
### 上下文
先读 _hyper-loop/context/ 下所有文件。
### 问题
[P1-3] archive_round 拷贝 bdd-specs.md 路径可能错误。

位置 line 797:
```bash
cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/"
```

BDD spec 的权威路径是 `_hyper-loop/context/bdd-specs.md`。当前 `_hyper-loop/bdd-specs.md` 是一个副本，可能过期或不存在。

修复：改为拷贝权威路径 `${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md`。因为后面有 `2>/dev/null || true` 保护不会崩溃，但 archive 中可能缺少 BDD spec 快照影响问题回溯。
### 相关文件
- scripts/hyper-loop.sh (line 797, archive_round 函数)
### 约束
- 只修改 archive_round 函数中 cp bdd-specs.md 的路径
- 保留 `2>/dev/null || true` 错误保护
### 验收标准
引用 BDD 场景 S013 (关联): archive 中包含正确的 BDD spec 快照，支持回退时的问题追溯
