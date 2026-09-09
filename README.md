# skills

Claude Code plugins I use across projects. This repo is a plugin marketplace.

```bash
claude plugin marketplace add adrianj98/skills
```

## Plugins

### [`adversarial-review`](plugins/adversarial-review) · v0.1.0

A reviewer that assumes your code is wrong, in a context window that never saw you write
it. Modelled on the split-context review [Bun used](https://bun.com/blog/bun-in-rust) to
port a million lines from Zig to Rust — *"1 implementer, 2 or more adversarial reviewers
per implementer. The implementer doesn't review. The reviewer doesn't implement."*

```bash
claude plugin install adversarial-review@adrianj98-skills
```

Ships four levels of the same idea, escalating by how hard it is to skip:

| | invoke | |
|---|---|---|
| reviewer subagent | "have the adversary review my changes" | one pass, cheap |
| review workflow | `/adversarial-review:review` | 4 lenses in parallel, then refutation voting |
| Stop-hook nudge | automatic, once per diff | `adversary off` to silence |
| PR gate | [`examples/github-pr-review.yml`](examples/github-pr-review.yml) | not skippable from your laptop |

[Full README →](plugins/adversarial-review/README.md)

## Adding a plugin to this repo

1. `plugins/<name>/` with a `.claude-plugin/plugin.json`
2. Auto-discovered subdirs: `skills/<name>/SKILL.md`, `agents/*.md`, `commands/*.md`,
   `workflows/*.js`, `hooks/hooks.json`, `bin/`, `.mcp.json`
3. Add an entry to [`.claude-plugin/marketplace.json`](.claude-plugin/marketplace.json)
4. `claude plugin validate .`

## License

MIT
