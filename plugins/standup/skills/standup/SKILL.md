---
name: standup
description: Write a very short standup list of what was worked on since yesterday morning, from the commits in every worktree of the current repo, your GitHub PRs, your Jira issues, and any aj-log.md in those worktrees. Use when the user asks for a standup, a daily update, or what they worked on yesterday.
argument-hint: "[since WHEN] [everyone]"
allowed-tools: Bash, mcp__claude_ai_Atlassian_Rovo__searchJiraIssuesUsingJql, mcp__claude_ai_Atlassian_Rovo__getAccessibleAtlassianResources
---

Since yesterday morning: commits across every worktree of this repo (branch, time, sha, subject, then the message body indented), your GitHub PRs, and what each worktree's aj-log.md gained:

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/standup.sh" 2>&1`

The user invoked this with `$ARGUMENTS`. If that asks for a different window ("since friday",
"last 3 days") or for everyone's commits, rerun
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/standup.sh" --since "<when>"` and/or `--everyone`
and use that output instead.

**Jira.** If a Jira tool is available (an Atlassian MCP server's JQL search, or a `jira` /
`acli` CLI), search for issues you touched since the cutoff:
`assignee = currentUser() AND updated >= "<since date>"` plus
`status CHANGED BY currentUser() AFTER "<since date>"`, using the date the output above shows
after "updated since". Keep the key, summary and status. If there is no Jira tool, or it
fails, skip Jira without mentioning it.

Turn all of it into a standup list:

- **Grouped by project or page.** Put a bold heading over each group (`**LLM Insights**`,
  `**Workflow page**`). Group by what the work is for, not by ticket. Anything that fits no
  group goes under `**Other**`.
- **One bullet per piece of work, not per commit.** These all make one bullet: a fix and its
  follow-ups, a feature and its tests, the same change on two branches, the PR it went out in,
  the Jira issue it closes, and the aj-log.md entry about it.
- **Under about 12 words each**, past tense, saying what changed, not how. No lists of
  sub-features. No shas, times, branch names or file paths.
- **End each bullet with its keys** (`— AL-123, #412`). Add `(draft)` or `in progress` if
  the work isn't merged yet.
- **Only your own work.** Other people's squash-merged PRs that show up on your branches
  don't count. Reviews and Jira-only moves do: "reviewed Sam's retry PR", "picked up AL-130".
- **Read the commit bodies.** They say what a change was for. A vague subject ("fix",
  "update") usually has the real story in its body.
- **Use aj-log.md for context, not as a source of bullets.** Use it to say *why*, or to
  catch work that isn't committed yet. Only entries dated after the cutoff count.
- **Drop the noise** — typo fixes, formatting, version bumps, "wip" — unless that's all
  there is.
- **Nothing but the grouped list.** No title, intro or closing summary.

If there's nothing at all, say so in one line with the cutoff date, e.g. `Nothing since Mon Sep 14 06:00.`
