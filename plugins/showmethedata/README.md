# showmethedata

`/showmethedata UserSession` — how that data is stored and used by the code: where it lives
at rest, what shape it has in each layer and where those shapes disagree, who writes it, who
reads it and what for, how one write and one read travel end to end, and what eventually
deletes it.

```bash
claude plugin install showmethedata@adrianj98-skills
```

The target can be a symbol, a table or column, a field, a file, a directory, or a feature by
name. With no target it maps the repo at the level of stores — every place data lives and
who owns each — and names the symbols worth pointing it at next.

It reads and reports. It never edits a file.

## How it works

It's a prompt, not a tool. There is no script deciding what the model gets to see, because a
script that greps for a name and prints the hits also, quietly, tells the model when to stop
looking — and the copy of the data under a different name is exactly what it would miss.

Instead the skill orients first: which storage libraries the dependency manifest names, where
the migrations, schema and model files are, which config entries point at a store (names only;
gitignored `.env` files are never opened). Then it greps for every spelling of the target —
`userSession`, `user_session`, `UserSession`, "user session" — and follows every writer to
where it puts the data and every reader to where it came from, which is how the Redis key
beside the route and the denormalized column in the other table get found.

It reads the migration rather than the ORM model, because the model is what the code *thinks*
is there. It lines up every definition of the same record — column list, model, DTO,
validation schema, frontend type — field by field and reports where they drift: nullable on
one side and required on the other, a field nothing reads, a `DateTime` that comes back as a
string. It sorts readers into *display*, *decide*, *compute* and *forward*, because a field
that is branched on is where a bad write becomes a bug, and a field that is forwarded is where
the data leaves the codebase. It finds the copies and says what keeps each one in sync, or
that nothing does.

The report leads with a one-paragraph answer, then tables for at-rest stores, shapes and
drift, writers and readers, one write and one read traced step by step, the lifecycle, and
a **Worth knowing** list of only the things it actually saw. Every claim has a `file:line`.
Anything the code doesn't settle — what's actually in the database, runtime config — goes
under **Couldn't tell from the code** rather than being guessed.

## Scope

| | |
|---|---|
| `/showmethedata UserSession` | one record, traced |
| `/showmethedata expires_at` | one field, and every layer that renames it |
| `/showmethedata src/routes/billing.ts` | the data crossing that file |
| `/showmethedata src/billing/` | a map of the stores that directory owns and touches |
| `/showmethedata` | the whole repo, one paragraph per store |

## Installing without the plugin system

```bash
curl -fsSL https://raw.githubusercontent.com/adrianj98/Skills/main/install.sh | bash -s -- showmethedata --global
```

See the [repo README](../../README.md#installing-without-the-plugin-system).
