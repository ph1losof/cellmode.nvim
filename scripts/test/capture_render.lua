package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  "./?.lua",
  package.path,
}, ";")

local cellmode = require("cellmode")
local overlay = require("cellmode.view.overlay")
cellmode.setup({})

local file = vim.fn.getcwd() .. "/examples/sample.csv"
vim.cmd("edit " .. vim.fn.fnameescape(file))
local bufnr = vim.api.nvim_get_current_buf()
vim.wait(500)

local ns = overlay.namespace()
local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

-- Collect extmarks per row: conceal ranges and inline virt_text insertions.
local conceals = {}   -- row0 -> list of {start_col0, end_col0, text}
local inlines = {}    -- row0 -> list of {col0, text}
local eols = {}       -- row0 -> appended text (eol virt_text)

local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { -1, -1 }, { details = true })
for _, m in ipairs(marks) do
  local row0, col0, d = m[2], m[3], m[4] or {}
  if d.conceal ~= nil then
    conceals[row0] = conceals[row0] or {}
    table.insert(conceals[row0], { col0, d.end_col or col0, d.conceal })
  end
  if d.virt_text and d.virt_text_pos == "inline" then
    local s = ""
    for _, ch in ipairs(d.virt_text) do s = s .. ch[1] end
    inlines[row0] = inlines[row0] or {}
    table.insert(inlines[row0], { col0, s })
  end
  if d.virt_text and d.virt_text_pos == "eol" then
    local s = ""
    for _, ch in ipairs(d.virt_text) do s = s .. ch[1] end
    eols[row0] = (eols[row0] or "") .. " " .. s
  end
end

local function is_concealed(row0, byte_idx0)
  local cs = conceals[row0]
  if not cs then return false end
  for _, c in ipairs(cs) do
    if byte_idx0 >= c[1] and byte_idx0 < c[2] then return true end
  end
  return false
end

local function inline_at(row0, byte_idx0)
  local ins = inlines[row0]
  if not ins then return "" end
  local out = ""
  for _, it in ipairs(ins) do
    if it[1] == byte_idx0 then out = out .. it[2] end
  end
  return out
end

local out = {}
for i = 1, #lines do
  local row0 = i - 1
  local line = lines[i]
  local rendered = ""
  for b = 0, #line do
    rendered = rendered .. inline_at(row0, b)
    if b < #line and not is_concealed(row0, b) then
      rendered = rendered .. line:sub(b + 1, b + 1)
    end
  end
  rendered = rendered .. (eols[row0] or "")
  out[#out + 1] = string.format("%2d| %s", i, rendered)
end

io.stderr:write(table.concat(out, "\n") .. "\n")
vim.cmd("qa!")
