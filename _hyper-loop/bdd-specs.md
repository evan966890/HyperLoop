# BDD 行为规格 — HyperLoop v5.5

## S001: loop 命令启动死循环
Given project-config.env 和 bdd-specs.md 存在
When 执行 `hyper-loop.sh loop 3`
Then 脚本输出 "Round N/M" 并进入循环
  And 循环跑满 3 轮后正常退出（不崩溃）
  And results.tsv 有 3 行新记录

## S002: auto_decompose 生成任务文件
Given _hyper-loop/context/ 和 bdd-specs.md 存在
When auto_decompose 被调用
Then _hyper-loop/tasks/round-N/ 下至少有 1 个 task*.md 文件
  And 每个文件包含"修复任务"和"相关文件"段落
  And 如果 claude -p 失败，降级生成默认 task1.md

## S003: Writer worktree 创建 + 环境准备 + 启动
Given task*.md 文件存在且 parallel-plan.txt 已生成
When start_writers 被调用
Then Writer 数量由 parallel-plan.txt 决定（1~N 个）
  And 每个 Writer 创建 /tmp/hyper-loop-worktrees-rN/taskM 目录
  And prepare_worktree 为每个 worktree symlink SHARED_DEPS + 设置 CARGO_TARGET_DIR
  And ~/.codex/config.toml 包含该目录的 trust 配置
  And Codex exec 后台子进程启动（stdin 管道注入 prompt）
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

## S005b: diff 审计拦截评估文件修改
Given Writer 改了 _hyper-loop/ 下的评估文件（bdd-specs.md, contract.md, compute_verdict 逻辑）
When audit_writer_diff 被调用
Then 返回非零退出码（即使 TASK.md 列出了该文件）
  And 日志输出"评估文件不可修改"

## S006: Writer 超时处理
Given Writer 15 分钟未写 DONE.json
When 超时触发
Then DONE.json 被写入 status=timeout
  And 该 Writer 被标记为 failed

## S007: Tester 静态验证
Given App 已构建（bash -n 通过 或 BUILD_CMD 成功）
When run_tester 被调用
Then Tester Claude 子进程以管道模式启动（claude -p -）
  And 10 分钟内生成 reports/round-N-test.md
  And 报告末尾包含结构化摘要行 `BDD_PASS: N/M` 和 `P0_COUNT: N`
  And 超时时生成空报告而非崩溃

## S007b: Tester 动态验证（当 LAUNCH_CMD 存在时）
Given project-config.env 的 LAUNCH_CMD 非空
When run_tester 被调用
Then 静态验证完成后，启动 app（eval LAUNCH_CMD）
  And 使用 Playwright（web）或 screencapture（native）截图
  And 截图保存到 screenshots/round-N/
  And 报告引用截图路径并标注 BDD 场景通过/失败
  And 测试完成后关闭 app 进程

## S008: 3 Reviewer 启动并产出评分
Given Tester 报告存在
When run_reviewers 被调用
Then 3 个 Reviewer 以并行子进程启动（Gemini -p / Claude -p / Codex exec）
  And Reviewer prompt 包含 project-brief.md（BMAD 设计文档精华）
  And 5 分钟内各自生成 scores/round-N/reviewer-{a,b,c}.json
  And JSON 包含 "score" 字段
  And fallback score 5（超时或无输出时）

## S008b: Reviewer 引用设计文档评分
Given project-brief.md 存在且包含设计要求
When Reviewer 评分
Then issues 中能引用设计文档的具体章节或要求
  And 评分理由与用户原始设计意图对齐（不是自创标准）

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
Given Tester 报告包含结构化摘要 `P0_COUNT: N`（N > 0）
When compute_verdict 被调用
Then DECISION = REJECTED_TESTER_P0
  And 如果报告无结构化摘要，fallback 到正则检测 `### P0` heading + BDD FAIL

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

## S018: auto_decompose 检测文件交集决定并行度
Given auto_decompose 生成了 3 个 task，task1 改 a.rs，task2 改 b.rs，task3 改 a.rs
When 文件交集检测执行
Then task1 和 task3 有交集 → 合并为 1 个 task
  And parallel-plan.txt 写入 PARALLEL=false WRITER_COUNT=1
  And 最终只有 task1.md（合并版）

## S019: prepare_worktree symlink 共享依赖
Given SHARED_DEPS="tauri-app/node_modules" 且主目录有该目录
When prepare_worktree 被调用
Then worktree 中 tauri-app/node_modules 是指向主目录的 symlink
  And Cargo 项目使用独立 CARGO_TARGET_DIR（不 symlink target/）

## S020: cmd_loop 启动时清理残留
Given /tmp/hyper-loop-worktrees-r5/ 残留自上次运行
When cmd_loop 启动
Then /tmp/hyper-loop-worktrees-* 被清理
  And hyper-loop/* 分支被删除
  And stale tmux session 被关闭

## S021: 脚本异常退出时 trap 写日志
Given 脚本在 line 500 因未处理错误退出
When ERR trap 触发
Then loop.log 包含 "[FATAL] line 500 exit=1 cmd=..." 
  And EXIT trap 也写一行 "[EXIT] exit=1"

## S022: 所有任务改同一文件时 fallback 单 Writer
Given auto_decompose 生成 4 个 task 全部改 scripts/hyper-loop.sh
When 文件交集检测执行
Then parallel-plan.txt 写入 PARALLEL=false WRITER_COUNT=1
  And 4 个 task 合并为 task1.md

## S023: cmd_monitor 返回进程状态
Given 循环正在运行（PID 存在）
When cmd_monitor 被调用
Then 输出 "状态: 运行中 (PID XXXXX)"
  And 输出心跳时间
  And 输出最近 3 轮 results.tsv

## S024: 心跳超时 warning
Given heartbeat 文件最后更新在 6 分钟前
When cmd_monitor 被调用
Then 输出 "⚠ 心跳超时（>5分钟），可能卡住"

## S025: ACCEPTED merge 前 stash dirty working tree
Given working tree 有未提交修改
When ACCEPTED 分支执行 merge to main
Then 先 git stash push
  And merge 完成后 git stash pop
  And merge 不会因 dirty tree 静默失败

## S026: 达标后写 REACHED_GOAL 并停止
Given 中位数达到 >= 8.0
When 达标检查触发
Then _hyper-loop/REACHED_GOAL 文件被创建（含 ROUND 和 MEDIAN）
  And 循环 break（不自动继续）
  And cmd_monitor 检测到 REACHED_GOAL 输出 "🎉 目标达成！"

## S027: Reviewer prompt 超过 100KB 时自动裁剪
Given Reviewer prompt 文件大小 > 100KB
When run_reviewers 准备发送 prompt
Then prompt 被裁剪为：头部 30 行 + diff stat + Tester 报告前 50 行
  And 日志输出裁剪前后大小
