## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Reviewer 评审请求中 score 目标文件名使用字面量中文"你的角色名"，导致 3 个 Reviewer 都不知道写哪个文件。

line 450: `echo "把 JSON 写入文件 ${SCORES_DIR}/你的角色名.json 后输出：HYPERLOOP_REVIEW_DONE"`

"你的角色名" 是中文字面量，不是 bash 变量。3 个 Reviewer（reviewer-a/b/c）看到的是同一个请求，无法确定自己该写 `reviewer-a.json` 还是 `reviewer-b.json` 还是 `reviewer-c.json`。

因果链：
1. Reviewer 不知道写哪个文件 → score 文件未创建
2. 降级从 pane 输出提取（line 481-503）→ 也找不到有效 JSON → 写默认 `{"score":0}`
3. score=0 < 4.0 → 触发一票否决 (S010) → REJECTED_VETO
4. 连续 8 轮全部 REJECTED_VETO

当前流程：评审请求在循环外生成一次（line 433-451），然后 paste 给 3 个 reviewer。
需要改为在循环内为每个 reviewer 生成带各自精确文件名的请求。

### 相关文件
- scripts/hyper-loop.sh (line 427-465, 重点 line 433-451 评审请求生成 和 line 455-465 reviewer 循环)

### 约束
- 只修 scripts/hyper-loop.sh 中 `run_reviewers` 函数
- 保持 3 reviewer 并行启动的结构
- 将评审请求生成移入 for 循环内部，每个 reviewer 收到带 `${SCORES_DIR}/${NAME}.json` 精确路径的请求
- 或者将通用部分保留在外，只替换 line 450 的"你的角色名"为 `\${NAME}` 并在循环内替换
- 不改 CSS

### 验收标准
引用 BDD 场景 S008（3 Reviewer 启动并产出评分）
- reviewer-a 收到的请求包含 `${SCORES_DIR}/reviewer-a.json`
- reviewer-b 收到的请求包含 `${SCORES_DIR}/reviewer-b.json`
- reviewer-c 收到的请求包含 `${SCORES_DIR}/reviewer-c.json`
- 等待逻辑（line 468-477）和降级提取逻辑（line 480-503）不受影响
- `bash -n scripts/hyper-loop.sh` 语法检查通过
