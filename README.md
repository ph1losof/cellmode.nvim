# cellmode.nvim

Visual table editing for CSV/TSV in Neovim, with the buffer always holding raw on-disk bytes.

`cellmode` keeps the buffer canonical: what you see on disk is what's in the buffer. Column separators, padding, and the visual grid are rendered with extmarks (inline `virt_text` + `conceal`), so cursor motions, yank, search, and external tools all operate on the real CSV text.

## Requirements

- Neovim 0.10+ (inline `virt_text` is required)
- No external dependencies (pure Lua, no Python, no subprocess)

## Install (lazy.nvim)

```lua
{
  "ph1losof/cellmode.nvim",
  ft = { "csv", "tsv" },
  opts = {},
}
```

## Setup

```lua
require("cellmode").setup({
  command = "Cellmode",  -- user-command name
  marks = {
    pipe = "│",   -- column separator glyph
    pipec = "┊",  -- multi-line continuation glyph
  },
})
```

The plugin attaches automatically on `BufReadPost` for buffers with filetype or extension `csv` / `tsv`.

## How it works

- The buffer holds raw CSV/TSV bytes, identical to disk. `:w` is a normal Vim write.
- A pure-Lua RFC 4180 parser (`cellmode.codec.csv_parser`) builds a per-buffer cell layout (`cellmode.view.cell_layout`) on attach and incrementally on each edit.
- An overlay (`cellmode.view.overlay`) places extmarks: inline `virt_text` for column pipes and alignment padding, and `conceal=""` to hide the underlying delimiters and quote characters when not on the cursor line. Per-window `conceallevel=2` and `concealcursor=nc` are set on attach so editing reveals the raw text.
- Typing the format's delimiter inside an unquoted cell auto-quotes the cell (`cellmode.runtime.auto_quote`) so cell boundaries stay stable.
- Multi-line cells (RFC 4180 quoted values containing `\n`) span multiple buffer lines; continuation lines get a marker glyph.

## Commands

```vim
:Cellmode open <path> <csv|tsv>           " open + attach explicitly
:Cellmode op set-cell <row> <col> <value> " replace a cell value
:Cellmode op insert-row <row> <v1,v2,...> " insert a row at <row>
:Cellmode op delete-row <row>             " delete a row
:Cellmode toggle                          " hide/show the visual overlay
:Cellmode save                            " :write the buffer
:Cellmode status                          " print format/records/columns/overlay
```

`<row>` and `<col>` are 1-based indexes into the parsed records / fields.

## Highlights

| Group                  | Purpose                                |
|------------------------|----------------------------------------|
| `CellmodePipe`         | Column separator glyph                 |
| `CellmodePadding`      | Alignment padding                      |
| `CellmodeContinuation` | Multi-line cell continuation marker    |
| `CellmodeHbar`         | Reserved (row underline)               |
| `CellmodeSpecialChar`  | Reserved (special-char glyphs)         |

All groups are defined with `default = true`; override with `vim.api.nvim_set_hl`.

## Testing

```sh
./scripts/test/run-render.sh
```

Headless integration suite covering session attach, raw-CSV buffer contents, layout, extmark placement, cell ops, overlay toggle, and save round-trip.

## Help

See `:help cellmode`.

---

Inspiration for this project was taken from [tirenvi.nvim](https://github.com/kibi2/tirenvi.nvim).
