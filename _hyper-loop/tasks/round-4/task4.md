## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 两处代码质量问题:
1. cmd_status() 重复定义 — L670-676（第一次）和 L932-944（第二次），第一个定义是死代码，被第二个覆盖。
2. archive_round() L770 复制路径 `${PROJECT_ROOT}/_hyper-loop/bdd-specs.md` 错误，实际文件在 `_hyper-loop/context/bdd-specs.md`，归档时始终复制失败（被 `|| true` 静默吞掉）。
### 相关文件
- scripts/hyper-loop.sh (L670-676, 第一个 cmd_status 定义)
- scripts/hyper-loop.sh (L764-777, archive_round 函数)
### 约束
- 只修 scripts/hyper-loop.sh
- 删除 L670-676 的第一个 cmd_status 定义
- 修正 archive_round 中 bdd-specs.md 的复制路径为 _hyper-loop/context/bdd-specs.md
- 不改 CSS
### 验收标准
引用 BDD 场景 S001（脚本不崩溃、功能正常）: cmd_status 只有一个定义且功能完整；archive_round 能正确复制 bdd-specs.md 到归档目录。
