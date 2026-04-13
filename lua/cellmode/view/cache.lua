local M = {}

local state = {}

local function key(bufnr, winid)
  return string.format("%d:%d", bufnr, winid)
end

function M.get(bufnr, winid)
  return state[key(bufnr, winid)]
end

function M.set(bufnr, winid, value)
  state[key(bufnr, winid)] = value
end

function M.clear(bufnr, winid)
  if bufnr and winid then
    state[key(bufnr, winid)] = nil
    return
  end
  if bufnr then
    local prefix = tostring(bufnr) .. ":"
    for k, _ in pairs(state) do
      if k:sub(1, #prefix) == prefix then
        state[k] = nil
      end
    end
    return
  end
  state = {}
end

return M
