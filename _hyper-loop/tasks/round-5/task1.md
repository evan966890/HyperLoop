## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] merge_writers stdout 污染导致 build_app 永远失败

`INTEGRATION_WT=$(merge_writers "$ROUND")` (line 629, 852) 用命令替换捕获 merge_writers 的全部 stdout，但函数内有大量 `echo` 状态输出（"合并 Writer 产出..."、"✓ task1 merged"、"合并完成: ..."），导致 INTEGRATION_WT 变量包含多行文本而非单一路径。后续 `build_app "$INTEGRATION_WT"` 执行 `cd "$BUILD_DIR"` 时必定失败，每轮 DECISION 都是 BUILD_FAILED。

### 相关文件
- scripts/hyper-loop.sh (line 299-361, merge_writers 函数)

### 约束
- 只修 scripts/hyper-loop.sh 中 merge_writers 函数
- 不改函数签名和返回逻辑
- 不改 CSS

### 验收标准
- merge_writers 内所有状态消息（echo "合并 Writer 产出..."、echo "  ✓ ..."、echo "  ✗ ..."、echo "  ⚠ ..."、echo "合并完成: ..."）全部重定向到 stderr（`>&2`）
- 只有最后一行 `echo "$INTEGRATION_WT"` 输出路径到 stdout
- `INTEGRATION_WT=$(merge_writers "$ROUND")` 拿到的是纯路径字符串
- 引用 BDD 场景 S004, S005, S017
