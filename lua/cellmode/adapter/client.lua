local protocol = require("cellmode.adapter.protocol")

local M = {}

local processes = {}

local function ensure_command(command)
  if type(command) ~= "table" or #command == 0 then
    error("adapter command must be a non-empty argv table")
  end
end

local function command_key(command)
  return table.concat(command, "\0")
end

local function ensure_process(command)
  local key = command_key(command)
  local process = processes[key]
  if process and process.jobid and process.jobid > 0 then
    return process
  end

  process = {
    command = vim.deepcopy(command),
    pending = {},
    stderr = {},
    stdout_remainder = "",
    stderr_remainder = "",
  }

  local function reject_all(message)
    for _, req in pairs(process.pending) do
      req.error = message
      req.done = true
    end
    process.pending = {}
  end

  process.jobid = vim.fn.jobstart(command, {
    rpc = false,
    pty = false,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      local chunks = vim.deepcopy(data or {})
      if #chunks == 0 then
        return
      end
      if process.stdout_remainder ~= "" then
        chunks[1] = process.stdout_remainder .. chunks[1]
        process.stdout_remainder = ""
      end
      if chunks[#chunks] ~= "" then
        process.stdout_remainder = chunks[#chunks]
        chunks[#chunks] = nil
      end
      for _, line in ipairs(chunks) do
        if line ~= "" then
          local message, decode_err = protocol.decode(line)
          if not message then
            reject_all("adapter response decode failed: " .. tostring(decode_err))
            return
          end
          local id = message.id
          local req = process.pending[id]
          if req then
            req.message = message
            req.done = true
            process.pending[id] = nil
          end
        end
      end
    end,
    on_stderr = function(_, data)
      local chunks = vim.deepcopy(data or {})
      if #chunks == 0 then
        return
      end
      if process.stderr_remainder ~= "" then
        chunks[1] = process.stderr_remainder .. chunks[1]
        process.stderr_remainder = ""
      end
      if chunks[#chunks] ~= "" then
        process.stderr_remainder = chunks[#chunks]
        chunks[#chunks] = nil
      end
      for _, line in ipairs(chunks) do
        if line ~= "" then
          process.stderr[#process.stderr + 1] = line
        end
      end
    end,
    on_exit = function(_, code)
      if process.stderr_remainder ~= "" then
        process.stderr[#process.stderr + 1] = process.stderr_remainder
        process.stderr_remainder = ""
      end
      local stderr = table.concat(process.stderr, "\n")
      if stderr == "" then
        stderr = "(no stderr output)"
      end
      reject_all(string.format("adapter process exited (code=%s): %s", tostring(code), stderr))
      processes[key] = nil
    end,
  })

  if process.jobid <= 0 then
    error("failed to start adapter process")
  end

  processes[key] = process
  return process
end

local function ensure_response_shape(message)
  if type(message) ~= "table" then
    return false, "adapter response is not an object"
  end
  if message.jsonrpc ~= "2.0" then
    return false, "adapter response must use jsonrpc=2.0"
  end
  if message.error then
    local err = message.error.message or "adapter returned an unknown error"
    return false, err
  end
  return true
end

function M.request(command, method, params, opts)
  opts = opts or {}
  ensure_command(command)
  local process = ensure_process(command)
  local id = opts.request_id or tostring(vim.loop.hrtime())
  local request = protocol.new_request(id, method, params)
  local request_line = protocol.encode(request)

  local pending = { done = false }
  process.pending[id] = pending

  vim.fn.chansend(process.jobid, request_line .. "\n")

  local timeout_ms = opts.timeout_ms or 20000
  local completed = vim.wait(timeout_ms, function()
    return pending.done == true
  end, 10)
  if not completed then
    process.pending[id] = nil
    return nil, "adapter request timed out"
  end

  if pending.error then
    return nil, pending.error
  end

  local message = pending.message
  local ok, shape_err = ensure_response_shape(message)
  if not ok then
    return nil, shape_err
  end
  if message.id ~= id then
    return nil, "adapter response id mismatch"
  end
  return message.result
end

function M.capabilities(command, opts)
  local result, err = M.request(command, "capabilities", {}, opts)
  if not result then
    return nil, err
  end
  local ok, validation_err = protocol.validate_capabilities(result)
  if not ok then
    return nil, validation_err
  end
  return result
end

function M.shutdown_all()
  for _, process in pairs(processes) do
    if process.jobid and process.jobid > 0 then
      pcall(vim.fn.jobstop, process.jobid)
    end
  end
  processes = {}
end

return M
