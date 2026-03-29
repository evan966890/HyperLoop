## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。

### 问题
[P0] Reviewer 评审请求中 score 文件名使用字面量"你的角色名"，导致 Reviewer 不知道写哪个文件

line 447: `echo "把 JSON 写入文件 ${SCORES_DIR}/你的角色名.json 后输出：HYPERLOOP_REVIEW_DONE"`

这行的 `你的角色名` 是中文字面量，不是变量。3 个 Reviewer 都看到同样的请求，不知道自己该写 `reviewer-a.json` 还是 `reviewer-b.json` 还是 `reviewer-c.json`。

当前流程：评审请求在循环外生成一次（line 431-448），然后 paste 给 3 个 reviewer。需要改为每个 reviewer 生成带各自名字的请求。

结果：score 文件未写入 → 降级提取也找不到 JSON → 默认 `{"score":0}` → 触发 veto（score < 4.0）

### 相关文件
- scripts/hyper-loop.sh (line 425-462, 重点 line 431-448 和 line 452-462)

### 约束
- 只修 scripts/hyper-loop.sh
- 保持 3 reviewer 并行启动的结构
- 每个 reviewer 的评审请求需要包含其准确的 score 文件名

### 验收标准
引用 BDD 场景 S008（3 Reviewer 启动并产出评分）
- 每个 Reviewer 收到的评审请求中包含精确的目标文件路径，如 `${SCORES_DIR}/reviewer-a.json`
- 等待逻辑和降级提取逻辑不受影响
