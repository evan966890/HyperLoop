## 修复任务: TASK-1
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P0] merge_writers() 的信息性 echo（L311、L321、L328、L350、L354、L359）和返回值 echo "$INTEGRATION_WT"（L360）共用 stdout。调用方 `INTEGRATION_WT=$(merge_writers "$ROUND")`（L854）捕获全部 stdout，导致变量包含多行垃圾文本而非纯路径。后续 `build_app "$INTEGRATION_WT"` 中 `cd "$BUILD_DIR"` 必定失败，整个流程在错误目录上运行。
### 相关文件
- scripts/hyper-loop.sh (L298-361, merge_writers 函数)
### 约束
- 只修 scripts/hyper-loop.sh
- 只改 merge_writers 函数内部
- 不改函数签名和返回值语义
- 不改 CSS
### 验收标准
引用 BDD 场景 S004: merge_writers 被调用后，squash merge 到 integration 分支成功，task*.patch 和 task*.stat 文件被生成。调用方 `INTEGRATION_WT=$(merge_writers ...)` 得到的值是纯路径（单行，不含信息性文本）。
