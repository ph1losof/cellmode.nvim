local config = require("cellmode.config")

local M = {}

function M.encode(cell)
  cell = cell:gsub("\n", config.marks.lf)
  cell = cell:gsub("\t", config.marks.tab)
  return cell
end

function M.decode(cell)
  cell = cell:gsub(vim.pesc(config.marks.lf), "\n")
  cell = cell:gsub(vim.pesc(config.marks.tab), "\t")
  return cell
end

function M.strip_padding(cell)
  local padding = vim.pesc(config.marks.padding)
  return (cell:gsub(padding, ""))
end

return M
