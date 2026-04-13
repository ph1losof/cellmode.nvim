local M = {}

local function as_string(value)
  if value == nil then
    return ""
  end
  if type(value) == "string" then
    return value
  end
  return tostring(value)
end

local function normalize_row(row)
  local out = {}
  for index = 1, #row do
    out[index] = as_string(row[index])
  end
  return out
end

local function row_max_index(row)
  local max_col = 0
  for key, _ in pairs(row or {}) do
    if type(key) == "number" and key > max_col and key >= 1 and math.floor(key) == key then
      max_col = key
    end
  end
  return max_col
end

local function normalize_segment(segment)
  local kind = segment.kind or "plain"
  if kind == "table" then
    local rows = segment.rows or {}
    local normalized_rows = {}
    for irow = 1, #rows do
      normalized_rows[irow] = normalize_row(rows[irow] or {})
    end
    return {
      kind = "table",
      rows = normalized_rows,
      meta = segment.meta or {},
    }
  end

  local lines = segment.lines or {}
  local normalized_lines = {}
  for iline = 1, #lines do
    normalized_lines[iline] = as_string(lines[iline])
  end
  return {
    kind = "plain",
    lines = normalized_lines,
    meta = segment.meta or {},
  }
end

local function normalize_sheet(sheet)
  local segments = sheet.segments or {}
  local normalized_segments = {}
  for index = 1, #segments do
    normalized_segments[index] = normalize_segment(segments[index])
  end

  return {
    id = as_string(sheet.id),
    name = as_string(sheet.name),
    segments = normalized_segments,
    meta = sheet.meta or {},
  }
end

local function index_sheets_by_id(sheets)
  local by_id = {}
  local by_name = {}
  for index = 1, #sheets do
    local sheet = sheets[index]
    if sheet.id ~= "" then
      by_id[sheet.id] = index
    end
    if sheet.name ~= "" then
      by_name[sheet.name] = index
    end
  end
  return by_id, by_name
end

function M.new(workbook)
  local source = workbook or {}
  local sheets = source.sheets or {}
  local normalized_sheets = {}
  for index = 1, #sheets do
    normalized_sheets[index] = normalize_sheet(sheets[index])
  end

  local by_id, by_name = index_sheets_by_id(normalized_sheets)
  local active_sheet = source.active_sheet
  if type(active_sheet) == "string" then
    active_sheet = by_id[active_sheet] or by_name[active_sheet] or 1
  end
  if type(active_sheet) ~= "number" or active_sheet < 1 or active_sheet > #normalized_sheets then
    active_sheet = #normalized_sheets > 0 and 1 or 0
  end

  return {
    id = as_string(source.id),
    format = as_string(source.format),
    sheets = normalized_sheets,
    active_sheet = active_sheet,
    meta = source.meta or {},
    _index = {
      by_id = by_id,
      by_name = by_name,
    },
  }
end

function M.new_sheet(id, name, segments)
  return normalize_sheet({
    id = id,
    name = name,
    segments = segments,
  })
end

function M.list_sheet_names(workbook)
  local names = {}
  for index = 1, #workbook.sheets do
    names[index] = workbook.sheets[index].name
  end
  return names
end

function M.resolve_sheet_index(workbook, id_or_name_or_index)
  if type(id_or_name_or_index) == "number" then
    local index = id_or_name_or_index
    if index >= 1 and index <= #workbook.sheets then
      return index
    end
    return nil
  end

  if type(id_or_name_or_index) ~= "string" then
    return nil
  end
  return workbook._index.by_id[id_or_name_or_index] or workbook._index.by_name[id_or_name_or_index]
end

function M.get_sheet(workbook, id_or_name_or_index)
  local index = M.resolve_sheet_index(workbook, id_or_name_or_index)
  if not index then
    return nil
  end
  return workbook.sheets[index], index
end

function M.select_sheet(workbook, id_or_name_or_index)
  local _, index = M.get_sheet(workbook, id_or_name_or_index)
  if not index then
    return false, "sheet not found"
  end
  workbook.active_sheet = index
  return true
end

function M.get_active_sheet(workbook)
  if workbook.active_sheet == 0 then
    return nil
  end
  return workbook.sheets[workbook.active_sheet]
end

function M.to_external(workbook)
  local sheets = vim.deepcopy(workbook.sheets)
  for isheet = 1, #sheets do
    local sheet = sheets[isheet]
    for isegment = 1, #(sheet.segments or {}) do
      local segment = sheet.segments[isegment]
      if segment.kind == "table" then
        local rows = segment.rows or {}
        local max_col = 0
        for irow = 1, #rows do
          max_col = math.max(max_col, row_max_index(rows[irow] or {}))
        end
        for irow = 1, #rows do
          local row = rows[irow] or {}
          local normalized = {}
          for icol = 1, max_col do
            normalized[icol] = as_string(row[icol])
          end
          rows[irow] = normalized
        end
      end
    end
  end
  return {
    id = workbook.id,
    format = workbook.format,
    active_sheet = workbook.active_sheet,
    meta = vim.deepcopy(workbook.meta),
    sheets = sheets,
  }
end

function M.add_sheet(workbook, sheet)
  local normalized = normalize_sheet(sheet)
  if normalized.id ~= "" and workbook._index.by_id[normalized.id] then
    return false, "duplicate sheet id"
  end
  if normalized.name ~= "" and workbook._index.by_name[normalized.name] then
    return false, "duplicate sheet name"
  end

  local index = #workbook.sheets + 1
  workbook.sheets[index] = normalized
  if normalized.id ~= "" then
    workbook._index.by_id[normalized.id] = index
  end
  if normalized.name ~= "" then
    workbook._index.by_name[normalized.name] = index
  end
  if workbook.active_sheet == 0 then
    workbook.active_sheet = 1
  end
  return true
end

return M
