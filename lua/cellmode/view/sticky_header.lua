local config = require("cellmode.config")
local cell_layout = require("cellmode.view.cell_layout")
local overlay = require("cellmode.view.overlay")
local session_store = require("cellmode.runtime.session_store")

local M = {}

local floats = {}
local float_winids = {}

function M.is_float(winid)
  return float_winids[winid] == true
end

local function close_float(winid)
  local state = floats[winid]
  if not state then
    return
  end
  floats[winid] = nil
  local fw = state.float_winid
  if fw and vim.api.nvim_win_is_valid(fw) then
    float_winids[fw] = nil
    pcall(vim.api.nvim_win_close, fw, true)
  else
    if fw then
      float_winids[fw] = nil
    end
  end
end

function M.disable_for_win(winid)
  close_float(winid)
end

local function apply_float_options(float_winid)
  vim.wo[float_winid].conceallevel = 2
  vim.wo[float_winid].concealcursor = "nvc"
  vim.wo[float_winid].wrap = false
  vim.wo[float_winid].cursorline = false
  vim.wo[float_winid].number = false
  vim.wo[float_winid].relativenumber = false
  vim.wo[float_winid].signcolumn = "no"
  vim.wo[float_winid].foldcolumn = "0"
  vim.wo[float_winid].list = false
  vim.wo[float_winid].winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat"
end

local function ensure_float(winid, bufnr, height, width, col_offset)
  local state = floats[winid]
  if state and state.float_winid and vim.api.nvim_win_is_valid(state.float_winid) then
    local cfg = vim.api.nvim_win_get_config(state.float_winid)
    if cfg.width ~= width or cfg.height ~= height or cfg.col ~= col_offset then
      vim.api.nvim_win_set_config(state.float_winid, {
        relative = "win",
        win = winid,
        row = 0,
        col = col_offset,
        width = width,
        height = height,
      })
    end
    return state.float_winid
  end

  local fw = vim.api.nvim_open_win(bufnr, false, {
    relative = "win",
    win = winid,
    row = 0,
    col = col_offset,
    width = width,
    height = height,
    focusable = false,
    style = "minimal",
    zindex = 50,
    noautocmd = true,
  })
  float_winids[fw] = true
  apply_float_options(fw)
  floats[winid] = { float_winid = fw, last_leftcol = -1 }
  return fw
end

function M.refresh(winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    close_float(winid)
    return
  end
  if float_winids[winid] then
    return
  end
  if config.sticky_header ~= true then
    close_float(winid)
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  local session = session_store.get(bufnr)
  if not session then
    close_float(winid)
    return
  end
  if not overlay.is_visible(bufnr) then
    close_float(winid)
    return
  end

  local layout = cell_layout.get(bufnr)
  if not layout or not layout.records or not layout.records[1] then
    close_float(winid)
    return
  end

  local header = layout.records[1]
  local header_start = header.buf_row_start
  local header_end = header.buf_row_end
  local height = header_end - header_start + 1

  local topline = vim.fn.line("w0", winid)
  if topline <= header_end then
    close_float(winid)
    return
  end

  local win_width = vim.api.nvim_win_get_width(winid)
  local textoff = 0
  local info = vim.fn.getwininfo(winid)
  if info and info[1] and info[1].textoff then
    textoff = info[1].textoff
  end
  local width = win_width - textoff
  if width <= 0 or height <= 0 then
    close_float(winid)
    return
  end

  local parent_view
  vim.api.nvim_win_call(winid, function()
    parent_view = vim.fn.winsaveview()
  end)
  local leftcol = parent_view and parent_view.leftcol or 0

  local fw = ensure_float(winid, bufnr, height, width, textoff)
  vim.api.nvim_win_call(fw, function()
    vim.fn.winrestview({
      topline = header_start,
      lnum = header_start,
      col = 0,
      leftcol = leftcol,
    })
  end)

  local state = floats[winid]
  if state then
    state.last_leftcol = leftcol
  end
end

function M.refresh_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if not float_winids[winid] then
      M.refresh(winid)
    end
  end
end

function M.disable_for_buffer(bufnr)
  if not bufnr then
    return
  end
  local wins = {}
  for winid, _ in pairs(floats) do
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
      wins[#wins + 1] = winid
    end
  end
  for _, winid in ipairs(wins) do
    close_float(winid)
  end
end

function M.forget_float(winid)
  if float_winids[winid] then
    float_winids[winid] = nil
    for parent, state in pairs(floats) do
      if state.float_winid == winid then
        floats[parent] = nil
        break
      end
    end
  end
end

function M.close_all()
  for winid, _ in pairs(floats) do
    close_float(winid)
  end
  floats = {}
  float_winids = {}
end

return M
