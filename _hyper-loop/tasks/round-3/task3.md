## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] archive_round 函数中 bdd-specs.md 的 cp 路径缺少 `context/` 子目录，导致归档时 BDD 规格文件静默复制失败（因 `|| true`），archive 目录不完整。

- L770: `cp "${PROJECT_ROOT}/_hyper-loop/bdd-specs.md"` 应为 `cp "${PROJECT_ROOT}/_hyper-loop/context/bdd-specs.md"`

### 相关文件
- scripts/hyper-loop.sh (L765-774)

### 约束
- 只修改 L770 的 cp 源路径
- 不改动 archive_round 的其他逻辑
- 修改后 `bash -n scripts/hyper-loop.sh` 必须通过

### 验收标准
引用 BDD 场景 S002 (关联): archive 操作能正确复制 `_hyper-loop/context/bdd-specs.md` 到归档目录
