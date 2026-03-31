# BDD 行为规格 — HyperLoop 脚本自身

## S001: loop 命令启动死循环
Given project-config.env 和 bdd-specs.md 存在
When 执行 `hyper-loop.sh loop 3`
Then 脚本输出 "Round 1/3" 并进入循环
  And 循环跑满 3 轮后正常退出（不崩溃）
  And results.tsv 有 3 行记录

## S002: auto_decompose 生成任务文件
Given _hyper-loop/context/ 和 bdd-specs.md 存在
When auto_decompose 被调用
Then _hyper-loop/tasks/round-N/ 下至少有 1 个 task*.md 文件
  And 每个文件包含"修复任务"和"相关文件"段落
  And 如果 claude -p 失败，降级生成默认 task1.md

## S003: Writer worktree 创建 + trust + 启动
Given task*.md 文件存在
When start_writers 被调用
Then 为每个 task 创建 /tmp/hyper-loop-worktrees-rN/taskM 目录
  And ~/.codex/config.toml 包含该目录的 trust 配置
  And Codex 进程在 tmux window 中启动
  And _ctx/ 目录被复制到 worktree

## S004: Writer 完成后 diff 被正确 commit
Given Writer 写了 DONE.json status=done 且改了文件
When merge_writers 被调用
Then HyperLoop 元数据文件（DONE.json, WRITER_INIT.md, TASK.md, _writer_prompt.md, _ctx/）被删除
  And 然后执行 git add -A && git commit（只包含业务代码变更）
  And squash merge 到 integration 分支成功（不是 "already up to date"）
  And task*.patch 和 task*.stat 文件被生成
  And 多 Writer 不会因元数据文件冲突

## S005: diff 审计拦截越界修改
Given Writer 改了 TASK.md 未指定的文件
When audit_writer_diff 被调用
Then 返回非零退出码
  And 该 Writer 的产出被跳过不合并

## S006: Writer 超时处理
Given Writer 15 分钟未写 DONE.json
When 超时触发
Then DONE.json 被写入 status=timeout
  And 该 Writer 被标记为 failed

## S007: Tester 启动并生成报告
Given App 已构建（对本项目=bash -n 通过）
When run_tester 被调用
Then Tester Claude 子进程在 tmux 中启动
  And 15 分钟内生成 reports/round-N-test.md
  And 超时时生成空报告而非崩溃

## S008: 3 Reviewer 启动并产出评分
Given Tester 报告存在
When run_reviewers 被调用
Then 3 个 Reviewer 在 tmux 中启动（Gemini + Claude + Codex）
  And 10 分钟内各自生成 scores/round-N/reviewer-{a,b,c}.json
  And JSON 包含 "score" 字段
  And 如果文件不存在，从 pane 输出提取 JSON

## S009: 和议计算正确
Given 3 个评分文件存在 scores=[5.0, 6.0, 7.0]
When compute_verdict 被调用
Then 中位数 = 6.0
  And DECISION = ACCEPTED（如果 > prev_median）
  And verdict.env 可以被安全读取（不崩 bash）

## S010: 一票否决（score < 4.0）
Given scores=[3.5, 6.0, 7.0]
When compute_verdict 被调用
Then DECISION = REJECTED_VETO
  And 记录到 results.tsv

## S011: Tester P0 否决
Given Tester 报告包含 "P0" 和 "fail"
When compute_verdict 被调用
Then DECISION = REJECTED_TESTER_P0

## S012: verdict.env 安全读取
Given verdict.env 包含 MEDIAN=0.0 和 SCORES="1.0 2.0 3.0"
When 脚本读取 verdict.env
Then DECISION 和 MEDIAN 被正确提取
  And 不会出现 "command not found" 错误

## S013: 连续 5 轮失败自动回退
Given results.tsv 有 5 行 REJECTED
  And archive/round-2/git-sha.txt 存在且得分最高
When 第 6 轮开始
Then 代码回退到 Round 2 的 git sha
  And consecutive_rejects 重置为 0

## S014: STOP 文件优雅退出
Given _hyper-loop/STOP 文件存在
When 循环检查到 STOP
Then 当前轮不执行
  And 脚本正常退出（exit 0）
  And STOP 文件被删除

## S015: worktree 清理
Given Round N 完成
When cleanup_round 被调用
Then /tmp/hyper-loop-worktrees-rN/ 不存在
  And hyper-loop/rN-* 分支被删除
  And tmux writer windows 被关闭

## S016: macOS timeout 兼容
Given macOS 没有 timeout 命令但有 gtimeout
When 脚本启动
Then timeout 函数可用（不报 command not found）

## S017: 多 Writer 同文件冲突处理
Given task1 和 task2 都改了同一个业务文件（非元数据）
When merge_writers 合并
Then 元数据文件已预先清理，不会导致 false conflict
  And 第一个 Writer 成功 merge
  And 如果第二个 Writer 与第一个有真实代码冲突则 merge --abort 并标记 deferred
  And 如果没有代码冲突则两个都成功 merge
  And 脚本不崩溃
