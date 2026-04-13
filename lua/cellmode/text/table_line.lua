local config = require("cellmode.config")

local M = {}

local function marks()
  return config.marks.pipe, config.marks.pipec
end

local function next_separator(line, from, pipen, pipec)
  local n_start = line:find(pipen, from, true)
  local c_start = line:find(pipec, from, true)

  if not n_start then
    if c_start then
      return c_start, #pipec
    end
    return nil, nil
  end

  if not c_start or n_start < c_start then
    return n_start, #pipen
  end

  return c_start, #pipec
end

function M.get_pipe_char(line)
  local pipen, pipec = marks()
  if type(line) ~= "string" then
    return nil
  end

  local has_normal = line:find(pipen, 1, true) ~= nil
  if has_normal then
    return pipen
  end

  local has_continue = line:find(pipec, 1, true) ~= nil
  if has_continue then
    return pipec
  end

  return nil
end

function M.get_cells(line)
  local pipen, pipec = marks()
  if type(line) ~= "string" then
    return nil
  end

  if not M.get_pipe_char(line) then
    return nil
  end

  local from = 1
  local to = #line

  if line:sub(1, #pipen) == pipen then
    from = from + #pipen
  elseif line:sub(1, #pipec) == pipec then
    from = from + #pipec
  end

  if to >= #pipen and line:sub(to - #pipen + 1, to) == pipen then
    to = to - #pipen
  elseif to >= #pipec and line:sub(to - #pipec + 1, to) == pipec then
    to = to - #pipec
  end

  if from > to then
    return { "" }
  end

  local cells = {}
  local cell_from = from

  while true do
    local sep_from, sep_len = next_separator(line, cell_from, pipen, pipec)
    if not sep_from or sep_from > to then
      cells[#cells + 1] = line:sub(cell_from, to)
      break
    end
    cells[#cells + 1] = line:sub(cell_from, sep_from - 1)
    cell_from = sep_from + sep_len
  end

  return cells
end

return M
