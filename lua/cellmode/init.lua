local config = require("cellmode.config")
local table_view = require("cellmode.ui.table_view")

local M = {}

M.config = config

M.model = {
  workbook = require("cellmode.model.workbook"),
}

M.adapter = {
  protocol = require("cellmode.adapter.protocol"),
  client = require("cellmode.adapter.client"),
  registry = require("cellmode.adapter.registry"),
  loader = require("cellmode.adapter.workbook_loader"),
}

M.engine = {
  transaction = require("cellmode.engine.transaction"),
}

M.render = {
  projector = require("cellmode.render.projector"),
}

M.runtime = {
  session_store = require("cellmode.runtime.session_store"),
  controller = require("cellmode.runtime.controller"),
  commands = require("cellmode.runtime.commands"),
  autocmd = require("cellmode.runtime.autocmd"),
  messages = require("cellmode.runtime.messages"),
  errors = require("cellmode.runtime.errors"),
  adapter_resolver = require("cellmode.runtime.adapter_resolver"),
  scheduler = require("cellmode.runtime.scheduler"),
}

M.ui = {
  table_view = table_view,
}

local function plugin_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  return source:gsub("/lua/cellmode/init.lua$", "")
end

local function adapter_script_path()
  return plugin_root() .. "/adapters/cellmode_tir_csv_adapter.py"
end

local function with_default_csv_adapters(adapters)
  local script = adapter_script_path()
  if adapters.csv == nil then
    adapters.csv = {
      command = { "python3", script },
    }
  end
  if adapters.tsv == nil then
    adapters.tsv = {
      command = { "python3", script, "--delimiter", "\t" },
    }
  end
end

function M.setup(opts)
  opts = opts or {}
  local adapters = type(opts.adapters) == "table" and vim.deepcopy(opts.adapters) or {}
  with_default_csv_adapters(adapters)
  local merged = vim.tbl_deep_extend("force", {}, opts, {
    adapters = adapters,
    command = opts.command or "Cellmode",
  })
  config.setup(merged)
  table_view.setup()
  M.runtime.commands.setup()
  M.runtime.autocmd.setup()
  vim.g.cellmode_initialized = true
end

return M
