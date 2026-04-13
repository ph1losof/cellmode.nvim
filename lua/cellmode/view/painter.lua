local config = require("cellmode.config")
local viewport = require("cellmode.view.viewport")
local cache = require("cellmode.view.cache")

local M = {}

local ns = vim.api.nvim_create_namespace("cellmode_table_view")
local hl_exists_cache = {}

local function pick_highlight_link(targets)
  for index = 1, #targets do
    local target = targets[index]
    local known = hl_exists_cache[target]
    if known == true then
      return target
    end
    if known == nil then
      local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = target })
      local exists = ok and hl and next(hl) ~= nil
      hl_exists_cache[target] = exists and true or false
      if exists then
        return target
      end
    end
  end

  for index = 1, #targets do
    local target = targets[index]
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = target })
    if ok and hl and next(hl) ~= nil then
      hl_exists_cache[target] = true
      return target
    end
  end

  return "Normal"
end

local function add_occurrences(bufnr, row0, line, token, hl)
  if token == "" then
    return
  end
  local from = 1
  while true do
    local s = line:find(token, from, true)
    if not s then
      break
    end
    local e = s + #token - 1
    vim.api.nvim_buf_add_highlight(bufnr, ns, hl, row0, s - 1, e)
    from = e + 1
  end
end

local function all_occurrences(line, token)
  local out = {}
  local from = 1
  while true do
    local s = line:find(token, from, true)
    if not s then
      break
    end
    out[#out + 1] = s
    from = s + #token
  end
  return out
end

local function apply_row_highlights(bufnr, row0, line, marks)
  add_occurrences(bufnr, row0, line, marks.padding, "CellmodePadding")
  add_occurrences(bufnr, row0, line, marks.lf, "CellmodeSpecialChar")
  add_occurrences(bufnr, row0, line, marks.tab, "CellmodeSpecialChar")
  add_occurrences(bufnr, row0, line, marks.pipec, "CellmodePipe")

  local pipes = all_occurrences(line, marks.pipe)
  if #pipes == 0 then
    return
  end

  add_occurrences(bufnr, row0, line, marks.pipe, "CellmodePipe")
  for index = 1, #pipes - 1 do
    local inner_start = pipes[index] - 1 + #marks.pipe
    local inner_end = pipes[index + 1] - 1
    if inner_start < inner_end then
      vim.api.nvim_buf_add_highlight(bufnr, ns, "CellmodeHbar", row0, inner_start, inner_end)
    end
  end
end

local function paint_range(bufnr, first, last, marks)
  if first > last then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
  for row = 1, #lines do
    apply_row_highlights(bufnr, first + row - 2, lines[row], marks)
  end
end

function M.setup()
  hl_exists_cache = {}
  vim.api.nvim_set_hl(0, "CellmodePadding", {})
  local target = pick_highlight_link({ "@punctuation.special.markdown", "Delimiter", "Special" })
  local special = vim.api.nvim_get_hl(0, { name = target })
  vim.api.nvim_set_hl(0, "CellmodePipe", { link = target })
  vim.api.nvim_set_hl(0, "CellmodeHbar", {
    underline = true,
    sp = special.fg,
    nocombine = true,
  })
  vim.api.nvim_set_hl(0, "CellmodeSpecialChar", { link = "NonText" })
end

function M.apply(winid, opts)
  winid = winid or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then
    return
  end

  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  local cache_key = viewport.bucketed_key(winid, tick)
  local first, last = viewport.expanded_range(winid, line_count)
  local marks = config.marks
  local prev = cache.get(bufnr, winid)
  local changed_ranges = opts and opts.changed_ranges or nil

  if prev and prev.key == cache_key and first >= prev.first and last <= prev.last then
    return
  end

  if (not prev) or prev.tick ~= tick then
    if prev and changed_ranges and #changed_ranges > 0 then
      for _, range in ipairs(changed_ranges) do
        local start_line = math.max(first, range.start_line or first)
        local end_line = math.min(last, range.end_line or last)
        if start_line <= end_line then
          vim.api.nvim_buf_clear_namespace(bufnr, ns, start_line - 1, end_line)
          paint_range(bufnr, start_line, end_line, marks)
        end
      end
      if first > prev.first then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, prev.first - 1, first - 1)
      elseif first < prev.first then
        paint_range(bufnr, first, prev.first - 1, marks)
      end
      if last < prev.last then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, last, prev.last)
      elseif last > prev.last then
        paint_range(bufnr, prev.last + 1, last, marks)
      end
    else
      if prev then
        vim.api.nvim_buf_clear_namespace(bufnr, ns, prev.first - 1, prev.last)
      end
      paint_range(bufnr, first, last, marks)
    end
    cache.set(bufnr, winid, { tick = tick, key = cache_key, first = first, last = last })
    return
  end

  if first > prev.first then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, prev.first - 1, first - 1)
  elseif first < prev.first then
    paint_range(bufnr, first, prev.first - 1, marks)
  end

  if last < prev.last then
    vim.api.nvim_buf_clear_namespace(bufnr, ns, last, prev.last)
  elseif last > prev.last then
    paint_range(bufnr, prev.last + 1, last, marks)
  end

  cache.set(bufnr, winid, { tick = tick, key = cache_key, first = first, last = last })
end

function M.clear(winid)
  winid = winid or vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  cache.clear(bufnr, winid)
end

function M.clear_buffer(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  cache.clear(bufnr)
end

return M
