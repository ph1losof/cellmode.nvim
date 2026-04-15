local session_store = require("cellmode.runtime.session_store")
local cell_layout = require("cellmode.view.cell_layout")
local overlay = require("cellmode.view.overlay")
local sticky_header = require("cellmode.view.sticky_header")
local csv_parser = require("cellmode.codec.csv_parser")

local M = {}

local function detect_format(bufnr, override)
  if override == "csv" or override == "tsv" then
    return override
  end
  local ft = vim.bo[bufnr].filetype
  if ft == "csv" or ft == "tsv" then
    return ft
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local ext = path:match("^.+%.([^.]+)$")
  if ext == "tsv" then
    return "tsv"
  end
  return "csv"
end

M.detect_format = detect_format

local function apply_window_options_for_buffer(bufnr)
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    overlay.apply_window_options(winid)
  end
end

function M.open(bufnr, opts)
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "invalid buffer"
  end
  local format = detect_format(bufnr, opts.format)
  cell_layout.build(bufnr, format)
  session_store.open(bufnr, {
    format = format,
    overlay_visible = true,
  })
  apply_window_options_for_buffer(bufnr)
  overlay.redraw(bufnr)
  sticky_header.refresh_buffer(bufnr)
  return true
end

function M.close(bufnr)
  sticky_header.disable_for_buffer(bufnr)
  session_store.close(bufnr)
  cell_layout.clear(bufnr)
  overlay.forget(bufnr)
end

function M.on_buffer_changed(bufnr, change)
  local session = session_store.get(bufnr)
  if not session then
    return
  end
  if session.updating_buffer then
    return
  end
  local result = cell_layout.apply_edit(bufnr, change)
  if not result then
    return
  end
  if result.full or result.widths_changed then
    overlay.redraw(bufnr)
  else
    overlay.redraw_range(bufnr, result.first_record, result.last_record, result.widths_changed)
  end
  sticky_header.refresh_buffer(bufnr)
end

function M.toggle_overlay(bufnr)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  local visible = session.overlay_visible == false
  session_store.set_overlay_visible(bufnr, visible)
  overlay.set_visible(bufnr, visible)
  if visible then
    sticky_header.refresh_buffer(bufnr)
  else
    sticky_header.disable_for_buffer(bufnr)
  end
  return true
end

local function delim_for(format)
  return csv_parser.delimiter_for_format(format)
end

local function encode_cell(value, delim)
  local text = tostring(value or "")
  local needs = text:find('"', 1, true)
    or text:find(delim, 1, true)
    or text:find("\n", 1, true)
    or text:find("\r", 1, true)
  if not needs then
    return text
  end
  return '"' .. text:gsub('"', '""') .. '"'
end

M.encode_cell = encode_cell

local function set_lines_unmanaged(bufnr, start_row0, end_row0, lines)
  session_store.set_updating_buffer(bufnr, true)
  vim.api.nvim_buf_set_lines(bufnr, start_row0, end_row0, false, lines)
  session_store.set_updating_buffer(bufnr, false)
end

local function set_text_unmanaged(bufnr, sr, sc, er, ec, lines)
  session_store.set_updating_buffer(bufnr, true)
  vim.api.nvim_buf_set_text(bufnr, sr, sc, er, ec, lines)
  session_store.set_updating_buffer(bufnr, false)
end

function M.set_cell(bufnr, irec, icol, value)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  local layout = cell_layout.get(bufnr)
  if not layout then
    return false, "layout not built"
  end
  local record = layout.records[irec]
  if not record then
    return false, "record out of range"
  end
  local field = record.fields[icol]
  local delim = delim_for(session.format)
  local encoded = encode_cell(value, delim)

  if field then
    local sr = field.byte_start_row - 1
    local sc = field.byte_start_col - 1
    local er = field.byte_end_row - 1
    local ec = field.byte_end_col
    local replacement = vim.split(encoded, "\n", { plain = true })
    set_text_unmanaged(bufnr, sr, sc, er, ec, replacement)
  else
    local last_field = record.fields[#record.fields]
    if not last_field then
      return false, "record has no fields"
    end
    local missing = icol - #record.fields
    local insert = ""
    for _ = 1, missing - 1 do
      insert = insert .. delim
    end
    insert = insert .. delim .. encoded
    local sr = last_field.byte_end_row - 1
    local sc = last_field.byte_end_col
    set_text_unmanaged(bufnr, sr, sc, sr, sc, vim.split(insert, "\n", { plain = true }))
  end

  cell_layout.build(bufnr, session.format)
  overlay.redraw(bufnr)
  return true
end

function M.insert_row(bufnr, irec, values)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  local layout = cell_layout.get(bufnr)
  if not layout then
    return false, "layout not built"
  end
  local delim = delim_for(session.format)
  local cells = {}
  for i = 1, #(values or {}) do
    cells[i] = encode_cell(values[i], delim)
  end
  local row_text = table.concat(cells, delim)
  local row_lines = vim.split(row_text, "\n", { plain = true })

  local insert_at0
  local total_records = #layout.records
  if irec <= 0 then
    insert_at0 = 0
  elseif irec > total_records then
    insert_at0 = layout.line_count
  else
    insert_at0 = layout.records[irec].buf_row_start - 1
  end
  set_lines_unmanaged(bufnr, insert_at0, insert_at0, row_lines)
  cell_layout.build(bufnr, session.format)
  overlay.redraw(bufnr)
  return true
end

function M.delete_row(bufnr, irec)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  local layout = cell_layout.get(bufnr)
  if not layout then
    return false, "layout not built"
  end
  local record = layout.records[irec]
  if not record then
    return false, "record out of range"
  end
  set_lines_unmanaged(bufnr, record.buf_row_start - 1, record.buf_row_end, {})
  cell_layout.build(bufnr, session.format)
  overlay.redraw(bufnr)
  return true
end

return M
