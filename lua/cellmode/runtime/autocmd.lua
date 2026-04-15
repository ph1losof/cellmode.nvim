local controller = require("cellmode.runtime.controller")
local session_store = require("cellmode.runtime.session_store")
local overlay = require("cellmode.view.overlay")
local sticky_header = require("cellmode.view.sticky_header")
local scheduler = require("cellmode.runtime.scheduler")
local messages = require("cellmode.runtime.messages")
local auto_quote = require("cellmode.runtime.auto_quote")

local M = {}

local GROUP = "cellmode"
local pending_change = {}

local function flush_pending(bufnr)
  local change = pending_change[bufnr]
  if not change then
    return
  end
  pending_change[bufnr] = nil
  controller.on_buffer_changed(bufnr, change)
end

local function schedule_changed(bufnr)
  scheduler.next_tick(bufnr, "changed", function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      pending_change[bufnr] = nil
      return
    end
    flush_pending(bufnr)
  end)
end

local function record_change(bufnr, firstline, lastline, new_lastline)
  local prev = pending_change[bufnr]
  if not prev then
    pending_change[bufnr] = {
      first_line = firstline,
      last_line = lastline,
      new_last_line = new_lastline,
    }
    return
  end
  prev.first_line = math.min(prev.first_line, firstline)
  prev.last_line = math.max(prev.last_line, lastline)
  prev.new_last_line = math.max(prev.new_last_line, new_lastline)
end

function M.attach_buffer_tracking(bufnr)
  if vim.b[bufnr].cellmode_lines_attached then
    return
  end
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function(_, changed_bufnr, _, firstline, lastline, new_lastline)
      if not session_store.get(changed_bufnr) then
        return
      end
      if session_store.is_updating_buffer(changed_bufnr) then
        return
      end
      record_change(changed_bufnr, firstline, lastline, new_lastline)
      schedule_changed(changed_bufnr)
    end,
    on_detach = function(_, detached_bufnr)
      vim.b[detached_bufnr].cellmode_lines_attached = false
      pending_change[detached_bufnr] = nil
    end,
  })
  vim.b[bufnr].cellmode_lines_attached = true
end

local function should_attach(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    return false
  end
  if not vim.bo[bufnr].modifiable then
    return false
  end
  return true
end

local function format_for_buffer(bufnr)
  local ft = vim.bo[bufnr].filetype
  if ft == "csv" or ft == "tsv" then
    return ft
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  local ext = path:match("^.+%.([^.]+)$")
  if ext == "csv" or ext == "tsv" then
    return ext
  end
  return nil
end

local function on_buf_read_post(args)
  local bufnr = args.buf
  if not should_attach(bufnr) then
    return
  end
  if session_store.get(bufnr) then
    return
  end
  local format = format_for_buffer(bufnr)
  if not format then
    return
  end
  local ok, err = controller.open(bufnr, { format = format })
  if not ok then
    messages.error(err)
    return
  end
  M.attach_buffer_tracking(bufnr)
end

local function on_buf_wipeout(args)
  sticky_header.disable_for_buffer(args.buf)
  controller.close(args.buf)
  scheduler.clear_for_buffer(args.buf)
  pending_change[args.buf] = nil
end

local function on_win_enter(args)
  local bufnr = args.buf
  if not session_store.get(bufnr) then
    return
  end
  local winid = vim.api.nvim_get_current_win()
  if sticky_header.is_float(winid) then
    return
  end
  overlay.apply_window_options(winid)
  sticky_header.refresh(winid)
end

local function on_text_changed_i(args)
  if not session_store.get(args.buf) then
    return
  end
  auto_quote.handle_text_changed(args.buf)
end

local function on_win_scrolled()
  local event = vim.v.event or {}
  local handled = false
  for key, _ in pairs(event) do
    local winid = tonumber(key)
    if winid and winid > 0 and not sticky_header.is_float(winid) then
      sticky_header.refresh(winid)
      handled = true
    end
  end
  if not handled then
    sticky_header.refresh(vim.api.nvim_get_current_win())
  end
end

local function on_win_resized()
  local event = vim.v.event or {}
  local wins = event.windows
  if type(wins) == "table" then
    for _, winid in ipairs(wins) do
      if not sticky_header.is_float(winid) then
        sticky_header.refresh(winid)
      end
    end
  else
    sticky_header.refresh(vim.api.nvim_get_current_win())
  end
end

local function on_win_closed(args)
  local winid = tonumber(args.match)
  if not winid then
    return
  end
  if sticky_header.is_float(winid) then
    sticky_header.forget_float(winid)
  else
    sticky_header.disable_for_win(winid)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", { group = group, callback = on_buf_read_post })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, { group = group, callback = on_buf_wipeout })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, { group = group, callback = on_win_enter })
  vim.api.nvim_create_autocmd("TextChangedI", { group = group, callback = on_text_changed_i })
  vim.api.nvim_create_autocmd("WinScrolled", { group = group, callback = on_win_scrolled })
  vim.api.nvim_create_autocmd("WinResized", { group = group, callback = on_win_resized })
  vim.api.nvim_create_autocmd("WinClosed", { group = group, callback = on_win_closed })
end

return M
