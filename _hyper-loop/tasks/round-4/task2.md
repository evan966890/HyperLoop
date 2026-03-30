## 修复任务: TASK-2
### 上下文
先读 _ctx/ 下所有文件。
### 问题
[P1] audit_writer_diff()（L259）使用 `git diff --name-only HEAD` 只能检测已跟踪文件的修改，无法发现 Writer 新建的未跟踪文件。如果 Writer 在允许列表外新建文件，审计不会拦截，但后续 `git add -A` 会将其提交，绕过审计。
### 相关文件
- scripts/hyper-loop.sh (L245-296, audit_writer_diff 函数)
### 约束
- 只修 scripts/hyper-loop.sh
- 只改 audit_writer_diff 函数内部
- 不改 CSS
### 验收标准
引用 BDD 场景 S005: Writer 改了（或新建了）TASK.md 未指定的文件时，audit_writer_diff 返回非零退出码，该 Writer 的产出被跳过不合并。CHANGED_FILES 同时包含已跟踪文件的改动和新建的未跟踪文件。
