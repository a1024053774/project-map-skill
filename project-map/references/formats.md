# Project map formats

Templates live in [../assets/templates/](../assets/templates/). `project_map.py init` copies `MAP.md`; copy `ticket.md` for a decision, research, or task ticket, `build-ticket.md` for a build ticket, and `spec.md` for a spec.

## MAP.md

Required sections, in this order: `## Destination`, `## Notes`, `## Decisions so far`, `## Not yet specified`, `## Out of scope`, `## Living docs`. Budget: 150 lines.

*Decisions so far* has one line per closed non-`build` ticket:

```markdown
- [T-004 Pick the session store](tickets/T-004-session-store.md): SQLite; Redis rejected as extra ops for one user
```

Open tickets are not listed in the map; the script computes them. A ticket appears in *Decisions so far* only once it is closed.

### Living docs table

```markdown
| Doc | Covers | Verified |
| --- | --- | --- |
| [README.md](../README.md) | `src/cli/**`, `pyproject.toml` | |
| [docs/architecture.md](../docs/architecture.md) | `src/**` | a1b2c3d |
```

- **Doc**: a Markdown link relative to `MAP.md`.
- **Covers**: backtick-quoted paths or globs relative to the project root. `**` matches any depth. Pick the paths whose change could make the doc wrong, not the whole repository.
- **Verified**: empty, or a commit id recorded when a flagged change was reviewed and did not affect the doc. Editing the doc itself also counts as a review, so the cell is only needed for "reviewed, no change needed".

The script flags a living doc as stale when commits after its last reviewed commit changed its `covers` paths, or when the working tree changes covered paths without touching the doc. The last reviewed commit is the later of the doc's own last commit and its *Verified* commit. Without git, it compares modification times.

## Tickets

File name: `tickets/<id>-<slug>.md`, where the file name starts with the ticket's `id`. Frontmatter uses simple `key: value` lines; lists use `[A, B]`.

| Field | Values |
| --- | --- |
| `id` | `T-001`, `T-002`, ... unique |
| `title` | short name |
| `type` | `decide`, `compare`, `prototype`, `research`, `task`, `build` |
| `status` | `open`, `closed`, `superseded`, `out-of-scope` |
| `blocked_by` | list of ticket ids; the ticket is unblocked when each is `closed` or `superseded` |
| `claimed_by` | empty when unclaimed |
| `supersedes` | id of the ticket this one replaces, or empty |

Body sections: `## Question` and `## Resolution` for decision, research, and task tickets; `## What to build`, `## Acceptance`, and `## Resolution` for build tickets. A closed ticket must have a non-empty `## Resolution`. Prototype and research outputs are linked from the resolution, not pasted.

A build ticket needs at least one checkbox (`- [ ]`) under `## Acceptance`, and it can close only when every box is checked (`- [x]` or `- [X]`).

The **frontier** is every open, unclaimed ticket whose blockers are all resolved.

## Specs and the glossary

A spec lives at `specs/<slug>.md`, is linked from *Destination*, and is a dated record. The glossary is `CONTEXT.md` at the repository root, registered in *Living docs* with the paths of the code that implements its concepts.
