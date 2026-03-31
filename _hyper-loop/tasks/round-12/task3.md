## 修复任务: TASK-3
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P1] `cmd_loop` 重启后 `BEST_ROUND`/`BEST_MEDIAN` 不从历史初始化

`cmd_loop`（~line 1056-1058）硬编码：
```bash
local CONSECUTIVE_REJECTS=0
local BEST_ROUND=0
local BEST_MEDIAN=0
```

重启 loop 后，即使 `results.tsv` 中有历史 ACCEPTED 轮次，`BEST_ROUND` 仍为 0。
当连续 5 轮失败触发回退逻辑（~line 1157）时，条件 `BEST_ROUND -gt 0` 不满足，无法回退。

**影响**: 重启后的自动回退机制完全失效，脚本只能持续失败而无法自愈。

### 相关文件
- scripts/hyper-loop.sh (行 1046-1068, `cmd_loop` 函数初始化段)

### 修复策略
1. 在 `BEST_ROUND=0` / `BEST_MEDIAN=0` 初始化之后，加入从 `results.tsv` 读取历史最佳轮次的逻辑
2. 扫描所有 `ACCEPTED` 或 `ACCEPTED_UNCHANGED` 行，找到 median 最高的轮次：
   ```bash
   if [[ -f "${PROJECT_ROOT}/_hyper-loop/results.tsv" ]]; then
     while IFS=$'\t' read -r r med _ dec; do
       [[ "$dec" == ACCEPTED* ]] || continue
       if python3 -c "exit(0 if float('${med}') > float('${BEST_MEDIAN}') else 1)" 2>/dev/null; then
         BEST_ROUND=$r; BEST_MEDIAN=$med
       fi
     done < "${PROJECT_ROOT}/_hyper-loop/results.tsv"
     [[ "$BEST_ROUND" -gt 0 ]] && echo "历史最佳: Round ${BEST_ROUND} (median=${BEST_MEDIAN})"
   fi
   ```
3. 同时初始化 `CONSECUTIVE_REJECTS`：扫描 results.tsv 末尾连续非 ACCEPTED 行数
4. 运行 `bash -n scripts/hyper-loop.sh` 确认语法正确

### 约束
- 只修 scripts/hyper-loop.sh 的 `cmd_loop` 函数初始化段（行 1046-1068）
- 不改循环体内的 BEST_ROUND 更新逻辑（~line 1142-1145）
- 不改回退逻辑（~line 1157-1167）

### 验收标准
- BDD S013: 连续 5 轮失败自动回退到历史最佳轮次
- 重启 loop 后 BEST_ROUND 从 results.tsv 正确恢复
- `bash -n scripts/hyper-loop.sh` 通过
