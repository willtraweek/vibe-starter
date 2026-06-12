# The `.context/` workflow

`.context/` is local scratch space for collaborating with other agents and across Conductor
workspaces. It is **gitignored** — nothing in it is committed, and it is created on demand (you
don't need to commit the directory).

Use it for:

- Handoff docs between parallel agents.
- Work-in-progress plans and scratch reasoning.
- Shared state you don't want in git history.

If a note here becomes durable (an architecture decision, a real design), promote it to `docs/`
or `DESIGN.md` so it survives. Treat `.context/` as a whiteboard, not a filing cabinet.
