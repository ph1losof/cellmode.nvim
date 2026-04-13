local M = {}

function M.unwrap(err)
  if type(err) == "table" and err.message then
    return err.message
  end
  return tostring(err)
end

return M
