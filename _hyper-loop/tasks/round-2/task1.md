## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] `auto_decompose()` 和 `archive_round()` 引用了错误的文件路径，缺少 `context/` 目录段。

`auto_decompose()` L692-693 中 bdd-specs.md 和 contract.md 的路径写成了 `_hyper-loop/bdd-specs.md` 和 `_hyper-loop/contract.md`，实际文件在 `_hyper-loop/context/bdd-specs.md` 和 `_hyper-loop/context/contract.md`。Claude 拿到不存在的路径，任务拆解大概率失败。

`archive_round()` L770 同样引用了 `_hyper-loop/bdd-specs.md`（缺少 `context/`），导致归档时 cp 静默失败，归档目录缺少 bdd-specs.md。

### 相关文件
- scripts/hyper-loop.sh (L688-694, auto_decompose 函数的 DPROMPT heredoc)
- scripts/hyper-loop.sh (L770, archive_round 函数的 cp 命令)

### 约束
- 只修 scripts/hyper-loop.sh
- 不改其他逻辑，只修路径字符串
- 不改 CSS

### 验收标准
- S002: auto_decompose 生成任务文件 — prompt 中的路径指向真实存在的文件
- 归档后 archive/round-N/ 下有 bdd-specs.md 副本
