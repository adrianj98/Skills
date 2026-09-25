# caveman

`/caveman` makes replies short and plain for the rest of the session. `/caveman off` turns it
back.

```bash
claude plugin install caveman@adrianj98-skills
```

It's a single, light level of [JuliusBrussee/caveman](https://github.com/juliusbrussee/caveman).
Sentences stay grammatical. What goes is the filler: pleasantries, preamble, hedging,
restating the question, and the summary at the end. The answer comes first. Code, commands,
error messages and technical names are never shortened. Anything written to a file, such as
commits, PRs and docs, stays normal prose. Security warnings and irreversible actions are
written out in full.

It keeps to the light level because the savings are small and the risk is real. JetBrains
measured the original on 86 real coding tasks and found 8.5% fewer output tokens with quality
flat. Output tokens are a small share of what an agent session costs, so pushing past light
into fragments saves little and makes answers harder to read.

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- caveman --global
```
