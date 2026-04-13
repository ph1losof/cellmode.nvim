local M = {}

local sessions = {}

local function now_ms()
  return math.floor(vim.loop.hrtime() / 1000000)
end

function M.open(bufnr, session)
  if type(bufnr) ~= "number" or bufnr <= 0 then
    error("bufnr must be a positive number")
  end
  local data = vim.deepcopy(session or {})
  data.dirty_segments = data.dirty_segments or {}
  data.segment_widths = data.segment_widths or {}
  data.changed_line_ranges = data.changed_line_ranges or {}
  data.updating_buffer = false
  data.bufnr = bufnr
  data.updated_at = now_ms()
  sessions[bufnr] = data
  return data
end

function M.update(bufnr, patch)
  local session = sessions[bufnr]
  if not session then
    return nil
  end
  for key, value in pairs(patch or {}) do
    session[key] = value
  end
  session.updated_at = now_ms()
  return session
end

function M.get(bufnr)
  return sessions[bufnr]
end

function M.touch(bufnr)
  local session = sessions[bufnr]
  if not session then
    return false
  end
  session.updated_at = now_ms()
  return true
end

function M.close(bufnr)
  sessions[bufnr] = nil
end

function M.clear_invalid()
  for bufnr, _ in pairs(sessions) do
    if not vim.api.nvim_buf_is_valid(bufnr) then
      sessions[bufnr] = nil
    end
  end
end

function M.is_updating_buffer(bufnr)
  local session = sessions[bufnr]
  return session and session.updating_buffer == true or false
end

function M.set_updating_buffer(bufnr, value)
  local session = sessions[bufnr]
  if not session then
    return false
  end
  session.updating_buffer = value == true
  return true
end

function M.push_changed_line_range(bufnr, range)
  local session = sessions[bufnr]
  if not session then
    return false
  end
  if type(range) ~= "table" then
    return false
  end
  session.changed_line_ranges[#session.changed_line_ranges + 1] = {
    old_start = range.old_start,
    old_end = range.old_end,
    new_start = range.new_start,
    new_end = range.new_end,
  }
  return true
end

function M.consume_changed_line_ranges(bufnr)
  local session = sessions[bufnr]
  if not session then
    return {}
  end
  local ranges = session.changed_line_ranges or {}
  session.changed_line_ranges = {}
  return ranges
end

function M.mark_dirty_segment(bufnr, segment_index, row_start, row_end)
  local session = sessions[bufnr]
  if not session then
    return false
  end
  if type(segment_index) ~= "number" or segment_index < 1 then
    return false
  end
  local current = session.dirty_segments[segment_index]
  if not current then
    session.dirty_segments[segment_index] = {
      row_start = row_start,
      row_end = row_end,
    }
    return true
  end
  if type(row_start) == "number" then
    current.row_start = current.row_start and math.min(current.row_start, row_start) or row_start
  end
  if type(row_end) == "number" then
    current.row_end = current.row_end and math.max(current.row_end, row_end) or row_end
  end
  return true
end

function M.consume_dirty_segments(bufnr)
  local session = sessions[bufnr]
  if not session then
    return {}
  end
  local dirty = session.dirty_segments or {}
  session.dirty_segments = {}
  return dirty
end

function M.count()
  local n = 0
  for _, _ in pairs(sessions) do
    n = n + 1
  end
  return n
end

return M
