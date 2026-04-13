local client = require("cellmode.adapter.client")
local protocol = require("cellmode.adapter.protocol")

local M = {}

function M.open(command, path, format)
  local caps, cap_err = client.capabilities(command)
  if not caps then
    return nil, cap_err
  end

  local opened, open_err = client.request(command, "open", {
    path = path,
    format = format,
  })
  if not opened then
    return nil, open_err
  end

  if not protocol.supports_method(caps, "read_workbook") then
    return nil, "adapter is missing required method: read_workbook"
  end

  local workbook, wb_err = client.request(command, "read_workbook", {
    workbook_id = opened.workbook_id,
  })
  if not workbook then
    return nil, wb_err
  end
  workbook.id = workbook.id or opened.workbook_id
  workbook.format = workbook.format or format

  return {
    workbook = workbook,
    adapter = {
      command = command,
      workbook_id = opened.workbook_id,
      capabilities = caps,
    },
  }
end

return M
