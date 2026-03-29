## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] S001: 循环输出前缀不符合 BDD 规格

BDD S001 要求输出 `Round 1/3`，但 line 849 实际输出 `LOOP: Round 1/3`，多了 `LOOP: ` 前缀。

当前代码 (line 849):
```bash
echo "  LOOP: Round ${ROUND}/${MAX_ROUNDS}"
```

BDD 期望输出:
```
Round 1/3
```

### 相关文件
- scripts/hyper-loop.sh (line 847-850, 循环头部输出)

### 约束
- 只改 `scripts/hyper-loop.sh` 中 line 849 的 echo 语句
- 保持分隔线（line 848, 850）不变
- 不改 CSS

### 验收标准
- 引用 BDD 场景 S001: 脚本输出 "Round 1/3"（不含 LOOP: 前缀）
- `bash -n scripts/hyper-loop.sh` 通过
