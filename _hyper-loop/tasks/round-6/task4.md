## 修复任务: TASK-4
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] 三个代码质量/健壮性 bug：

1. **P1-003 PREV_MEDIAN 空值导致 python 崩溃**: L846-848 `tail -1 results.tsv | cut -f2 || echo 0` — 若 results.tsv 存在但为空，cut 返回空字符串（exit 0），`|| echo 0` 不触发。空字符串传入 `compute_verdict` 的 python `float('')` 引发 ValueError，循环崩溃。

2. **P1-005 cmd_status 重复定义**: L670 和 L932 两处定义 `cmd_status` 函数，后者覆盖前者。L670 是简化版死代码，增加维护负担和困惑。

3. **P1-006 fallback 分数注释不一致**: L476 注释"fallback 给 3 分"但 L479 实际代码写 `"score":5`，注释误导维护者。

### 相关文件
- scripts/hyper-loop.sh (L846-848, cmd_loop 中 PREV_MEDIAN 赋值)
  - 改为两行: `PREV_MEDIAN=$(tail -1 ... | cut -f2)` 然后 `PREV_MEDIAN="${PREV_MEDIAN:-0}"`
- scripts/hyper-loop.sh (L670-676, 旧版 cmd_status 函数)
  - 删除 L670-676 整个旧版 cmd_status
- scripts/hyper-loop.sh (L476, fallback 注释)
  - L476: 注释改为 `# 确保所有评分文件存在（fallback 给 5 分）`
### 约束
- 只修改 scripts/hyper-loop.sh 中指定的三处
- 不改 CSS
- 不改业务逻辑，仅修正健壮性和代码卫生
### 验收标准
引用 BDD 场景 S009: compute_verdict 在 results.tsv 为空时不崩溃，PREV_MEDIAN 默认为 0
