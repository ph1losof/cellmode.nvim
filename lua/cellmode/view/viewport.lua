local M = {}

local VIEW_MARGIN = 40

function M.visible_range(winid)
  local range = vim.api.nvim_win_call(winid, function()
    return { vim.fn.line("w0"), vim.fn.line("w$") }
  end)
  return range[1], range[2]
end

function M.expanded_range(winid, line_count)
  local top, bottom = M.visible_range(winid)
  top = math.max(1, top - VIEW_MARGIN)
  bottom = math.min(line_count, bottom + VIEW_MARGIN)
  return top, bottom
end

function M.bucketed_key(winid, tick)
  local top, bottom = M.visible_range(winid)
  local leftcol = vim.api.nvim_win_call(winid, function()
    return vim.fn.winsaveview().leftcol
  end)
  local width = vim.api.nvim_win_get_width(winid)
  return table.concat({
    tick,
    math.floor(top / 10),
    math.floor(bottom / 10),
    math.floor(leftcol / 8),
    width,
  }, ":")
end

return M
