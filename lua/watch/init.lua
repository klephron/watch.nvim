local M = {}

local cmd = require("watch.cmd")

M.setup = function()
  cmd.register_create()
  cmd.register_delete()
  cmd.register_leave()
  cmd.register_list()
end

return M
