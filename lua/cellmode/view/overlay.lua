local config = require("cellmode.config")
local cell_layout = require("cellmode.view.cell_layout")

local M = {}

local ns = vim.api.nvim_create_namespace("cellmode_overlay")
local hl_ready = false
local visibility = {}

local function setup_highlights()
  if hl_ready then
    return
  end
  hl_ready = true
  vim.api.nvim_set_hl(0, "CellmodePadding", { default = true })
  local target = "Delimiter"
  local target_hl = vim.api.nvim_get_hl(0, { name = target, link = false })
  local normal_hl = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local fg = target_hl.fg or normal_hl.fg
  vim.api.nvim_set_hl(0, "CellmodePipe", { default = true, fg = fg, nocombine = true })
  vim.api.nvim_set_hl(0, "CellmodeHbar", { default = true, underline = true, sp = fg, nocombine = true })
  vim.api.nvim_set_hl(0, "CellmodeContinuation", { default = true, link = "NonText" })
  vim.api.nvim_set_hl(0, "CellmodeSpecialChar", { default = true, link = "NonText" })
end

function M.setup()
  setup_highlights()
end

function M.namespace()
  return ns
end

local function pipe_glyph()
  return config.marks.pipe or "│"
end

local function continuation_glyph()
  return config.marks.pipec or "┊"
end

local function place_inline(bufnr, row0, col0, chunks, opts)
  opts = opts or {}
  opts.virt_text = chunks
  opts.virt_text_pos = "inline"
  if opts.right_gravity == nil then
    opts.right_gravity = false
  end
  vim.api.nvim_buf_set_extmark(bufnr, ns, row0, col0, opts)
end

local function place_conceal(bufnr, row0, col0, end_col0)
  vim.api.nvim_buf_set_extmark(bufnr, ns, row0, col0, {
    end_row = row0,
    end_col = end_col0,
    conceal = "",
  })
end

local function pad_str(width)
  if width <= 0 then
    return ""
  end
  return string.rep(" ", width)
end

local function decorate_single_line_record(bufnr, layout, record)
  local row0 = record.buf_row_start - 1
  local fields = record.fields
  local widths = layout.widths or {}
  local pipe = pipe_glyph()

  place_inline(bufnr, row0, 0, { { pipe, "CellmodePipe" } })

  for icol = 1, #fields do
    local field = fields[icol]
    local width = widths[icol] or 0
    local field_display = cell_layout.display_width(field.value)
    local padding = pad_str(width - field_display)
    local chunks = {}
    if padding ~= "" then
      chunks[#chunks + 1] = { padding, "CellmodePadding" }
    end
    chunks[#chunks + 1] = { pipe, "CellmodePipe" }

    local end_col
    if field.delim_col then
      end_col = field.delim_col
    else
      local line = vim.api.nvim_buf_get_lines(bufnr, row0, row0 + 1, false)[1] or ""
      end_col = #line + 1
    end
    place_inline(bufnr, row0, end_col - 1, chunks)

    if field.delim_col then
      place_conceal(bufnr, row0, field.delim_col - 1, field.delim_col)
    end

    if field.quoted then
      place_conceal(bufnr, row0, field.byte_start_col - 1, field.byte_start_col)
      place_conceal(bufnr, row0, field.byte_end_col - 1, field.byte_end_col)
    end
  end
end

local function decorate_multiline_record(bufnr, record)
  local cont = continuation_glyph()
  for row = record.buf_row_start, record.buf_row_end - 1 do
    vim.api.nvim_buf_set_extmark(bufnr, ns, row - 1, 0, {
      virt_text = { { cont, "CellmodeContinuation" } },
      virt_text_pos = "eol",
      right_gravity = false,
    })
  end
end

local function clear_lines(bufnr, row_start, row_end)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, row_start - 1, row_end)
end

function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

function M.redraw(bufnr)
  setup_highlights()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  M.clear(bufnr)
  if visibility[bufnr] == false then
    return
  end
  local layout = cell_layout.get(bufnr)
  if not layout then
    return
  end
  local records = layout.records
  for irec = 1, #records do
    local record = records[irec]
    if record.multiline then
      decorate_multiline_record(bufnr, record)
    else
      decorate_single_line_record(bufnr, layout, record)
    end
  end
end

function M.redraw_range(bufnr, first_record, last_record, widths_changed)
  setup_highlights()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if visibility[bufnr] == false then
    return
  end
  local layout = cell_layout.get(bufnr)
  if not layout then
    return
  end
  if widths_changed then
    M.redraw(bufnr)
    return
  end
  local records = layout.records
  if not first_record or first_record < 1 then
    first_record = 1
  end
  if not last_record or last_record > #records then
    last_record = #records
  end
  if first_record > last_record then
    return
  end
  local row_start = records[first_record].buf_row_start
  local row_end = records[last_record].buf_row_end
  clear_lines(bufnr, row_start, row_end)
  for irec = first_record, last_record do
    local record = records[irec]
    if record.multiline then
      decorate_multiline_record(bufnr, record)
    else
      decorate_single_line_record(bufnr, layout, record)
    end
  end
end

function M.set_visible(bufnr, visible)
  visibility[bufnr] = visible and true or false
  if not visible then
    M.clear(bufnr)
  else
    M.redraw(bufnr)
  end
end

function M.is_visible(bufnr)
  return visibility[bufnr] ~= false
end

function M.forget(bufnr)
  visibility[bufnr] = nil
  M.clear(bufnr)
end

function M.apply_window_options(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return
  end
  vim.wo[winid].conceallevel = 2
  vim.wo[winid].concealcursor = "nc"
end

return M
