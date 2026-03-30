## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Reviewer fallback 机制失效：score=0 的文件非空，`! -s` 检查通过，fallback 不触发。

run_reviewers 第 477-482 行的 fallback 只检查文件是否为空（`! -s`），但实际情况：
- Reviewer 命令失败时 EXTRACT_PY 可能输出 `{"score":0}` 或 `{"score":5}` 的 fallback JSON
- 文件非空但 score=0 → `! -s` 为 false → fallback 不触发
- 3 个 score=0 全部 < 4.0 → REJECTED_VETO 每一轮

同时存在注释/代码不一致：
- 第 476 行注释: "fallback 给 3 分"
- 第 479 行 JSON: `"score":5`
- 第 480 行 echo: "fallback to score 3"

### 相关文件
- scripts/hyper-loop.sh (第 476-482 行: run_reviewers fallback 逻辑)

### 修复方案
改 fallback 检查：不仅检查文件是否为空，还验证 score > 0。统一 fallback 分为 5（中立分，不触发 veto）。

替换第 476-482 行为：
```bash
  # 确保所有评分文件存在且 score > 0（fallback 给中立分 5）
  for NAME in reviewer-a reviewer-b reviewer-c; do
    local SCORE_VAL
    SCORE_VAL=$(python3 -c "import json; print(json.load(open('${SCORES_DIR}/${NAME}.json'))['score'])" 2>/dev/null || echo "0")
    if [[ ! -s "${SCORES_DIR}/${NAME}.json" ]] || python3 -c "exit(0 if float('${SCORE_VAL}') <= 0 else 1)" 2>/dev/null; then
      echo '{"score":5,"issues":[],"summary":"Reviewer 超时或无效输出，中立分5"}' > "${SCORES_DIR}/${NAME}.json"
      echo "  ⚠ ${NAME} fallback to score 5" >&2
    fi
  done
```

### 约束
- 只修 scripts/hyper-loop.sh
- 只改 run_reviewers 函数的 fallback 逻辑（第 476-482 行）
- fallback 分数必须 >= 4.0（避免触发 S010 一票否决）

### 验收标准
引用 BDD 场景 S008: JSON 包含 "score" 字段，且 score > 0
引用 BDD 场景 S010: 一票否决（score < 4.0）— fallback 分不应触发 veto
