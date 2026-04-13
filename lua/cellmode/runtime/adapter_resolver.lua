local registry = require("cellmode.adapter.registry")

local M = {}

local function get_format(bufnr)
  local ft = vim.bo[bufnr].filetype
  if type(ft) == "string" and ft ~= "" then
    return ft
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  return path:match("^.+%.([^.]+)$")
end

function M.from_buffer(bufnr)
  local format = get_format(bufnr)
  local command, err = registry.get(format)
  if not command then
    return nil, err
  end
  return {
    format = format,
    command = command,
    path = vim.api.nvim_buf_get_name(bufnr),
  }
end

function M.from_open_args(path, format, adapter_argv)
  local command
  if adapter_argv and #adapter_argv > 0 then
    command = adapter_argv
  else
    local err
    command, err = registry.get(format)
    if not command then
      return nil, err
    end
  end
  if type(command) ~= "table" then
    return nil, "adapter command is invalid"
  end
  return {
    format = format,
    command = command,
    path = path,
  }
end

return M
