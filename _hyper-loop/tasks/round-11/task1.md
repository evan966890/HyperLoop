## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] scripts/hyper-loop.sh L282-421 区域三个相邻函数存在 bug：

1. **audit_writer_diff (L282-336)**: `git diff --name-only HEAD` 只检测已跟踪文件的修改，不检测 Writer 新建的 untracked 文件。如果 Writer 在任务范围外创建了新文件（如 `src/evil.ts`），audit 完全不会发现，该文件会被 `git add -A` 提交并合并到 integration 分支。BDD S005 要求"改了 TASK.md 未指定的文件"时拦截——"改"包括新建。

2. **merge_writers (L339-406)**: L392 `git commit --no-edit -m "..." >&2 2>/dev/null` 在 squash merge 产生空提交时（Writer 没改任何代码文件），因 `set -e` 导致脚本崩溃退出。当 Writer 写了 `DONE.json status=done` 但实际没修改代码文件时，元数据被清理后 commit 为空，`git commit` 返回非零，脚本终止。

3. **build_app (L409-421)**: L412 `cd "$BUILD_DIR"` 永久改变脚本工作目录。虽然后续函数目前用 `$PROJECT_ROOT` 绝对路径所以没触发问题，但这是一个潜在 P0——任何未来使用相对路径的代码都会在错误目录执行。

### 相关文件
- scripts/hyper-loop.sh (L282-421: audit_writer_diff, merge_writers, build_app 三个函数)

### 修复策略

用 grep/搜索先定位所有相关代码，一次性修复：

**audit_writer_diff 修复：**
在获取 CHANGED_FILES 时（L299 附近），除了 `git diff --name-only HEAD`，还要加上 untracked 文件检测：
```bash
UNTRACKED=$(git -C "$WT" ls-files --others --exclude-standard 2>/dev/null)
if [[ -n "$UNTRACKED" ]]; then
  CHANGED_FILES=$(printf '%s\n%s' "$CHANGED_FILES" "$UNTRACKED" | sort -u)
fi
```

**merge_writers 修复：**
给 squash merge 后的 commit 加 `|| true`，防止空提交导致 set -e 崩溃：
```bash
git -C "$INTEGRATION_WT" commit --no-edit -m "hyper-loop R${ROUND} ${TASK_NAME}" >&2 2>/dev/null || true
```

**build_app 修复：**
用 subshell 包裹 cd + build 逻辑，防止 cd 副作用泄漏到调用方：
```bash
build_app() {
  local BUILD_DIR="$1"
  echo "构建 App..."
  if (
    cd "$BUILD_DIR"
    eval "${CACHE_CLEAN:-true}" 2>/dev/null || true
    eval "${BUILD_CMD:-echo 'no BUILD_CMD'}"
  ); then
    echo "  ✓ 构建成功"
    return 0
  else
    echo "  ✗ 构建失败"
    return 1
  fi
}
```

### 约束
- 只修 scripts/hyper-loop.sh 的 L282-421 区域（audit_writer_diff / merge_writers / build_app 三个函数）
- 不改该区域之外的代码
- 修完运行 `bash -n scripts/hyper-loop.sh` 确认语法无误

### 验收标准
- S004: Writer 完成后 diff 被正确 commit，多 Writer 不因空提交崩溃
- S005: audit 能拦截 Writer 新建的越界 untracked 文件
- S017: 多 Writer 同文件冲突处理不崩溃
