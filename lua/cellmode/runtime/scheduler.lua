local M = {}

local timer_pending = {}

function M.once(bufnr, key, delay_ms, fn)
  local token = string.format("%d:%s", bufnr, key)
  if timer_pending[token] then
    return
  end
  timer_pending[token] = true
  vim.defer_fn(function()
    timer_pending[token] = nil
    fn()
  end, delay_ms)
end

function M.next_tick(bufnr, key, fn)
  local token = string.format("%d:%s", bufnr, key)
  if timer_pending[token] then
    return
  end
  timer_pending[token] = true
  vim.schedule(function()
    timer_pending[token] = nil
    fn()
  end)
end

function M.clear_for_buffer(bufnr)
  local prefix = tostring(bufnr) .. ":"
  for token, _ in pairs(timer_pending) do
    if token:sub(1, #prefix) == prefix then
      timer_pending[token] = nil
    end
  end
end

return M
