local M = {}

local QUOTE = '"'

local function delimiter_for_format(format)
  if format == "tsv" then
    return "\t"
  end
  return ","
end

M.delimiter_for_format = delimiter_for_format

local function read_quoted_field(lines, row, col, nl, field)
  field.quoted = true
  field.byte_start_row = row
  field.byte_start_col = col
  field.escapes = {}
  col = col + 1
  local last_row, last_col = row, col - 1
  local parts = {}
  while true do
    local line = lines[row] or ""
    if col > #line then
      parts[#parts + 1] = "\n"
      row = row + 1
      col = 1
      if row > nl then
        last_row, last_col = row - 1, math.max(1, #(lines[row - 1] or ""))
        break
      end
    else
      local ch = line:sub(col, col)
      if ch == QUOTE then
        local nx = line:sub(col + 1, col + 1)
        if nx == QUOTE then
          parts[#parts + 1] = QUOTE
          field.escapes[#field.escapes + 1] = { row = row, col = col + 1 }
          col = col + 2
        else
          last_row, last_col = row, col
          col = col + 1
          break
        end
      else
        parts[#parts + 1] = ch
        col = col + 1
      end
    end
  end
  field.value = table.concat(parts)
  field.byte_end_row = last_row
  field.byte_end_col = last_col
  if last_row > field.byte_start_row then
    field.multiline = true
  end
  return row, col
end

local function read_unquoted_field(lines, row, col, delim, field)
  field.quoted = false
  field.byte_start_row = row
  field.byte_start_col = col
  local line = lines[row] or ""
  local parts = {}
  local last_col = col - 1
  while col <= #line do
    local ch = line:sub(col, col)
    if ch == delim then
      break
    end
    parts[#parts + 1] = ch
    last_col = col
    col = col + 1
  end
  field.value = table.concat(parts)
  field.byte_end_row = row
  field.byte_end_col = math.max(field.byte_start_col - 1, last_col)
  return row, col
end

local function read_field(lines, row, col, delim, nl)
  local field = {}
  local line = lines[row] or ""
  local ch = line:sub(col, col)
  if ch == QUOTE then
    return field, read_quoted_field(lines, row, col, nl, field)
  end
  return field, read_unquoted_field(lines, row, col, delim, field)
end

function M.parse(lines, format)
  local delim = delimiter_for_format(format)
  local records = {}
  local nl = #lines
  local row = 1
  while row <= nl do
    local record = {
      buf_row_start = row,
      fields = {},
    }
    local col = 1
    while true do
      local field, new_row, new_col = read_field(lines, row, col, delim, nl)
      record.fields[#record.fields + 1] = field
      if field.multiline then
        record.multiline = true
      end
      row = new_row
      col = new_col
      local line = lines[row] or ""
      if col <= #line and line:sub(col, col) == delim then
        field.delim_row = row
        field.delim_col = col
        col = col + 1
      else
        break
      end
    end
    record.buf_row_end = row
    records[#records + 1] = record
    row = row + 1
  end
  return records
end

function M.find_record_start(lines, target_row)
  local nl = #lines
  if target_row < 1 then
    return 1
  end
  local probe = math.max(1, target_row)
  while probe > 1 do
    local prev = lines[probe - 1] or ""
    local quote_count = 0
    for i = 1, #prev do
      if prev:sub(i, i) == QUOTE then
        quote_count = quote_count + 1
      end
    end
    if quote_count % 2 == 0 then
      break
    end
    probe = probe - 1
  end
  if probe < 1 then
    probe = 1
  end
  if probe > nl then
    probe = nl
  end
  return probe
end

return M
