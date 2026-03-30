## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] merge_writers 中 `git merge --squash` stdout 未重定向，可能污染函数返回值

`merge_writers` 函数通过 `echo "$INTEGRATION_WT"` 将路径返回给调用方。但 line 348 的 `git merge --squash` 只重定向了 stderr (`2>/dev/null`)，其 stdout 输出（如 "Squash commit -- not updating HEAD"）会混入函数返回值，导致 `build_app` 收到错误路径后 `cd` 失败。

同样，line 349 的 `git commit --no-edit` 也可能输出到 stdout。

### 相关文件
- scripts/hyper-loop.sh (line 348-349，squash merge 和 commit 处)

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 line 348-349 的 git 命令重定向
- 不改 CSS

### 验收标准
引用 BDD 场景 S004: squash merge 到 integration 分支成功，merge_writers 返回的 INTEGRATION_WT 路径纯净无 git 输出污染
