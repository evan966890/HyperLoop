## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] `merge_writers` 函数在 stdout 混合了状态输出和返回路径，导致调用方 `INTEGRATION_WT=$(merge_writers "$ROUND")` 捕获到多行文本而非纯路径。后续 `build_app "$INTEGRATION_WT"` 中 `cd "$BUILD_DIR"` 因路径含杂质必然失败。这是每轮都会触发的致命 bug——构建永远失败，Tester/Reviewer 永远不会运行。
### 相关文件
- scripts/hyper-loop.sh (line 311, 321, 328, 350, 354, 359: merge_writers 中的 echo 状态输出)
- scripts/hyper-loop.sh (line 628-631: cmd_round 中调用 merge_writers)
- scripts/hyper-loop.sh (line 853-856: cmd_loop 中调用 merge_writers)
### 约束
- 只修 scripts/hyper-loop.sh
- 不改 CSS
- 将 merge_writers 中所有非返回值的 echo（状态信息、进度日志）重定向到 stderr (`>&2`)
- 仅保留最后一行 `echo "$INTEGRATION_WT"` 输出到 stdout
- 不改变函数逻辑，只改输出目标
### 验收标准
引用 BDD 场景 S004: merge_writers 返回的字符串是纯路径，build_app 能成功 cd 进去
