# Pipeline steps

The four steps of the pipeline in [../SKILL.md](../SKILL.md#pipeline). Read a step's section when you start it.

## 1. Decide

Settle the decision tickets with the user (the `grilling` Skill when invoked). Keep the domain language in `CONTEXT.md` at the repository root: when a term is settled, write it there right away; challenge a user's term that conflicts with the glossary, and check what the user says against the code. `CONTEXT.md` is a glossary only, with no implementation details. Create it with the first settled term and register it as a living doc that covers the code implementing those concepts.

## 2. Spec

When every decision ticket inside the destination is closed, synthesize a spec without asking new questions: copy `assets/templates/spec.md` to `specs/<slug>.md` and link it from *Destination*. It states the problem, the solution, the decisions (as links, never restated), the test seam, and what is out of scope. Pick the highest test seam, ideally one end-to-end entry point, and confirm it with the user. A spec is a dated record: later changes go through new tickets, not edits to the spec.

## 3. Slice

Break the spec into `build` tickets from `assets/templates/build-ticket.md`:

- each ticket is a tracer-bullet slice: a narrow but complete path through every layer, verifiable on its own, small enough for one fresh session;
- blocking edges go in `blocked_by`, and prefactoring that makes the change easy comes first;
- a wide mechanical refactor that no single slice can land green is sequenced as expand, migrate in batches, contract;
- the body states the behavior from the user's side and its acceptance checkboxes; leave out file paths and code snippets, which go stale, unless a prototype snippet encodes a decision better than prose.

Slice only the next two or three tickets; leave the rest of the spec under *Not yet specified*. The first slices show what the spec got wrong, and tickets cut before that would encode the mistakes. When they close, reread the spec against what was built and slice the next batch; if a decision in it turned out wrong, open a superseding ticket instead of slicing around it.

Show the breakdown (title, blocked by, what it delivers) and let the user adjust granularity and edges before writing the files.

## 4. Work one build ticket

One ticket per session, taken from the frontier:

1. Claim it.
2. Make the agreed end-to-end check fail for the missing behavior. If a part must be tested in isolation, list its failure modes first.
3. Implement the slice.
4. Run the check green and keep its artifact: the output plus the command that regenerates it.
5. Check against the spec: what is missing or partial, what was built but not asked for, and what looks implemented but is wrong. Fix it or open tickets; check a box only with evidence.
6. Run `design-integrity-review` when its trigger applies, and `status` for stale living docs.
7. Close with the resolution (command, result, commit) and commit the work.
