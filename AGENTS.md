# AGENTS.md

Engineering guide for contributors and agents working on `cellmode.nvim`.

## Core Philosophy

- The buffer is canonical: it always holds raw on-disk bytes. All visual
  formatting is decoration via extmarks; nothing is written into buffer
  contents to make the table look right.
- Prefer one clear execution path over multiple recovery branches.
- Avoid runtime fallback patterns unless strictly required for safety.
- Break compatibility when needed to keep internals small, explicit, and fast.
- Fail fast on invalid state instead of silently compensating.

## Architecture Principles

- Source of truth is the buffer text. The cell layout is a derived index;
  the overlay is a derived projection. Never let derived state become a
  second source of truth.
- Separate concerns cleanly:
  - parsing (`cellmode.codec.csv_parser`),
  - layout indexing + width cache (`cellmode.view.cell_layout`),
  - extmark placement (`cellmode.view.overlay`),
  - runtime orchestration (`cellmode.runtime.*`).
- Prefer deterministic transformations over implicit heuristics.
- Keep the public Lua surface minimal; treat module APIs as narrow contracts.

## Performance Rules

- Optimize hot paths first using measured data, not assumptions.
- Avoid whole-buffer recomputation for local edits. `apply_edit` should
  reparse only what it must (extending past any open quote) and rebuild
  widths only when an affected cell can change a column max.
- Compare new vs. previous widths; only do a full overlay redraw when widths
  actually changed. Otherwise redraw the affected record range only.
- Minimize allocations in tight loops (avoid unnecessary deep copies).
- Keep data structures merge-friendly (sorted, contiguous record indices).

## Lua Best Practices

- Use local functions and narrow module APIs.
- Keep functions small and single-purpose.
- Avoid mutation across unrelated modules.
- Avoid hidden control flow; make state transitions explicit.
- Return `(ok, err)` for recoverable runtime failures.

## Extmark / Overlay Rules

- Use a single namespace (`cellmode_overlay`) for all decoration.
- `conceal` requires window-local `conceallevel=2` and `concealcursor=nc`;
  apply these on attach via `overlay.apply_window_options(winid)`.
- Inline `virt_text` extmarks (`virt_text_pos = "inline"`) appear before the
  byte position they're anchored to. Combine conceal of the underlying
  delimiter with inline `padding + pipe` virt_text at the same byte to
  produce the visual gap.
- Multi-line records (RFC 4180 quoted cells with embedded `\n`) render as a
  full grid: every physical buffer row of the record gets the complete column
  set. Columns whose bytes are not physically present on a continuation row
  (because a neighbouring cell spans multiple lines) are emitted as empty
  padded cells so all rows stay column-aligned. Column width for a multi-line
  cell is the widest of its `\n`-split segments. The row separator
  (`CellmodeHbar` underline) is drawn only on a record's final physical line
  so a multi-line cell reads as one wrapped row, not several stacked rows.
- Escaped quotes (`""`) inside a quoted field are recorded per-field
  (`field.escapes`) by the parser; the overlay conceals one byte of each pair
  so the cell displays a single `"`.
- Highlight groups are declared with `default = true` so users can override.

## No-Fallback Implementation Policy

- Do not add compatibility shims for old protocol paths or removed adapter
  IO. The Python adapter, workbook model, and projector were removed; do
  not reintroduce them under new names.
- If an invariant fails:
  - return an explicit error,
  - keep state unchanged when possible,
  - fix the root cause rather than layering fallback logic.

## Testing and Verification

- Every non-trivial change must include verification runs.
- Required checks after runtime / rendering changes:
  - headless plugin load,
  - integration suite (`./scripts/test/run-render.sh`),
  - open / edit / save round-trip preserves bytes,
  - cell ops (`set-cell`, `insert-row`, `delete-row`),
  - overlay toggle clears and restores extmarks,
  - manual visual check in `nvim some.csv`: cursor steps cell-to-cell,
    typing the delimiter auto-quotes, conceal reveals raw bytes on the
    edited line.
- Render verification must assert both buffer content (raw CSV) and
  extmark presence (column pipes), not only file output.

## Change Discipline

- Prefer deleting dead paths over leaving legacy branches.
- Keep public surface area minimal.
- When the buffer/overlay contract changes, update `README.md`,
  `doc/cellmode.txt`, and the integration suite in the same change.
