## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] archive_round 中 bdd-specs.md 路径错误，BDD 规格从未被归档

line 773:
```bash
cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md" "$ARCHIVE/" 2>/dev/null || true
```
实际文件位于 `_hyper-loop/context/bdd-specs.md`，此行永远静默失败。归档缺少 BDD 规格会影响历史回溯分析。

### 相关文件
- scripts/hyper-loop.sh (line 773，archive_round 函数中的 cp 命令)

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 line 773 的路径
- 不改 CSS

### 验收标准
引用 BDD 场景 S001: 循环跑满后 archive 目录中包含 bdd-specs.md 的正确副本
