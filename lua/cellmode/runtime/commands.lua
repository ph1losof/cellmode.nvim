local controller = require("cellmode.runtime.controller")
local session_store = require("cellmode.runtime.session_store")
local cell_layout = require("cellmode.view.cell_layout")
local runtime_autocmd = require("cellmode.runtime.autocmd")
local runtime_config = require("cellmode.config")
local messages = require("cellmode.runtime.messages")

local M = {}

local api = vim.api

local function split_csv(value)
  local parts = vim.split(value or "", ",", { plain = true })
  local out = {}
  for index = 1, #parts do
    out[index] = vim.trim(parts[index])
  end
  return out
end

local function cmd_open(bufnr, fargs)
  local path = fargs[2]
  local format = fargs[3]
  if not path or not format then
    return false, "usage: Cellmode open <path> <csv|tsv>"
  end
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  bufnr = api.nvim_get_current_buf()
  if session_store.get(bufnr) then
    return true
  end
  local ok, err = controller.open(bufnr, { format = format })
  if not ok then
    return false, err
  end
  runtime_autocmd.attach_buffer_tracking(bufnr)
  return true
end

local function cmd_op(bufnr, fargs)
  local op = fargs[2]
  if op == "set-cell" then
    local row = tonumber(fargs[3])
    local col = tonumber(fargs[4])
    local value = table.concat(vim.list_slice(fargs, 5), " ")
    if not row or not col then
      return false, "usage: Cellmode op set-cell <row> <col> <value>"
    end
    return controller.set_cell(bufnr, row, col, value)
  elseif op == "insert-row" then
    local row = tonumber(fargs[3])
    local values = split_csv(table.concat(vim.list_slice(fargs, 4), " "))
    if not row then
      return false, "usage: Cellmode op insert-row <row> <value1,value2,...>"
    end
    return controller.insert_row(bufnr, row, values)
  elseif op == "delete-row" then
    local row = tonumber(fargs[3])
    if not row then
      return false, "usage: Cellmode op delete-row <row>"
    end
    return controller.delete_row(bufnr, row)
  end
  return false, "usage: Cellmode op <set-cell|insert-row|delete-row> ..."
end

local function cmd_status(bufnr)
  local session = session_store.get(bufnr)
  if not session then
    messages.info("no active session")
    return true
  end
  local layout = cell_layout.get(bufnr)
  local rec_count = layout and #layout.records or 0
  local col_count = layout and #(layout.widths or {}) or 0
  local visible = session.overlay_visible ~= false
  messages.info(string.format(
    "format=%s records=%d columns=%d overlay=%s",
    session.format,
    rec_count,
    col_count,
    visible and "on" or "off"
  ))
  return true
end

local function cmd_toggle(bufnr)
  return controller.toggle_overlay(bufnr)
end

local function cmd_save(bufnr, fargs)
  local _ = fargs
  vim.api.nvim_buf_call(bufnr, function()
    vim.cmd("write")
  end)
  return true
end

function M.exec(opts)
  local fargs = opts.fargs
  local action = fargs[1]
  local bufnr = api.nvim_get_current_buf()
  if not action then
    return false, "usage: Cellmode <open|op|toggle|status|save> ..."
  end
  if action == "open" then
    return cmd_open(bufnr, fargs)
  elseif action == "op" then
    return cmd_op(bufnr, fargs)
  elseif action == "toggle" then
    return cmd_toggle(bufnr)
  elseif action == "status" then
    return cmd_status(bufnr)
  elseif action == "save" then
    return cmd_save(bufnr, fargs)
  end
  return false, "unknown action: " .. action
end

function M.setup()
  pcall(api.nvim_del_user_command, runtime_config.command)
  api.nvim_create_user_command(runtime_config.command, function(opts)
    local ok, message = M.exec(opts)
    if not ok then
      messages.error(message)
    end
  end, {
    nargs = "*",
    complete = function()
      return { "open", "op", "toggle", "status", "save" }
    end,
  })
end

return M
