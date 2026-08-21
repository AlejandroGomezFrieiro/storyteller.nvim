# Migration notes — superseded by the joint rework plan

The tiered migration plan that lived here has been folded into
**[docs/rework-plan.md](docs/rework-plan.md)** — the active master plan
covering the plugin migration (former Tiers 0–3) together with the TUI's
staged-editing, Timeline, Relations, and Plotlines work, with no deferred
items.

What survives here as standing context:

- **Parity facts** (verified against the tree at plan time): the bundled
  schema was frozen at v1.1.0; `compile.lua` wrote verbatim manuscripts;
  `index.M.timeline` sorted a single implicit axis; relations parsing
  discarded edge payloads; card parsing ignored both bullets and heading
  sections. All of these are scheduled in rework-plan Phases A and H.
- **The flow-map rule**: placement strings (`also:`) must stay opaque
  through read/write round-trips — `meta/read.lua` does not parse flow maps
  and `meta/serde.lua::encode_map` writes list items with `tostring()`.
  Views parse placements; meta stores them verbatim.
- **Non-goals** carried forward: consolidating the dual-path execution
  model (LSP bus vs in-process Lua) remains out of scope.

Do not extend this file; update `docs/rework-plan.md` instead.
