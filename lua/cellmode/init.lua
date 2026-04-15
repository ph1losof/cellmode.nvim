local config = require("cellmode.config")
local overlay = require("cellmode.view.overlay")

local M = {}

M.config = config

M.codec = {
  csv_parser = require("cellmode.codec.csv_parser"),
}

M.view = {
  cell_layout = require("cellmode.view.cell_layout"),
  overlay = overlay,
  sticky_header = require("cellmode.view.sticky_header"),
}

M.runtime = {
  session_store = require("cellmode.runtime.session_store"),
  controller = require("cellmode.runtime.controller"),
  commands = require("cellmode.runtime.commands"),
  autocmd = require("cellmode.runtime.autocmd"),
  messages = require("cellmode.runtime.messages"),
  errors = require("cellmode.runtime.errors"),
  scheduler = require("cellmode.runtime.scheduler"),
  auto_quote = require("cellmode.runtime.auto_quote"),
  keymaps = require("cellmode.runtime.keymaps"),
}

function M.setup(opts)
  opts = opts or {}
  config.setup(opts)
  overlay.setup()
  M.runtime.commands.setup()
  M.runtime.autocmd.setup()
  vim.g.cellmode_initialized = true
end

return M
