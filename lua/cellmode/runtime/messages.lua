local M = {}

local PREFIX = "cellmode: "

function M.error(message)
  vim.notify(PREFIX .. tostring(message), vim.log.levels.ERROR)
end

function M.info(message)
  vim.notify(PREFIX .. tostring(message), vim.log.levels.INFO)
end

return M
