local controller = require("cellmode.runtime.controller")
local session_store = require("cellmode.runtime.session_store")
local resolver = require("cellmode.runtime.adapter_resolver")
local runtime_autocmd = require("cellmode.runtime.autocmd")
local runtime_config = require("cellmode.config")
local messages = require("cellmode.runtime.messages")
local errors = require("cellmode.runtime.errors")

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
    return false, "usage: Cellmode open <path> <format> [--adapter <cmd> [args...]]"
  end

  local adapter_argv
  if fargs[4] == "--adapter" then
    adapter_argv = vim.list_slice(fargs, 5)
    if #adapter_argv == 0 then
      return false, "usage: Cellmode open <path> <format> --adapter <cmd> [args...]"
    end
  elseif fargs[4] and fargs[4] ~= "" then
    adapter_argv = { fargs[4] }
  end

  local spec, spec_err = resolver.from_open_args(path, format, adapter_argv)
  if not spec then
    return false, spec_err
  end

  local ok, open_err = controller.open_from_adapter(bufnr, spec.command, spec.path, spec.format)
  if not ok then
    return false, open_err
  end
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].swapfile = false
  runtime_autocmd.attach_write_cmd(bufnr)
  runtime_autocmd.attach_buffer_tracking(bufnr)
  return true
end

local function cmd_op(bufnr, fargs)
  local op = fargs[2]
  local operations
  if op == "set-cell" then
    local segment = tonumber(fargs[3])
    local row = tonumber(fargs[4])
    local col = tonumber(fargs[5])
    local value = table.concat(vim.list_slice(fargs, 6), " ")
    if not segment or not row or not col then
      return false, "usage: Cellmode op set-cell <segment> <row> <col> <value>"
    end
    operations = {
      { op = "set_cell", segment = segment, row = row, col = col, value = value },
    }
  elseif op == "insert-row" then
    local segment = tonumber(fargs[3])
    local row = tonumber(fargs[4])
    local values = split_csv(table.concat(vim.list_slice(fargs, 5), " "))
    if not segment or not row then
      return false, "usage: Cellmode op insert-row <segment> <row> <value1,value2,...>"
    end
    operations = {
      { op = "insert_row", segment = segment, row = row, values = values },
    }
  elseif op == "delete-row" then
    local segment = tonumber(fargs[3])
    local row = tonumber(fargs[4])
    if not segment or not row then
      return false, "usage: Cellmode op delete-row <segment> <row>"
    end
    operations = {
      { op = "delete_row", segment = segment, row = row },
    }
  else
    return false, "usage: Cellmode op <set-cell|insert-row|delete-row> ..."
  end

  local ok, op_err = controller.apply_operations(bufnr, operations)
  if not ok then
    return false, errors.unwrap(op_err)
  end
  return true
end

local function cmd_save(bufnr, fargs)
  local path = fargs[2] or api.nvim_buf_get_name(bufnr)
  local format = fargs[3]
  if not path or path == "" then
    return false, "usage: Cellmode save <path> [format]"
  end
  local ok, save_err = controller.save_to_adapter(bufnr, path, format)
  if not ok then
    return false, save_err
  end
  return true
end

local function cmd_status(bufnr)
  local session = session_store.get(bufnr)
  if not session then
    messages.info("no active session")
    return true
  end
  local sheet = session.workbook.sheets[session.workbook.active_sheet]
  local text = string.format(
    "workbook=%s format=%s active_sheet=%s",
    session.workbook.id,
    session.workbook.format,
    sheet and sheet.name or "(none)"
  )
  messages.info(text)
  return true
end

function M.exec(opts)
  local fargs = opts.fargs
  local action = fargs[1]
  local bufnr = api.nvim_get_current_buf()
  if not action then
    return false, "usage: Cellmode <open|op|save|status> ..."
  end

  if action == "open" then
    return cmd_open(bufnr, fargs)
  elseif action == "op" then
    return cmd_op(bufnr, fargs)
  elseif action == "save" then
    return cmd_save(bufnr, fargs)
  elseif action == "status" then
    return cmd_status(bufnr)
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
      return { "open", "op", "save", "status" }
    end,
  })
end

return M
