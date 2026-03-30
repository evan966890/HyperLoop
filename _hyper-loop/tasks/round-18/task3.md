## 修复任务: TASK-3
### 上下文
先读 _hyper-loop/context/ 下所有文件。
### 问题
[P0-3] merge_writers 函数的 stdout 污染了 INTEGRATION_WT 变量。

`INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获了函数内所有 echo 输出 + 最后的路径。实际变量值变成多行：
```
合并 Writer 产出...
  ⚠ task1: status=timeout, 跳过
合并完成: 0 merged, 1 failed/skipped
/tmp/hyper-loop-worktrees-rN/integration
```

导致 `build_app "$INTEGRATION_WT"` 收到垃圾字符串，cd 到错误目录，构建在错误位置执行。

修复：merge_writers 中所有信息性 echo 重定向到 stderr (`>&2`)，只保留最后一行 `echo "$INTEGRATION_WT"` 输出到 stdout。
### 相关文件
- scripts/hyper-loop.sh (line 299-360, merge_writers 函数体)
### 约束
- 只修改 merge_writers 函数内的 echo 语句
- 将 `echo "合并 Writer 产出..."` 改为 `echo "合并 Writer 产出..." >&2`
- 将 `echo "  ⚠ ..."` 改为 `echo "  ⚠ ..." >&2`
- 将 `echo "  ✓ ..."` 改为 `echo "  ✓ ..." >&2`
- 将 `echo "  ✗ ..."` 改为 `echo "  ✗ ..." >&2`
- 将 `echo "合并完成: ..."` 改为 `echo "合并完成: ..." >&2`
- 最后一行 `echo "$INTEGRATION_WT"` 保持不变（输出到 stdout）
### 验收标准
引用 BDD 场景 S004: merge_writers 返回值只包含路径，build_app 能正确 cd 到 integration worktree
