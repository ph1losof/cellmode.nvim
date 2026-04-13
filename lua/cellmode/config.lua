local M = {}

local defaults = {
  adapters = {},
  command = "Cellmode",
  marks = {
    pipe = "│",
    pipec = "┊",
    padding = "⠀",
    lf = "↲",
    tab = "⇥",
  },
}

local function assign(cfg)
  M.adapters = cfg.adapters
  M.command = cfg.command
  M.marks = cfg.marks
end

function M.setup(opts)
  local merged = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  assign(merged)
end

M.setup()

return M
