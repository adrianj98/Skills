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

- **One bullet per piece of work, not per commit.** A fix and its follow-ups, a feature and
  its tests, the same change landing on two branches, the PR it went out in, the Jira issue it
  closes and the aj-log.md entry about it: one bullet. Put the Jira key or PR number at the end
  when there is one (`— ALD-123`, `— #412`).
- **Read the commit bodies** — they say what the change was for; a vague subject ("fix",
  "update") usually has the real story in its body.
- **aj-log.md is context, not a source of bullets on its own** — use it to say *why*, or to
  catch work that isn't committed yet. Only entries dated after the cutoff count.
- **Reviews and Jira-only moves count** — "reviewed Sam's retry PR", "picked up ALD-130".
- **A few plain words each**, past tense, the way you'd say it out loud. No shas, times,
  branch names, or file paths.
- **Drop the noise** — typo fixes, formatting, version bumps, "wip" — unless that's all there is.
- **Nothing but the list.** No heading, no intro, no summary after.

If there's nothing at all, say so in one line with the cutoff date, e.g. `Nothing since Mon Sep 14 06:00.`
