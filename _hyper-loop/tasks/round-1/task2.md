## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件，特别是 hyper-loop.sh 和 bdd-specs.md。

### 问题
[P0] `record_result` 函数仍然使用 `. "$VERDICT_FILE"`（source）读取 verdict.env，违反 S012 安全读取规范。

背景：
- commit a5a4007 已修复 `cmd_round` 中的 verdict.env 读取（改用 grep）
- 但 `record_result` 函数（行 606-617）被遗漏，仍然 source verdict.env
- verdict.env 中的 `VETO=True`、`TESTER_P0=False` 是 Python 布尔值（大写），source 时可能被 bash 误解析
- 在 `set -euo pipefail` 下，任何解析异常都会导致脚本立即退出

当前代码（行 612）：
```bash
. "$VERDICT_FILE"
```

应该改为（与 cmd_round 行 664-665 一致）：
```bash
DECISION=$(grep '^DECISION=' "$VERDICT_FILE" | cut -d= -f2)
MEDIAN=$(grep '^MEDIAN=' "$VERDICT_FILE" | cut -d= -f2)
SCORES=$(grep '^SCORES=' "$VERDICT_FILE" | cut -d= -f2- | tr -d '"')
```

### 相关文件
- scripts/hyper-loop.sh (行 606-617: record_result 函数)
- _hyper-loop/context/hyper-loop.sh (同步修改)

### 修复方案
1. 删除行 612 的 `. "$VERDICT_FILE"`
2. 替换为 3 行 grep 提取 DECISION、MEDIAN、SCORES
3. printf 行（614）保持不变

### 约束
- 只修 scripts/hyper-loop.sh 和 _hyper-loop/context/hyper-loop.sh 中的 record_result 函数
- 不改函数签名
- 两个文件保持完全一致

### 验收标准
- S012: verdict.env 被安全读取，不出现 "command not found" 错误
- S009: 和议计算后 results.tsv 正确记录
- `bash -n scripts/hyper-loop.sh` 通过
