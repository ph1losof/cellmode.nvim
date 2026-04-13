# cellmode.nvim

Blazingly fast table-mode editing for Neovim.

`cellmode` is an adapter-driven plugin focused on CSV/TSV workflows with a viewport-oriented renderer for large files.

## Requirements

- Neovim (0.9+ recommended)
- Python 3
- `tir-csv` installed and available on `$PATH`

## Install (lazy.nvim)

```lua
{
  "ph1losof/cellmode.nvim",
  ft = { "csv", "tsv" },
  opts = {}
}
```

## Default adapters

When no adapters are provided, `cellmode` auto-registers:

- CSV: `python3 <plugin_root>/adapters/cellmode_tir_csv_adapter.py`
- TSV: `python3 <plugin_root>/adapters/cellmode_tir_csv_adapter.py --delimiter "\t"`

## Manual setup

```lua
require("cellmode").setup({
  adapters = {
    csv = { command = { "python3", "/path/to/adapters/cellmode_tir_csv_adapter.py" } },
    tsv = { command = { "python3", "/path/to/adapters/cellmode_tir_csv_adapter.py", "--delimiter", "\t" } },
  },
  command = "Cellmode",
})
```

## Commands

```vim
:Cellmode open <path> <format> [--adapter <cmd> [args...]]
:Cellmode op set-cell <segment> <row> <col> <value>
:Cellmode op insert-row <segment> <row> <value1,value2,...>
:Cellmode op delete-row <segment> <row>
:Cellmode save <path> [format]
:Cellmode status
```

## Help

See `:help cellmode`.

---

Inspiration for this project was taken from [tirenvi.nvim](https://github.com/kibi2/tirenvi.nvim).
