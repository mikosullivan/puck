~~~vibecode
{"doc": "sprint-note", "sprint": "trace-tables",
	"role": "Manifest for the schema.svg history dump. Nine committed versions extracted via git show, plus the current schema.svg (10th, latest, matching the pre-rewrite Inkscape aesthetic)."}
~~~

# schema.svg history

Every prior version of the CVM ER diagram, oldest first. Extracted with `git show <commit>:<path>` — the file lived under `requirements/drinian/`, then `requirements/mvm/`, then `requirements/cvm/` as the project renamed.

| File | Commit | Description |
|---|---|---|
| `history-01-8267e3b.svg` | `8267e3b` | Original: bootstrap sequence spec'd out; MVM engine wiring + install gate + process record init landed; archive/ removed; ER diagram of MVM schema |
| `history-02-f88acb4.svg` | `f88acb4` | Rename Drinian → MVM everywhere; global doc-image sizing (fixes #1535) |
| `history-03-00362db.svg` | `00362db` | MVM: owner_role column + block-scope closure envelopes + FK naming cleanup + frames walkthroughs |
| `history-04-2d2122e.svg` | `2d2122e` | MVM: drop frames.method, add frames.ast (JSON text); ast-storage design note; method_class also dropped |
| `history-05-7a07160.svg` | `7a07160` | Promote refs-rename sidequest into requirements/ |
| `history-06-904c476.svg` | `904c476` | CVM: rename MVM → CVM everywhere outside the frames-as-objects tree |
| `history-07-286e827.svg` | `286e827` | frames-as-objects Phase 1: promote docs to requirements/; ready for Phase 2 |
| `history-08-b35e0d4.svg` | `b35e0d4` | frame-0 sprint: implementation + tests complete, integration plan captured — last commit before integration |
| `history-09-e170ab3.svg` | `e170ab3` | Claude's rewrite: drop staleness note, replace Inkscape-authored SVG with a hand-authored one |
| `schema.svg` (current) | uncommitted | Redo in the pre-rewrite Inkscape aesthetic (Miko preferred the earlier style over `e170ab3`) |

Versions 01–08 share the same visual aesthetic (Inkscape-authored, white tables with colored headers, PK/FK/col row prefixes, small circular self-loops). Content evolved: the very old ones show a `processes` table and `bucket_pk`/`stack_pk` columns that no longer exist. Version 09 is the outlier — Claude rewrote from scratch in a different style. `schema.svg` (current) restores the earlier aesthetic on the current schema content.
