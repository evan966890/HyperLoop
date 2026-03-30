## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0-1 + P1-1] audit_writer_diff stdout 泄露 + 未检测 untracked 新文件

**P0-1（stdout 泄露，构建必定失败）**:
`merge_writers` (L299) 本身的 echo 已修复为 `>&2`，但它内部调用的 `audit_writer_diff` (L242) 仍有 3 处 echo 输出到 stdout：
- L262: `echo "  ⚠ Writer 没有改任何文件"` — 缺少 `>&2`
- L290: `echo -e "$VIOLATIONS"` — 缺少 `>&2`
- L294: `echo "  ✓ Diff 审计通过"` — 缺少 `>&2`

调用方 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获全部 stdout，这些日志文本混入路径，`build_app "$INTEGRATION_WT"` 的 `cd` 收到多行字符串而失败。

**P1-1（untracked 文件绕过审计）**:
L259 `git diff --name-only HEAD` 只检测已跟踪文件的变更。Writer 新建的 untracked 文件完全不出现在 diff 中，但后续 `git add -A` (L338) 会将它们全部提交。越界新文件不被审计拦截。

### 相关文件
- scripts/hyper-loop.sh (L242-295, audit_writer_diff 函数)

### 约束
- 只修 audit_writer_diff 函数内部
- 不改函数签名和返回值语义
- 不改 CSS

### 验收标准
1. 引用 BDD S004: `audit_writer_diff` 内所有 echo 使用 `>&2`，`merge_writers` 返回值仅含路径
2. 引用 BDD S005: `CHANGED_FILES` 同时包含 `git diff --name-only HEAD` 和 `git ls-files --others --exclude-standard` 的结果，untracked 新文件也被审计
