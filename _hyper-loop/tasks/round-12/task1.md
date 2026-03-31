## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] `audit_writer_diff` 白名单遗漏 `_writer_prompt.md` + 缺少 untracked 文件检测

`start_writers` 为每个 Writer 生成 `_writer_prompt.md`（~line 178），该文件是 untracked 的。
但 `audit_writer_diff` 的 case 白名单（~line 319-321）只有：
```
DONE.json|WRITER_INIT.md|_ctx/*|TASK.md
```
遗漏了 `_writer_prompt.md`。

此外，`audit_writer_diff` 只用 `git diff --name-only HEAD`（~line 299）检测已跟踪文件的变更，
不检测 untracked 文件。如果 Writer 执行了 `git add -A`（常见行为），untracked 的 `_writer_prompt.md`
会被 stage 并被 `git diff --name-only HEAD` 检测到，然后因不在白名单而被拒绝。

**影响**: 每个 Writer 的产出都可能被误判越界 → 所有合并被拒绝 → 整轮产出为零。这是阻塞性回归。

### 相关文件
- scripts/hyper-loop.sh (行 282-336, `audit_writer_diff` 函数)

### 修复策略
1. 用 grep 扫描 `start_writers` 函数中所有 `> "${WT}/` 或 `cat >` 写入 worktree 的文件名，
   确认完整的元数据文件列表
2. 用 grep 扫描 `merge_writers` 中 `rm -f` 删除的文件列表，两者应一致
3. 在 `audit_writer_diff` 的 case 白名单中加入 `_writer_prompt.md`：
   ```bash
   case "$changed" in
     DONE.json|WRITER_INIT.md|TASK.md|_writer_prompt.md|_ctx/*) FOUND=true ;;
   esac
   ```
4. 在 `CHANGED_FILES` 赋值处，同时检测 untracked 文件（与 tracked 变更合并）：
   ```bash
   CHANGED_FILES=$(
     { git -C "$WT" diff --name-only HEAD 2>/dev/null
       git -C "$WT" ls-files --others --exclude-standard 2>/dev/null
     } | sort -u
   )
   ```
5. 运行 `bash -n scripts/hyper-loop.sh` 确认语法正确

### 约束
- 只修 scripts/hyper-loop.sh 的 `audit_writer_diff` 函数（行 282-336）
- 不改函数签名或返回值语义

### 验收标准
- BDD S004: Writer 完成后 diff 被正确 commit（元数据文件不导致误判）
- BDD S005: diff 审计仍能正确拦截真实越界修改
- `bash -n scripts/hyper-loop.sh` 通过
