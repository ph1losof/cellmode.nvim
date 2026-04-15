local runtime_config = require("cellmode.config")
local cell_layout = require("cellmode.view.cell_layout")

local M = {}

local api = vim.api

local MAPPED_KEYS = { "o", "O" }

local function column_count(layout, irec)
  local n = layout.widths and #layout.widths or 0
  if n > 0 then
    return n
  end
  local record = layout.records[irec]
  if record and record.fields then
    return #record.fields
  end
  return 1
end

local function resolve_target(layout, direction)
  local total = #layout.records
  if total == 0 then
    return 1, 1
  end
  local cursor_row = api.nvim_win_get_cursor(0)[1]
  local irec = layout.record_by_row and layout.record_by_row[cursor_row]
  if not irec then
    if cursor_row <= layout.records[1].buf_row_start then
      irec = 1
    else
      irec = total
    end
  end
  local target = direction == "below" and irec + 1 or irec
  return target, irec
end

local function insert_row_relative(bufnr, direction)
  local controller = require("cellmode.runtime.controller")
  local layout = cell_layout.get(bufnr)
  if not layout then
    return
  end
  local target, irec = resolve_target(layout, direction)
  local ncols = column_count(layout, irec)
  local values = {}
  for i = 1, ncols do
    values[i] = ""
  end
  local ok, err = controller.insert_row(bufnr, target, values)
  if not ok then
    return ok, err
  end
  local new_layout = cell_layout.get(bufnr)
  local new_record = new_layout and new_layout.records[target]
  if new_record then
    api.nvim_win_set_cursor(0, { new_record.buf_row_start, 0 })
  end
  vim.cmd("startinsert")
end

function M.attach(bufnr)
  if not runtime_config.remap then
    return
  end
  if vim.b[bufnr].cellmode_keymaps_attached then
    return
  end
  vim.keymap.set("n", "o", function()
    insert_row_relative(bufnr, "below")
  end, { buffer = bufnr, silent = true, desc = "cellmode: insert row below" })
  vim.keymap.set("n", "O", function()
    insert_row_relative(bufnr, "above")
  end, { buffer = bufnr, silent = true, desc = "cellmode: insert row above" })
  vim.b[bufnr].cellmode_keymaps_attached = true
end

function M.detach(bufnr)
  if not vim.b[bufnr].cellmode_keymaps_attached then
    return
  end
  for _, lhs in ipairs(MAPPED_KEYS) do
    pcall(api.nvim_buf_del_keymap, bufnr, "n", lhs)
  end
  vim.b[bufnr].cellmode_keymaps_attached = false
end

return M
