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
  data.bufnr = bufnr
  data.updating_buffer = false
  data.overlay_visible = data.overlay_visible ~= false
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

function M.close(bufnr)
  sessions[bufnr] = nil
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

function M.set_overlay_visible(bufnr, value)
  local session = sessions[bufnr]
  if not session then
    return false
  end
  session.overlay_visible = value == true
  return true
end

function M.count()
  local n = 0
  for _, _ in pairs(sessions) do
    n = n + 1
  end
  return n
end

function M.clear_invalid()
  for bufnr, _ in pairs(sessions) do
    if not vim.api.nvim_buf_is_valid(bufnr) then
      sessions[bufnr] = nil
    end
  end
end

return M
