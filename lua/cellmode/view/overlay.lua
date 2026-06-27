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

-- The row separator (CellmodeHbar underline) is drawn only on the last
-- physical line of a record, so a multi-line cell reads as one wrapped row
-- rather than several stacked rows. Internal lines use the plain variants.
local PIPE_HL = { "CellmodePipe", "CellmodeHbar" }
local PAD_HL = { "CellmodePadding", "CellmodeHbar" }
local PIPE_HL_PLAIN = { "CellmodePipe" }
local PAD_HL_PLAIN = { "CellmodePadding" }

local function place_hbar(bufnr, row0, line)
  if #line == 0 then
    return
  end
  vim.api.nvim_buf_set_extmark(bufnr, ns, row0, 0, {
    end_row = row0,
    end_col = #line,
    hl_group = "CellmodeHbar",
  })
end

-- Display text of a field on a given buffer row. Single-line fields render
-- their whole value; multi-line fields render the value segment for that row.
local function field_segment(field, segs, row)
  if not field.multiline then
    return field.value
  end
  return segs[row - field.byte_start_row + 1] or ""
end

-- Render a record as a full grid. Every physical buffer row of the record
-- gets a complete set of column pipes; columns whose bytes are not physically
-- present on a row (because a neighbouring cell spans multiple lines) are
-- emitted as empty padded cells so all rows stay column-aligned.
local function decorate_record(bufnr, layout, record)
  local fields = record.fields
  local ncol = #fields
  local widths = layout.widths or {}
  local pipe = pipe_glyph()

  local segs = {}
  for icol = 1, ncol do
    local f = fields[icol]
    if f.multiline then
      segs[icol] = vim.split(f.value, "\n", { plain = true })
    end
  end

  for row = record.buf_row_start, record.buf_row_end do
    local row0 = row - 1
    local line = vim.api.nvim_buf_get_lines(bufnr, row0, row0 + 1, false)[1] or ""

    -- only the record's final physical line carries the row separator
    local rule = row == record.buf_row_end
    local pipe_hl = rule and PIPE_HL or PIPE_HL_PLAIN
    local pad_hl = rule and PAD_HL or PAD_HL_PLAIN

    local first_present, last_present
    for icol = 1, ncol do
      local f = fields[icol]
      if f.byte_start_row <= row and row <= f.byte_end_row then
        first_present = first_present or icol
        last_present = icol
      end
    end

    -- leading record pipe, plus empty cells for columns absent before the
    -- first one physically present on this row
    local lead = { { pipe, pipe_hl } }
    for icol = 1, (first_present or (ncol + 1)) - 1 do
      local w = widths[icol] or 0
      if w > 0 then
        lead[#lead + 1] = { pad_str(w), pad_hl }
      end
      lead[#lead + 1] = { pipe, pipe_hl }
    end
    place_inline(bufnr, row0, 0, lead)
    if rule then
      place_hbar(bufnr, row0, line)
    end

    for icol = first_present or 1, last_present or 0 do
      local field = fields[icol]
      local width = widths[icol] or 0
      local seg = field_segment(field, segs[icol], row)
      local padding = pad_str(width - cell_layout.display_width(seg))
      local chunks = {}
      if padding ~= "" then
        chunks[#chunks + 1] = { padding, pad_hl }
      end
      chunks[#chunks + 1] = { pipe, pipe_hl }

      local on_this_row = field.delim_row == row and field.delim_col
      local end_col = on_this_row and field.delim_col or (#line + 1)
      place_inline(bufnr, row0, end_col - 1, chunks, { right_gravity = true })

      if on_this_row then
        place_conceal(bufnr, row0, field.delim_col - 1, field.delim_col)
      end
      if field.quoted then
        if row == field.byte_start_row then
          place_conceal(bufnr, row0, field.byte_start_col - 1, field.byte_start_col)
        end
        if row == field.byte_end_row then
          place_conceal(bufnr, row0, field.byte_end_col - 1, field.byte_end_col)
        end
        if field.escapes then
          for iesc = 1, #field.escapes do
            local esc = field.escapes[iesc]
            if esc.row == row then
              place_conceal(bufnr, row0, esc.col - 1, esc.col)
            end
          end
        end
      end
    end

    -- empty cells for columns absent after the last one present on this row
    if last_present and last_present < ncol then
      local chunks = {}
      for icol = last_present + 1, ncol do
        local w = widths[icol] or 0
        if w > 0 then
          chunks[#chunks + 1] = { pad_str(w), pad_hl }
        end
        chunks[#chunks + 1] = { pipe, pipe_hl }
      end
      place_inline(bufnr, row0, #line, chunks, { right_gravity = true })
    end
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
    decorate_record(bufnr, layout, records[irec])
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
    decorate_record(bufnr, layout, records[irec])
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
  vim.wo[winid].concealcursor = "nvic"
end

return M
