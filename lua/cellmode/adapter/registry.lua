local config = require("cellmode.config")

local M = {}

local function normalize_command(item)
  if type(item) == "string" then
    return { item }
  end
  if type(item) == "table" then
    return vim.deepcopy(item)
  end
  return nil
end

function M.get(format)
  if type(format) ~= "string" or format == "" then
    return nil, "format is required"
  end
  local adapter = config.adapters[format]
  if not adapter then
    return nil, "adapter is not configured for format: " .. format
  end
  local command = normalize_command(adapter.command or adapter)
  if not command or #command == 0 then
    return nil, "adapter command is invalid for format: " .. format
  end
  return command
end

return M
