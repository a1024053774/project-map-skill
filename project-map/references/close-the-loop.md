# Close the loop

When the same failure class shows up a second time, whether as a bug, a review finding, or an incident, fixing the instance is not enough. Open a `task` ticket to make the next occurrence fail mechanically: a test, a lint or dependency rule, a script, or a hook that runs without anyone remembering to run it. Prose rules weaken as instruction files grow; a check holds on every run.

- **Checkable:** add the check, then one line in the project's `AGENTS.md` (or the living doc that owns the area) naming the check and the failure class it catches.
- **Not checkable:** only then write a prose rule there, and state in it why no check can catch the failure yet.

Link the check or rule from the ticket's resolution. Register `AGENTS.md` as a living doc so its lines are checked for staleness like any other. Rules and check pointers live there, not in a separate ledger.
