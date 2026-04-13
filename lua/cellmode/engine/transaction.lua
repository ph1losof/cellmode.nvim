local workbook_model = require("cellmode.model.workbook")

local M = {}

local function ensure_segment(sheet, index)
  local segment = sheet.segments[index]
  if not segment then
    return nil, "segment not found"
  end
  return segment
end

local function apply_set_cell(sheet, op)
  local segment, err = ensure_segment(sheet, op.segment)
  if not segment then
    return false, err
  end
  if segment.kind ~= "table" then
    return false, "set_cell requires table segment"
  end
  local row = segment.rows[op.row]
  if not row then
    return false, "row not found"
  end
  if type(op.col) ~= "number" or op.col < 1 then
    return false, "invalid column"
  end
  row[op.col] = op.value == nil and "" or tostring(op.value)
  return true
end

local function apply_insert_row(sheet, op)
  local segment, err = ensure_segment(sheet, op.segment)
  if not segment then
    return false, err
  end
  if segment.kind ~= "table" then
    return false, "insert_row requires table segment"
  end
  local rows = segment.rows
  local row_index = op.row
  if type(row_index) ~= "number" then
    row_index = #rows + 1
  end
  row_index = math.max(1, math.min(row_index, #rows + 1))
  local values = op.values or {}
  local row = {}
  for icol = 1, #values do
    row[icol] = values[icol] == nil and "" or tostring(values[icol])
  end
  table.insert(rows, row_index, row)
  return true
end

local function apply_delete_row(sheet, op)
  local segment, err = ensure_segment(sheet, op.segment)
  if not segment then
    return false, err
  end
  if segment.kind ~= "table" then
    return false, "delete_row requires table segment"
  end
  local row_index = op.row
  if type(row_index) ~= "number" or row_index < 1 or row_index > #segment.rows then
    return false, "row not found"
  end
  table.remove(segment.rows, row_index)
  return true
end

local function apply_add_sheet(workbook, op)
  return workbook_model.add_sheet(workbook, op.sheet or {})
end

local function apply_select_sheet(workbook, op)
  return workbook_model.select_sheet(workbook, op.sheet)
end

local function get_active_sheet(workbook)
  local sheet = workbook_model.get_active_sheet(workbook)
  if not sheet then
    return nil, "active sheet not found"
  end
  return sheet
end

local function apply_one(workbook, op)
  if type(op) ~= "table" or type(op.op) ~= "string" then
    return false, "operation must be an object with op"
  end

  if op.op == "add_sheet" then
    return apply_add_sheet(workbook, op)
  elseif op.op == "select_sheet" then
    return apply_select_sheet(workbook, op)
  end

  local sheet, err = get_active_sheet(workbook)
  if not sheet then
    return false, err
  end

  if op.op == "set_cell" then
    return apply_set_cell(sheet, op)
  elseif op.op == "insert_row" then
    return apply_insert_row(sheet, op)
  elseif op.op == "delete_row" then
    return apply_delete_row(sheet, op)
  end

  return false, "unsupported operation: " .. op.op
end

function M.apply(workbook, operations)
  for index = 1, #operations do
    local ok, err = apply_one(workbook, operations[index])
    if not ok then
      return false, {
        index = index,
        message = err,
      }
    end
  end
  return true
end

return M
