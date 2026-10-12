---
name: progress
description: Tell the state of a branch and its pull request in two sections, what it is about and where it stands. Use when the user asks for progress, the status of a PR or branch, where a PR is at, whether it is ready to merge, what is blocking it, or what is left to do on it.
argument-hint: "[PR number | branch | PR url — nothing = the checked-out branch]"
allowed-tools: Bash, mcp__claude_ai_Atlassian_Rovo__searchJiraIssuesUsingJql, mcp__claude_ai_Atlassian_Rovo__getJiraIssue
---

The branch against its base, the working tree, the commits with their bodies, the PR's
reviews, review threads, checks, mergeability and conversation, and what aj-log.md says:

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/progress.sh" $ARGUMENTS 2>&1`

If that line is still a command rather than its output, this host (Devin, for one) neither
runs it nor sets `${CLAUDE_PLUGIN_ROOT}`. The plugin root is two directories above this
skill's base directory: run `scripts/progress.sh` from there with `bash`, passing
`$ARGUMENTS`, and use its output.

**Jira.** If the output ends with `== issue keys` and a Jira tool is available (an Atlassian
MCP server, or a `jira` / `acli` CLI), fetch each key's summary and status. If there is no
Jira tool, or it fails, skip Jira without mentioning it.

Write exactly two sections and nothing else: no title above them, no closing line. Each
section starts with its heading on its own line, in bold: `**What it's about**`, then
`**State**`.

**What it's about**

One paragraph, two to four sentences. Open with the PR number and title in bold, linked to
the PR, or with the branch name if there is no PR. Then: the problem, what changed, and why it was done
that way. The PR description and the commit bodies say what; the aj-log.md lines carry the
why that reached neither. Say what the change does for the product, in plain words, not
which files moved. If the description says what it deliberately leaves out, say that in one
clause.

**State**

Bullets, each under about fifteen words, in this order. A bullet with nothing to say is
left out, not written as "none".

- **Where it is.** No PR yet, draft, open, merged, or closed, with how long ago it was
  opened or merged.
- **Review.** Approved by whom, changes requested by whom, waiting on whom, or nobody
  asked yet. The number of unresolved threads and what the open ones want.
- **Checks.** Green, failing (name the failing ones only), or still running.
- **Merge.** Conflicts with the base, behind it by how many commits, or up to date.
  Auto-merge if it's on.
- **Local.** Uncommitted changes, unpushed commits, or a branch that isn't the one checked
  out. Only when the branch is checked out here.
- **Conversation.** A question or a blocker someone posted that nobody has answered.
- **Jira.** Each key with its status, when there is one.
- **Next.** The one thing that gets it merged. If it's merged, that it's done and the
  branch can go.

When the PR is merged or closed, the branch's standing against its base no longer matters:
write Where it is, Review only if someone reviewed, Local only for uncommitted changes, and
Next. Leave out Checks and Merge.

Numbers only where they change what the reader does: behind by 18, three unresolved. No
shas, no times of day, no file paths, and no URL other than the PR's own in the first
section. Passing checks are a count, never a list. A branch with no PR is a state in its
own right: say so and describe the branch. The first line of the output says whether the
branch is the one checked out here; the Local bullet follows that line, not a guess. The report is a reading, not a to-do list, so
no shell commands.
