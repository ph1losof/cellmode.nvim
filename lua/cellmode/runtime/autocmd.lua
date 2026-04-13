local controller = require("cellmode.runtime.controller")
local session_store = require("cellmode.runtime.session_store")
local resolver = require("cellmode.runtime.adapter_resolver")
local messages = require("cellmode.runtime.messages")
local table_view = require("cellmode.ui.table_view")
local scheduler = require("cellmode.runtime.scheduler")
local adapter_client = require("cellmode.adapter.client")

local M = {}

local GROUP = "cellmode"
local reformat_busy = {}
local write_group = nil

local function schedule_table_view(bufnr, winid)
  scheduler.once(bufnr, "view", 16, function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if not session_store.get(bufnr) then
      return
    end
    if (not winid or not vim.api.nvim_win_is_valid(winid)) then
      local wins = vim.fn.win_findbuf(bufnr)
      winid = wins[1]
    end
    if winid and vim.api.nvim_win_is_valid(winid) then
      pcall(table_view.apply, winid)
    end
  end)
end

local function schedule_reformat(bufnr)
  scheduler.next_tick(bufnr, "reformat", function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    if reformat_busy[bufnr] or not session_store.get(bufnr) then
      return
    end
    local ranges = session_store.consume_changed_line_ranges(bufnr)
    if #ranges == 0 then
      return
    end
    reformat_busy[bufnr] = true
    local ok, result, err = pcall(controller.reformat_from_changed_ranges, bufnr, ranges)
    reformat_busy[bufnr] = nil
    if not ok then
      messages.error(result)
      return
    end
    if result == false then
      messages.error(err)
      return
    end
    schedule_table_view(bufnr)
  end)
end

local function push_changed_range(bufnr, firstline, lastline, new_lastline)
  local old_start = firstline + 1
  local old_end = math.max(old_start - 1, lastline)
  local new_start = firstline + 1
  local new_end = math.max(new_start - 1, new_lastline)
  session_store.push_changed_line_range(bufnr, {
    old_start = old_start,
    old_end = old_end,
    new_start = new_start,
    new_end = new_end,
  })
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
      push_changed_range(changed_bufnr, firstline, lastline, new_lastline)
      schedule_reformat(changed_bufnr)
    end,
    on_detach = function(_, detached_bufnr)
      vim.b[detached_bufnr].cellmode_lines_attached = false
    end,
  })
  vim.b[bufnr].cellmode_lines_attached = true
end

local function should_skip(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return true
  end
  if not vim.bo[bufnr].modifiable then
    return true
  end
  return vim.api.nvim_buf_get_name(bufnr) == ""
end

local function on_buf_read_post(args)
  local bufnr = args.buf
  if should_skip(bufnr) or session_store.get(bufnr) then
    return
  end

  local spec = resolver.from_buffer(bufnr)
  if not spec then
    return
  end

  local ok, err = controller.open_from_adapter(bufnr, spec.command, spec.path, spec.format)
  if not ok then
    messages.error(err)
    return
  end
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].swapfile = false
  M.attach_write_cmd(bufnr)
  M.attach_buffer_tracking(bufnr)
end

local function on_buf_write_cmd(args)
  local bufnr = args.buf
  if not session_store.get(bufnr) then
    return
  end
  local spec = resolver.from_buffer(bufnr)
  if not spec then
    messages.error("adapter is not configured for this buffer")
    return
  end
  local ok, err = controller.save_to_adapter(bufnr, spec.path, spec.format)
  if not ok then
    messages.error(err)
    return
  end
  vim.bo[bufnr].modified = false
end

function M.attach_write_cmd(bufnr)
  if not write_group then
    return
  end
  if vim.b[bufnr].cellmode_write_cmd_attached then
    return
  end
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = write_group,
    buffer = bufnr,
    callback = on_buf_write_cmd,
  })
  vim.b[bufnr].cellmode_write_cmd_attached = true
end

local function on_buf_wipeout(args)
  session_store.close(args.buf)
  scheduler.clear_for_buffer(args.buf)
  pcall(table_view.clear_buffer, args.buf)
end

local function on_win_enter(args)
  if not session_store.get(args.buf) then
    return
  end
  local winid = vim.api.nvim_get_current_win()
  schedule_table_view(args.buf, winid)
end

local function on_win_scrolled(args)
  local bufnr = args.buf ~= 0 and args.buf or vim.api.nvim_get_current_buf()
  if not session_store.get(bufnr) then
    return
  end
  local winid = vim.api.nvim_get_current_win()
  schedule_table_view(bufnr, winid)
end

function M.setup()
  local group = vim.api.nvim_create_augroup(GROUP, { clear = true })
  write_group = vim.api.nvim_create_augroup(GROUP .. "_write", { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", { group = group, callback = on_buf_read_post })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, { group = group, callback = on_buf_wipeout })
  vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, { group = group, callback = on_win_enter })
  vim.api.nvim_create_autocmd("WinScrolled", { group = group, callback = on_win_scrolled })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      adapter_client.shutdown_all()
    end,
  })
end

return M
