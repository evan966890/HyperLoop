## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。重点关注 build_app 函数和 cmd_loop 主循环中对它的调用。

### 问题
[P0] build_app 函数用裸 `cd` 改变全局工作目录，导致后续操作在错误的 cwd 中运行

位置: scripts/hyper-loop.sh L367 `cd "$BUILD_DIR"`

调用链: cmd_loop → build_app "$INTEGRATION_WT" → cd 到 worktree 目录 → 函数返回后 cwd 仍在 worktree → cleanup_round 删除该 worktree → 脚本 cwd 指向已删除的目录 → 后续轮次所有依赖相对路径的操作失败

### 相关文件
- scripts/hyper-loop.sh (L363-376) — build_app 函数

### 约束
- 只修 build_app 函数
- 用 subshell `( cd ... && ... )` 隔离 cwd 变更，或用 `pushd/popd`
- 保持 eval "${BUILD_CMD}" 的行为不变
- 确保返回值（0=成功, 非0=失败）能正确传递给调用者
- 不改 CSS

### 验收标准
- build_app 执行完毕后，调用者的 cwd 不被改变
- S001: 多轮循环能正常跑完不崩溃（cd 污染会导致第 2 轮崩）
- S015: cleanup_round 删除 worktree 后不影响后续操作
