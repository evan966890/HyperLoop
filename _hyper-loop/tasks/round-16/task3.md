## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] **cmd_status 重复定义 + Tester 超时消息错误**

两个独立 bug 合并修复（均为局部文本修改，互不影响）：

1. **cmd_status 重复定义** (line ~697 和 line ~957)：第一个 cmd_status 功能不全（无最佳轮次显示），被第二个覆盖。应删除第一个定义。
2. **Tester 超时消息错误** (line ~421)：实际超时 900s=15 分钟，但错误消息写 "Tester 未在 10 分钟内完成"。应改为 "15 分钟"。

### 相关文件
- scripts/hyper-loop.sh (line ~697-703 第一个 cmd_status；line ~421 Tester 超时消息)
### 约束
- 只修 scripts/hyper-loop.sh
- 删除第一个 cmd_status 函数定义（约 line 697-703）
- 将 "10 分钟" 改为 "15 分钟"（line ~421）
- 不改其他函数逻辑
### 验收标准
- `grep -c 'cmd_status()' scripts/hyper-loop.sh` 返回 1（只有一个定义）
- `grep '10 分钟' scripts/hyper-loop.sh` 无匹配
- `bash -n scripts/hyper-loop.sh` PASS
- 引用 BDD 场景 S007（Tester 启动并生成报告 — 超时消息准确）
