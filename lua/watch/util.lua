local uv = vim.loop
local fn = vim.fn
local api = vim.api

local M = {}

---@param msg string
---@param level any
---@return nil
M.notify = function(msg, level)
  return vim.notify(msg, level, { title = "watch" })
end

---@param name string
M.create_file_if_not_exist = function(name)
  if not uv.fs_stat(name) then
    local ok, fd = pcall(uv.fs_open, name, "w", 420)
    if not ok then
      M.notify("Couldn't open file " .. name, vim.log.levels.WARN)
      return
    end
    uv.fs_close(fd)
  end
end

---@param name string
---@param is_buflisted boolean
---@return number
M.open_buffer = function(name, is_buflisted)
  local bufnr = fn.bufnr(name)
  if bufnr == -1 then
    bufnr = api.nvim_create_buf(is_buflisted, true)
    api.nvim_buf_set_name(bufnr, name)
  end
  api.nvim_buf_set_option(bufnr, "buftype", "")
  api.nvim_buf_set_option(bufnr, "modifiable", true)
  return bufnr
end

---@param t1 table
---@param t2 table
M.tbl_equals = function(t1, t2)
  if t1 == t2 then return true end
  for k, v in pairs(t1) do
    if v ~= t2[k] then return false end
  end
  return true
end

---Trim string
---@param str string
M.trim = function(str)
  return str:gsub("^%s*(.-)%s*$", "%1")
end

return M
