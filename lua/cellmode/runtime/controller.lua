local workbook_model = require("cellmode.model.workbook")
local session_store = require("cellmode.runtime.session_store")
local transaction = require("cellmode.engine.transaction")
local projector = require("cellmode.render.projector")
local adapter_client = require("cellmode.adapter.client")
local workbook_loader = require("cellmode.adapter.workbook_loader")
local table_view = require("cellmode.ui.table_view")
local cell_marks = require("cellmode.codec.cell_marks")
local table_line = require("cellmode.text.table_line")

local M = {}

local function try_undojoin(bufnr)
  if vim.api.nvim_get_current_buf() ~= bufnr then
    return
  end
  pcall(vim.cmd, "silent! undojoin")
end

local function replace_lines(bufnr, start_row, end_row, replacement, join_undo)
  if join_undo then
    try_undojoin(bufnr)
  end
  session_store.set_updating_buffer(bufnr, true)
  vim.api.nvim_buf_set_lines(bufnr, start_row, end_row, false, replacement)
  session_store.set_updating_buffer(bufnr, false)
end

local function set_buffer_lines(bufnr, lines)
  session_store.set_updating_buffer(bufnr, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  session_store.set_updating_buffer(bufnr, false)
end

local function apply_table_ui(bufnr, changed_range)
  local wins = vim.fn.win_findbuf(bufnr)
  for _, winid in ipairs(wins) do
    if vim.api.nvim_win_is_valid(winid) then
      pcall(table_view.apply, winid, { changed_ranges = changed_range and { changed_range } or nil })
    end
  end
end

local function is_table_line(line)
  return table_line.get_cells(line) ~= nil
end

local function decode_table_row(line)
  local cells = table_line.get_cells(line)
  if not cells then
    return nil
  end
  for icol = 1, #cells do
    cells[icol] = cell_marks.decode(cell_marks.strip_padding(cells[icol]))
  end
  return cells
end

local function parse_buffer_lines(lines, map)
  local segments = {}
  local next_segment_index = 1
  local fallback_state = {
    kind = nil,
    segment_index = nil,
  }

  local function ensure_segment(kind, segment_index)
    local segment = segments[segment_index]
    if segment and segment.kind == kind then
      return segment
    end
    if kind == "table" then
      segment = { kind = "table", rows = {} }
    else
      segment = { kind = "plain", lines = {} }
    end
    segments[segment_index] = segment
    return segment
  end

  local function fallback_segment_index(kind)
    if fallback_state.kind == kind and fallback_state.segment_index then
      return fallback_state.segment_index
    end
    local index = next_segment_index
    next_segment_index = next_segment_index + 1
    fallback_state.kind = kind
    fallback_state.segment_index = index
    return index
  end

  for iline = 1, #lines do
    local line = lines[iline]
    local cells = table_line.get_cells(line)
    local map_item = map and map[iline]
    local segment_index = map_item and map_item.segment
    if type(segment_index) ~= "number" or segment_index < 1 then
      segment_index = fallback_segment_index(cells and "table" or "plain")
    else
      fallback_state.kind = nil
      fallback_state.segment_index = nil
    end
    if cells then
      for icol = 1, #cells do
        cells[icol] = cell_marks.decode(cell_marks.strip_padding(cells[icol]))
      end
      local segment = ensure_segment("table", segment_index)
      segment.rows[#segment.rows + 1] = cells
    else
      local segment = ensure_segment("plain", segment_index)
      segment.lines[#segment.lines + 1] = line
    end
  end

  local ordered = {}
  for index = 1, #segments do
    if segments[index] then
      ordered[#ordered + 1] = segments[index]
    end
  end
  if #ordered == 0 then
    return { { kind = "plain", lines = {} } }
  end
  return ordered
end

local function apply_session_projection(bufnr, projection)
  local session = session_store.update(bufnr, {
    projection = projection,
    segment_widths = projection.segment_widths or {},
  })
  if not session then
    return false, "session not found"
  end
  return true
end

local function patch_projection_lines(bufnr, previous_lines, projection, join_undo)
  local diff = projector.diff_ranges(previous_lines or {}, projection.lines)
  if not diff then
    return true
  end
  local replacement = {}
  if diff.new_start <= diff.new_end then
    for index = diff.new_start, diff.new_end do
      replacement[#replacement + 1] = projection.lines[index]
    end
  end
  replace_lines(bufnr, diff.old_start - 1, diff.old_end, replacement, join_undo)
  apply_table_ui(bufnr, { start_line = diff.old_start, end_line = diff.old_start + #replacement - 1 })
  return true
end

local function apply_projection(bufnr, projection)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  local previous_lines = session.projection and session.projection.lines or {}
  patch_projection_lines(bufnr, previous_lines, projection, false)
  return apply_session_projection(bufnr, projection)
end

function M.open_workbook(bufnr, workbook)
  local normalized = workbook_model.new(workbook)
  local projection = projector.project_workbook(normalized)
  set_buffer_lines(bufnr, projection.lines)
  apply_table_ui(bufnr)
  session_store.open(bufnr, {
    workbook = normalized,
    projection = projection,
    segment_widths = projection.segment_widths,
  })
  return true
end

function M.open_from_adapter(bufnr, adapter_command, path, format)
  local loaded, load_err = workbook_loader.open(adapter_command, path, format)
  if not loaded then
    return false, load_err
  end

  local ok = M.open_workbook(bufnr, loaded.workbook)
  if not ok then
    return false, "failed to open workbook"
  end

  session_store.update(bufnr, { adapter = loaded.adapter })
  return true
end

function M.apply_operations(bufnr, operations)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  local ok, tx_err = transaction.apply(session.workbook, operations)
  if not ok then
    return false, tx_err
  end
  local dirty_segments = {}
  local sheet = workbook_model.get_active_sheet(session.workbook)
  if sheet then
    for index = 1, #sheet.segments do
      dirty_segments[index] = { row_start = 1, row_end = math.huge }
    end
  end
  local projection = projector.project_workbook(session.workbook, session.segment_widths, dirty_segments)
  return apply_projection(bufnr, projection)
end

function M.select_sheet(bufnr, target)
  return M.apply_operations(bufnr, {
    { op = "select_sheet", sheet = target },
  })
end

function M.sync_active_sheet_from_buffer(bufnr)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  local sheet = workbook_model.get_active_sheet(session.workbook)
  if not sheet then
    return false, "active sheet not found"
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local map = session.projection and session.projection.map or nil
  sheet.segments = parse_buffer_lines(lines, map)
  local projection = projector.project_workbook(session.workbook)
  return apply_session_projection(bufnr, projection)
end

local function apply_range_rows_from_buffer(bufnr, session, lines, range)
  local map = session.projection and session.projection.map or {}
  local sheet = workbook_model.get_active_sheet(session.workbook)
  if not sheet then
    return false
  end

  local old_start = range.old_start
  local old_end = range.old_end
  local new_start = range.new_start
  local new_end = range.new_end
  local old_count = math.max(0, old_end - old_start + 1)
  local new_count = math.max(0, new_end - new_start + 1)

  if old_count ~= new_count then
    sheet.segments = parse_buffer_lines(lines, nil)
    for segment_index = 1, #sheet.segments do
      session_store.mark_dirty_segment(bufnr, segment_index, 1, math.huge)
    end
    return true
  end

  for offset = 0, new_count - 1 do
    local line_no = new_start + offset
    local line = lines[line_no] or ""
    local line_is_table = is_table_line(line)
    local map_item = map[old_start + offset]
    if map_item and type(map_item.segment) == "number" then
      local segment = sheet.segments[map_item.segment]
      if segment then
        if map_item.kind == "table" and segment.kind == "table" and type(map_item.row) == "number" then
          if not line_is_table then
            sheet.segments = parse_buffer_lines(lines, nil)
            for segment_index = 1, #sheet.segments do
              session_store.mark_dirty_segment(bufnr, segment_index, 1, math.huge)
            end
            return true
          end
          local row = decode_table_row(line)
          if row then
            segment.rows[map_item.row] = row
            session_store.mark_dirty_segment(bufnr, map_item.segment, map_item.row, map_item.row)
          end
        elseif map_item.kind == "plain" and segment.kind == "plain" and type(map_item.line) == "number" then
          if line_is_table then
            sheet.segments = parse_buffer_lines(lines, nil)
            for segment_index = 1, #sheet.segments do
              session_store.mark_dirty_segment(bufnr, segment_index, 1, math.huge)
            end
            return true
          end
          segment.lines[map_item.line] = line
          session_store.mark_dirty_segment(bufnr, map_item.segment, map_item.line, map_item.line)
        else
          sheet.segments = parse_buffer_lines(lines, nil)
          for segment_index = 1, #sheet.segments do
            session_store.mark_dirty_segment(bufnr, segment_index, 1, math.huge)
          end
          return true
        end
      end
    end
  end
  return false
end

local function apply_dirty_projection(bufnr)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  local dirty_segments = session_store.consume_dirty_segments(bufnr)
  local dirty_indexes = {}
  for segment_index, _ in pairs(dirty_segments) do
    dirty_indexes[#dirty_indexes + 1] = segment_index
  end
  if #dirty_indexes == 0 then
    return true
  end
  table.sort(dirty_indexes)

  local min_segment = math.max(1, dirty_indexes[1] - 1)
  local max_segment = math.min(#session.workbook.sheets[session.workbook.active_sheet].segments, dirty_indexes[#dirty_indexes] + 1)
  local old_projection = session.projection
  local old_segments = old_projection.segments or {}
  local old_start = old_segments[min_segment] and old_segments[min_segment].line_start or 1
  local old_end = old_segments[max_segment] and old_segments[max_segment].line_end or #old_projection.lines

  local mid_lines = {}
  local mid_map = {}
  local segment_widths = session.segment_widths or {}
  local new_segments_meta = {}
  local cursor = old_start

  for segment_index = min_segment, max_segment do
    local segment = session.workbook.sheets[session.workbook.active_sheet].segments[segment_index]
    local lines_part, map_part, width_cache = projector.project_segment(segment, segment_widths[segment_index], dirty_segments[segment_index])
    segment_widths[segment_index] = width_cache
    new_segments_meta[segment_index] = {
      kind = segment.kind,
      line_start = cursor,
      line_end = cursor + #lines_part - 1,
    }
    cursor = cursor + #lines_part
    for i = 1, #lines_part do
      mid_lines[#mid_lines + 1] = lines_part[i]
      local entry = map_part[i]
      entry.segment = segment_index
      mid_map[#mid_map + 1] = entry
    end
  end

  local delta = #mid_lines - (old_end - old_start + 1)
  local new_lines = {}
  local new_map = {}
  for i = 1, old_start - 1 do
    new_lines[#new_lines + 1] = old_projection.lines[i]
    new_map[#new_map + 1] = old_projection.map[i]
  end
  for i = 1, #mid_lines do
    new_lines[#new_lines + 1] = mid_lines[i]
    new_map[#new_map + 1] = mid_map[i]
  end
  for i = old_end + 1, #old_projection.lines do
    new_lines[#new_lines + 1] = old_projection.lines[i]
    new_map[#new_map + 1] = old_projection.map[i]
  end

  local merged_segments = {}
  for i = 1, #old_segments do
    local meta = old_segments[i]
    if i < min_segment then
      merged_segments[i] = {
        kind = meta.kind,
        line_start = meta.line_start,
        line_end = meta.line_end,
      }
    elseif i <= max_segment then
      merged_segments[i] = new_segments_meta[i]
    else
      merged_segments[i] = {
        kind = meta.kind,
        line_start = meta.line_start + delta,
        line_end = meta.line_end + delta,
      }
    end
  end

  replace_lines(bufnr, old_start - 1, old_end, mid_lines, true)
  apply_table_ui(bufnr, { start_line = old_start, end_line = old_start + #mid_lines - 1 })

  return apply_session_projection(bufnr, {
    lines = new_lines,
    map = new_map,
    segments = merged_segments,
    segment_widths = segment_widths,
  })
end

function M.reformat_from_changed_ranges(bufnr, ranges)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  local sheet = workbook_model.get_active_sheet(session.workbook)
  if not sheet then
    return false, "active sheet not found"
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local structural = false
  for _, range in ipairs(ranges or {}) do
    if apply_range_rows_from_buffer(bufnr, session, lines, range) then
      structural = true
    end
  end
  if structural then
    session.segment_widths = {}
    local dirty_segments = {}
    for index = 1, #sheet.segments do
      dirty_segments[index] = { row_start = 1, row_end = math.huge }
    end
    local projection = projector.project_workbook(session.workbook, session.segment_widths, dirty_segments)
    patch_projection_lines(bufnr, session.projection and session.projection.lines or {}, projection, true)
    return apply_session_projection(bufnr, projection)
  end
  return apply_dirty_projection(bufnr)
end

function M.save_to_adapter(bufnr, path, format)
  local session = session_store.get(bufnr)
  if not session then
    return false, "session not found"
  end
  if not session.adapter then
    return false, "adapter not configured for this session"
  end
  local sync_ok, sync_err = M.sync_active_sheet_from_buffer(bufnr)
  if not sync_ok then
    return false, sync_err
  end
  local result, err = adapter_client.request(session.adapter.command, "write_workbook", {
    workbook = workbook_model.to_external(session.workbook),
    path = path,
    format = format or session.workbook.format,
  })
  if not result then
    return false, err
  end
  return true
end

return M
