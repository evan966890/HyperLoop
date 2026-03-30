## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] audit_writer_diff 使用 `git diff --name-only HEAD` 检查越界文件，但 Writer (Codex) 是完整 AI agent，会自行 `git add + git commit`。一旦 Writer commit 了修改，`git diff HEAD` 返回空，审计函数认为"没有改任何文件"直接 return 0 — 整个 diff 审计被完全绕过，安全边界失效。这是本轮唯一 FAIL 的 BDD 场景。
### 相关文件
- scripts/hyper-loop.sh (L258-264, audit_writer_diff 函数)
### 修复方案
将 L259 的：
```bash
CHANGED_FILES=$(git -C "$WT" diff --name-only HEAD 2>/dev/null | sort -u)
```
改为对比从分支创建点到当前 HEAD 的所有变更：
```bash
local MERGE_BASE
MERGE_BASE=$(git -C "$WT" merge-base main HEAD 2>/dev/null || git -C "$WT" rev-list --max-parents=0 HEAD 2>/dev/null | head -1)
CHANGED_FILES=$(git -C "$WT" diff --name-only "$MERGE_BASE" HEAD 2>/dev/null | sort -u)
```
这样无论 Writer 是否自行 commit，都能检测到所有从分支创建点以来的文件变更。
### 约束
- 只修改 scripts/hyper-loop.sh 中 audit_writer_diff 函数
- 不改其他函数
- 不改 CSS
### 验收标准
引用 BDD 场景 S005: Writer 改了 TASK.md 未指定的文件时，audit_writer_diff 返回非零退出码，即使 Writer 已自行 commit
