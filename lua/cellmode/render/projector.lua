local config = require("cellmode.config")
local workbook_model = require("cellmode.model.workbook")
local cell_marks = require("cellmode.codec.cell_marks")

local M = {}

local fn = vim.fn

local function row_max_index(row)
  local max_col = 0
  for key, _ in pairs(row or {}) do
    if type(key) == "number" and key > max_col and key >= 1 and math.floor(key) == key then
      max_col = key
    end
  end
  return max_col
end

local function display_width(text)
  if not text:find("[\t\128-\255]") then
    return #text
  end
  return fn.strdisplaywidth(text)
end

local function pad(text, width, padding)
  local diff = width - display_width(text)
  if diff <= 0 then
    return text
  end
  return text .. string.rep(padding, diff)
end

local function build_width_cache(rows)
  local widths = {}
  local max_row_by_col = {}
  for irow = 1, #rows do
    local row = rows[irow] or {}
    local ncol = row_max_index(row)
    for icol = 1, ncol do
      local width = math.max(2, display_width(cell_marks.encode(row[icol] or "")))
      if width >= (widths[icol] or 0) then
        widths[icol] = width
        max_row_by_col[icol] = irow
      end
    end
  end
  return {
    widths = widths,
    max_row_by_col = max_row_by_col,
    row_count = #rows,
  }
end

local function refresh_width_cache(rows, previous_cache, dirty_hint)
  if not previous_cache then
    return build_width_cache(rows)
  end

  local widths = vim.deepcopy(previous_cache.widths or {})
  local max_row_by_col = vim.deepcopy(previous_cache.max_row_by_col or {})
  local cols_to_rescan = {}

  local row_start = dirty_hint and dirty_hint.row_start or 1
  local row_end = dirty_hint and dirty_hint.row_end or #rows
  row_start = math.max(1, row_start or 1)
  row_end = math.max(row_start, row_end or #rows)

  for icol = 1, #widths do
    local max_row = max_row_by_col[icol]
    if type(max_row) ~= "number" or max_row > #rows then
      cols_to_rescan[icol] = true
    end
  end

  for irow = row_start, math.min(row_end, #rows) do
    local row = rows[irow] or {}
    local ncol = math.max(#widths, row_max_index(row))
    for icol = 1, ncol do
      local value_width = math.max(2, display_width(cell_marks.encode(row[icol] or "")))
      local old_width = widths[icol] or 0
      if value_width >= old_width then
        widths[icol] = value_width
        max_row_by_col[icol] = irow
      elseif max_row_by_col[icol] == irow then
        cols_to_rescan[icol] = true
      end
    end
  end

  for icol, _ in pairs(cols_to_rescan) do
    local best_width = 0
    local best_row = nil
    for irow = 1, #rows do
      local row = rows[irow] or {}
      local width = math.max(2, display_width(cell_marks.encode(row[icol] or "")))
      if width >= best_width then
        best_width = width
        best_row = irow
      end
    end
    if best_width > 0 then
      widths[icol] = best_width
      max_row_by_col[icol] = best_row
    else
      widths[icol] = nil
      max_row_by_col[icol] = nil
    end
  end

  local max_col = 0
  for irow = 1, #rows do
    max_col = math.max(max_col, row_max_index(rows[irow] or {}))
  end
  for icol = #widths, max_col + 1, -1 do
    widths[icol] = nil
    max_row_by_col[icol] = nil
  end

  return {
    widths = widths,
    max_row_by_col = max_row_by_col,
    row_count = #rows,
  }
end

local function project_table(segment, width_cache)
  local lines = {}
  local mapping = {}
  local pipe = config.marks.pipe
  local padding = config.marks.padding
  local widths = width_cache.widths
  for irow = 1, #segment.rows do
    local row = segment.rows[irow] or {}
    local cells = {}
    for icol = 1, #widths do
      local cell = row[icol] or ""
      cell = cell_marks.encode(cell)
      cells[icol] = pad(cell, widths[icol], padding)
    end
    lines[#lines + 1] = pipe .. table.concat(cells, pipe) .. pipe
    mapping[#mapping + 1] = {
      kind = "table",
      row = irow,
    }
  end
  return lines, mapping
end

local function project_plain(segment)
  local lines = {}
  local mapping = {}
  for iline = 1, #segment.lines do
    lines[#lines + 1] = segment.lines[iline]
    mapping[#mapping + 1] = {
      kind = "plain",
      line = iline,
    }
  end
  return lines, mapping
end

function M.project_segment(segment, cache_entry, dirty_hint)
  if segment.kind == "table" then
    local width_cache = refresh_width_cache(segment.rows or {}, cache_entry, dirty_hint)
    local lines, map = project_table(segment, width_cache)
    return lines, map, width_cache
  end
  local lines, map = project_plain(segment)
  return lines, map, nil
end

function M.project_sheet(sheet, cache_by_segment, dirty_by_segment)
  cache_by_segment = cache_by_segment or {}
  local lines = {}
  local mapping = {}
  local segments = {}
  for isegment = 1, #sheet.segments do
    local segment = sheet.segments[isegment]
    local part_lines
    local part_map
    local line_start = #lines + 1
    if segment.kind == "table" then
      part_lines, part_map, cache_by_segment[isegment] = M.project_segment(
        segment,
        cache_by_segment[isegment],
        dirty_by_segment and dirty_by_segment[isegment]
      )
    else
      part_lines, part_map = M.project_segment(segment)
      cache_by_segment[isegment] = nil
    end

    for index = 1, #part_lines do
      lines[#lines + 1] = part_lines[index]
      local map = part_map[index]
      map.segment = isegment
      mapping[#mapping + 1] = map
    end
    segments[isegment] = {
      kind = segment.kind,
      line_start = line_start,
      line_end = #lines,
    }
  end
  return {
    lines = lines,
    map = mapping,
    segments = segments,
    segment_widths = cache_by_segment,
  }
end

function M.project_workbook(workbook, cache_by_segment, dirty_by_segment)
  local sheet = workbook_model.get_active_sheet(workbook)
  if not sheet then
    return {
      lines = {},
      map = {},
      segments = {},
      segment_widths = {},
    }
  end
  return M.project_sheet(sheet, cache_by_segment, dirty_by_segment)
end

function M.diff_ranges(old_lines, new_lines)
  local old_len = #old_lines
  local new_len = #new_lines
  local prefix = 0
  local max_prefix = math.min(old_len, new_len)
  while prefix < max_prefix and old_lines[prefix + 1] == new_lines[prefix + 1] do
    prefix = prefix + 1
  end

  if prefix == old_len and prefix == new_len then
    return nil
  end

  local suffix = 0
  local max_suffix = math.min(old_len - prefix, new_len - prefix)
  while suffix < max_suffix do
    if old_lines[old_len - suffix] ~= new_lines[new_len - suffix] then
      break
    end
    suffix = suffix + 1
  end

  local old_start = prefix + 1
  local old_end = old_len - suffix
  local new_start = prefix + 1
  local new_end = new_len - suffix

  return {
    old_start = old_start,
    old_end = old_end,
    new_start = new_start,
    new_end = new_end,
  }
end

return M
