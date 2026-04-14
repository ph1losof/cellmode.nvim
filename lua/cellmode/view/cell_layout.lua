local csv_parser = require("cellmode.codec.csv_parser")

local M = {}

local fn = vim.fn

local layouts = {}

local function display_width(text)
  if not text or text == "" then
    return 0
  end
  if not text:find("[\t\128-\255]") then
    return #text
  end
  return fn.strdisplaywidth(text)
end

M.display_width = display_width

local function compute_field_widths(record)
  local widths = {}
  for i = 1, #record.fields do
    local field = record.fields[i]
    if field.multiline then
      widths[i] = display_width(field.value:gsub("\n.*", ""))
    else
      widths[i] = display_width(field.value)
    end
  end
  return widths
end

local function rebuild_widths(layout)
  local widths = {}
  local max_row_by_col = {}
  local records = layout.records
  for irec = 1, #records do
    local fw = compute_field_widths(records[irec])
    for icol = 1, #fw do
      if fw[icol] > (widths[icol] or 0) then
        widths[icol] = fw[icol]
        max_row_by_col[icol] = irec
      end
    end
  end
  layout.widths = widths
  layout.max_row_by_col = max_row_by_col
end

local function build_record_index(layout)
  local by_buf_row = {}
  local records = layout.records
  for irec = 1, #records do
    local r = records[irec]
    for row = r.buf_row_start, r.buf_row_end do
      by_buf_row[row] = irec
    end
  end
  layout.record_by_row = by_buf_row
end

local function buffer_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

function M.build(bufnr, format)
  local lines = buffer_lines(bufnr)
  local records = csv_parser.parse(lines, format)
  local layout = {
    bufnr = bufnr,
    format = format,
    records = records,
    line_count = #lines,
  }
  rebuild_widths(layout)
  build_record_index(layout)
  layouts[bufnr] = layout
  return layout
end

function M.get(bufnr)
  return layouts[bufnr]
end

function M.clear(bufnr)
  layouts[bufnr] = nil
end

local function records_overlap(record, row_start, row_end)
  return record.buf_row_end >= row_start and record.buf_row_start <= row_end
end

local function widths_equal(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

function M.apply_edit(bufnr, change)
  local layout = layouts[bufnr]
  if not layout then
    return nil, "no layout"
  end
  local lines = buffer_lines(bufnr)
  layout.line_count = #lines

  local probe_row = csv_parser.find_record_start(lines, change.first_line + 1)
  local prev_widths = layout.widths or {}
  local records = csv_parser.parse(lines, layout.format)

  local record_by_row = {}
  for irec = 1, #records do
    local r = records[irec]
    for row = r.buf_row_start, r.buf_row_end do
      record_by_row[row] = irec
    end
  end

  layout.records = records
  layout.record_by_row = record_by_row
  rebuild_widths(layout)

  local widths_changed = not widths_equal(prev_widths, layout.widths)

  local affected_first_row = math.min(probe_row, change.first_line + 1)
  local affected_last_row = math.max(change.new_last_line, change.last_line, affected_first_row)
  local first_record = record_by_row[affected_first_row]
  local last_record = record_by_row[affected_last_row]
  if not first_record then
    for r = affected_first_row, #lines do
      if record_by_row[r] then
        first_record = record_by_row[r]
        break
      end
    end
  end
  if not last_record then
    for r = math.min(affected_last_row, #lines), 1, -1 do
      if record_by_row[r] then
        last_record = record_by_row[r]
        break
      end
    end
  end

  return {
    first_record = first_record or 1,
    last_record = last_record or #records,
    widths_changed = widths_changed,
    full = widths_changed,
  }
end

function M.cell_at(bufnr, row1, col1)
  local layout = layouts[bufnr]
  if not layout then
    return nil
  end
  local irec = layout.record_by_row[row1]
  if not irec then
    return nil
  end
  local record = layout.records[irec]
  for icol = 1, #record.fields do
    local f = record.fields[icol]
    if (row1 > f.byte_start_row or (row1 == f.byte_start_row and col1 >= f.byte_start_col))
       and (row1 < f.byte_end_row or (row1 == f.byte_end_row and col1 <= f.byte_end_col)) then
      return { record = irec, col = icol, field = f }
    end
  end
  return { record = irec, col = nil }
end

function M.cell_range(bufnr, irec, icol)
  local layout = layouts[bufnr]
  if not layout then
    return nil
  end
  local record = layout.records[irec]
  if not record then
    return nil
  end
  local field = record.fields[icol]
  if not field then
    return nil
  end
  return field
end

return M
