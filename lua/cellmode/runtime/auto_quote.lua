local session_store = require("cellmode.runtime.session_store")
local cell_layout = require("cellmode.view.cell_layout")
local csv_parser = require("cellmode.codec.csv_parser")
local overlay = require("cellmode.view.overlay")

local M = {}

local function delim_for(format)
  return csv_parser.delimiter_for_format(format)
end

local function field_at(layout, row1, col1)
  local irec = layout.record_by_row[row1]
  if not irec then
    return nil
  end
  local record = layout.records[irec]
  for icol = 1, #record.fields do
    local f = record.fields[icol]
    if (row1 > f.byte_start_row or (row1 == f.byte_start_row and col1 >= f.byte_start_col))
       and (row1 < f.byte_end_row or (row1 == f.byte_end_row and col1 <= f.byte_end_col + 1)) then
      return f, irec, icol
    end
  end
  return nil
end

function M.handle_text_changed(bufnr)
  local session = session_store.get(bufnr)
  if not session then
    return
  end
  if session.updating_buffer then
    return
  end
  local layout = cell_layout.get(bufnr)
  if not layout then
    return
  end
  local pos = vim.api.nvim_win_get_cursor(0)
  local row1 = pos[1]
  local col0 = pos[2]
  local line = vim.api.nvim_buf_get_lines(bufnr, row1 - 1, row1, false)[1] or ""
  local delim = delim_for(session.format)
  local typed_col0 = col0 - 1
  if typed_col0 < 0 or typed_col0 >= #line then
    return
  end
  local typed = line:sub(typed_col0 + 1, typed_col0 + 1)
  if typed ~= delim then
    return
  end

  local typed_col1 = typed_col0 + 1
  local field, irec, _ = field_at(layout, row1, typed_col1)
  if not field then
    return
  end
  if field.quoted then
    return
  end
  if typed_col1 == field.delim_col and field.delim_row == row1 then
    return
  end

  local sr = field.byte_start_row - 1
  local sc = field.byte_start_col - 1
  local er = field.byte_end_row - 1
  local ec = field.byte_end_col

  local current = vim.api.nvim_buf_get_text(bufnr, sr, sc, er, ec, {})
  local joined = table.concat(current, "\n")
  local quoted = '"' .. joined:gsub('"', '""') .. '"'
  local replacement = vim.split(quoted, "\n", { plain = true })

  session_store.set_updating_buffer(bufnr, true)
  vim.api.nvim_buf_set_text(bufnr, sr, sc, er, ec, replacement)
  session_store.set_updating_buffer(bufnr, false)

  cell_layout.build(bufnr, session.format)
  overlay.redraw(bufnr)

  vim.api.nvim_win_set_cursor(0, { row1, col0 + 1 })
  local _ = irec
end

return M
