---
name: showmethedata
description: Explain how a piece of data is stored and used by the code — where it lives at rest, what shape it has, who writes it, who reads it, how it moves between layers, and when it dies. Point it at a file, a type, a table, a field, a feature, or a directory. Use when the user asks where something is stored, how data flows through the code, who reads or writes a value, what shape a record has, or says "show me the data".
argument-hint: "TARGET   (a file, symbol, table, field, feature or directory; nothing = the whole repo)"
allowed-tools: Bash, Read, Grep, Glob
---

The user invoked this with `$ARGUMENTS`.

- **a target** — a path, a symbol, a table or column, a field, a feature by name. Explain
  that one thing's data.
- **no target** — map the repo: every place data lives, and who owns each. Stores, not
  fields. Stop at the level where one more paragraph would be a field list.

This skill reads and reports. It never edits a file.

## 0. Orient

Before chasing the target, learn where this repo keeps data at all. Ten minutes here saves
missing a store later.

- The dependency manifest (`package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`,
  `Gemfile`…): which ORMs, drivers, caches, queues, object-storage and client-state
  libraries are installed. Each one is a kind of store to look for.
- Files whose path says where the shape lives: `migrations/`, `schema.*`, `*.prisma`,
  `*.sql`, `models/`, `entities/`, `types/`, `*.proto`, `*.graphql`, `openapi.*`.
- Config that names a store: `.env.example`, `docker-compose.yml`, `config/*`. Read the
  **names** of entries like `DATABASE_URL` or `REDIS_URL`; never print a value, and never
  open a gitignored `.env`.

Then find the target. Grep for every spelling it could have — `userSession`, `user_session`,
`user-session`, `UserSession`, and the words with a space between — and for the table or
column name if that differs from the code's name. Cast the net wide; you will narrow it in
the steps below. **Do not stop at the first list of hits.** A copy of the data under another
name (a Redis key, a denormalized column, a renamed DTO field) never shows up in a grep for
the original, so every writer you find in step 4 has to be followed to where it puts the
data, and every reader in step 5 to where the data came from.

## 1. Resolve the target

Decide what the user actually pointed at before tracing anything:

- **A path** — the data that file owns or handles. A model file is about its model; a route
  file is about the payloads crossing it; a directory is a map, not a trace.
- **A symbol, table or field** — grep for its definition: `class`, `interface`, `type`,
  `model`, `CREATE TABLE`, `def`, `struct`. If the same name is defined in more than one place (a Prisma model *and* a TS interface *and* a
  Zod schema), they are all the same data in different shapes; keep them all.
- **A concept** ("billing", "the onboarding state") — no single definition. Find the two or
  three symbols that carry it and trace those.

If nothing matched, say so and list the nearest names the grep did find. Do not invent.

## 2. At rest — where it lives

For every place the data sits when no code is running, name the store and the file that
proves it. The candidates, roughly in order of how often they get forgotten:

- a database table or collection, and the migration or schema that defines it
- a cache (Redis, in-process LRU, memoized module state) — a **copy** with its own lifetime
- a queue or topic — data in flight, with its own schema
- files on disk, object storage, a browser's `localStorage` / IndexedDB / cookies
- client state (Redux, Zustand, React Query cache) — also a store, also can go stale
- environment and config — data too, and the part most likely to differ per deploy
- a third party's API as the system of record, with this repo holding only an id
- module-level mutable state — a singleton `Map` is a database with no persistence

For a database store, read the migration or schema, not the ORM model: the model is what the
code *thinks* is there. Note keys, uniqueness, indexes, nullability, foreign keys, and
whether deletes are soft. Where two stores hold the same data, say which is authoritative
and what keeps the other one in sync — or that nothing does.

## 3. Shape — and where the shapes disagree

Find every definition of the same record: column list, ORM model, API DTO, validation
schema, frontend type, protobuf message. Line them up field by field and look for drift:

- nullable in the column, required in the type (or the reverse)
- a field the type has and the table doesn't, or that the table has and nothing reads
- names that differ across layers (`created_at` / `createdAt` / `created`) and where they
  get renamed
- enums whose value sets don't match
- types that lose information at a boundary: `DateTime` → ISO string → `Date` again with a
  timezone change, `numeric` → JS `number`, `bigint` → JSON

Drift is the finding most worth reporting. Each one gets a `file:line` on both sides.

## 4. Writers

Every site that creates, updates or deletes the data, and the entry point that leads there:
an HTTP route, a job, a CLI command, a migration or backfill, a seed, a webhook handler, a
test fixture. For each: what validates the input before the write (or nothing does), whether
it runs in a transaction, and whether it also has to update a copy (a cache, a search index,
a denormalized column) — and does.

Follow the ORM through. `prisma.user.update` is a write; so is the raw SQL in the job
nobody remembers, and so is the `redis.set` beside the route.

## 5. Readers

Every site that reads it, and what the read is *for*:

| | |
|---|---|
| **display** | rendered to a user, returned from an API |
| **decide** | branched on — the code behaves differently depending on the value |
| **compute** | folded into something else that is then stored or shown |
| **forward** | sent onwards — to another service, a log line, analytics, an email |

The **decide** and **forward** readers matter most. A field that decides something is where a
bad write becomes a bug; a field that is forwarded is where it leaves this codebase, which
matters a great deal if it is personal data or a secret.

## 6. Movement — trace one path each way

Pick the most common write and the most common read and walk them end to end, as numbered
steps with a `file:line` each: where the value enters, what validates it, what transforms
it, where it lands; then where it is fetched, what reshapes it, how it is serialized, and
who receives it. Name each boundary the data crosses (HTTP, JSON, wire format, process,
file) and what changes about it there. One trace of each is enough; the tables above
cover the rest.

## 7. Lifecycle

Created when. Mutated by what, how often. Deleted or expired by what — a job, a TTL, a
cascade, a user action, or never. Migrated how, when the shape changed last (the migrations
directory usually tells this story better than the git log). Whether orphans are possible.

## 8. Sensitive?

If the data is personal, financial, or a credential, say so and add three facts: where it
is logged, whether it is encrypted or hashed at rest, and which check gates reading it.
This is a statement of what the code does, not a security review; don't rate it.

## Report

Lead with the answer in one short paragraph, the way you'd tell a colleague: *what it is,
where it lives, who writes it, who reads it.* Then, in this order, skipping any section
that has nothing in it:

- **At rest** — a table: store · location · schema source · `file:line`
- **Shapes** — each definition with its `file:line`, then the drift, each with both sides
- **Writers** — `file:line` · entry point · validation · touches which copies
- **Readers** — `file:line` · entry point · display / decide / compute / forward
- **One write, one read** — the two numbered traces
- **Lifecycle** — a few lines
- **Worth knowing** — only things you actually saw, each with a `file:line`: drift, a copy
  nothing keeps in sync, a write with no validation, a column nothing reads, personal data
  in a log line. No general advice.
- **Couldn't tell from the code** — runtime config, what's actually in the database,
  behaviour behind a library you didn't read. Say it plainly rather than guess.

Every claim carries a `file:line`. Quote code only when the shape *is* the point (a column
list, a type) and keep it to a handful of lines. Don't list what you grepped. If the
target is bigger than one record's worth of tracing — a directory, a whole subsystem — give
the map at the store level and name the two or three symbols worth pointing this at next.
