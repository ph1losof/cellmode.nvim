local M = {}

M.REQUIRED_METHODS = {
  "open",
  "read_workbook",
  "write_workbook",
}

local function decode_json(line)
  local ok, value = pcall(vim.json.decode, line)
  if not ok then
    return nil, "invalid json"
  end
  if type(value) ~= "table" then
    return nil, "message is not an object"
  end
  return value
end

function M.new_request(id, method, params)
  return {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }
end

function M.new_response(id, result, err)
  local response = {
    jsonrpc = "2.0",
    id = id,
  }
  if err then
    response.error = err
  else
    response.result = result
  end
  return response
end

function M.encode(message)
  local ok, line = pcall(vim.json.encode, message)
  if not ok then
    error("protocol encode failed")
  end
  return line
end

function M.decode(line)
  return decode_json(line)
end

function M.decode_first_line(stdout)
  local lines = vim.split(stdout or "", "\n", { plain = true, trimempty = true })
  if #lines == 0 then
    return nil, "adapter did not return a response"
  end
  return decode_json(lines[1])
end

function M.validate_capabilities(capabilities)
  if type(capabilities) ~= "table" then
    return false, "capabilities must be an object"
  end
  if type(capabilities.methods) ~= "table" then
    return false, "capabilities.methods must be an object"
  end

  for _, method in ipairs(M.REQUIRED_METHODS) do
    if capabilities.methods[method] ~= true then
      return false, "missing required method: " .. method
    end
  end
  return true
end

function M.supports_method(capabilities, method)
  return type(capabilities) == "table"
    and type(capabilities.methods) == "table"
    and capabilities.methods[method] == true
end

return M
