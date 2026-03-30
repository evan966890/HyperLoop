## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1-4] PREV_MEDIAN 空值导致 Python float('') 崩溃，set -e 下脚本终止

L848-850 读取 PREV_MEDIAN：
```bash
local PREV_MEDIAN=0
if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
  PREV_MEDIAN=$(tail -1 "${PROJECT_ROOT}/_hyper-loop/results.tsv" | cut -f2 || echo 0)
fi
```

当 results.tsv 存在但为空（0 字节），`tail -1` 返回空字符串，`cut -f2` 对空输入也返回空字符串且 exit code 为 0，`|| echo 0` 不触发。PREV_MEDIAN 变成空字符串 `""`。

后续 compute_verdict (L521) 中 Python `float('')` 抛出 ValueError，在 `set -e` 下脚本直接终止。

对比 L813 处用了 `[[ -f ... && -s ... ]]`（检查文件非空），L848 只检查 `-f`，遗漏了 `-s`。

### 相关文件
- scripts/hyper-loop.sh (L848-851, cmd_loop 内 PREV_MEDIAN 读取)

### 约束
- 只修 L848-851 的 PREV_MEDIAN 读取逻辑
- 推荐双重保护：条件改为 `-f && -s` + 变量空值兜底 `${PREV_MEDIAN:-0}`
- 不改 CSS

### 验收标准
引用 BDD S009: results.tsv 为空文件时 PREV_MEDIAN 回退到 0，compute_verdict 不崩溃，脚本继续运行。`bash -n` 通过
