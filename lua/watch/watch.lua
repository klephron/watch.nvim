local M = {}

local api = vim.api
local fn = vim.fn

local util = require("watch.util")

M.defaults = {
  file = {
    remove = true,
    overwrite = true,
  },
  run_on_create = true,
  decorator = { -- example: treat stdout as terminal
    enabled = true,
    left = 'script -qe -c "',
    right = '" /dev/null',
  },
  is_buflisted = false,
  register = {
    save_watch_path = true,
    reg = "+",
  },
  command = {
    stdout_buffered = true,
    stderr_buffered = true,
    split = {
      enabled = true,
      -- NOTE: it's just used to split so shell behaviur won't work
      pattern = { "&&", ";" },
    },
    exit_on_error = true,
    save_after_each = true,
    trim = true,
  }
}

M.config = M.defaults

---@class WatchTable
---@field command_splitted string[]
---@field command string
---@field pattern string

---@type table<string, WatchTable>
M.data = {}

---Append data to file from stdin/stderr
---@param data table
---@param stream string
---@param bufnr number
M.append_data = function(bufnr, _, data, stream)
  if data and not util.tbl_equals(data, { "" }) then
    api.nvim_buf_set_lines(bufnr, -1, -1, false,
      { "[" .. string.upper(stream) .. "]" })
    api.nvim_buf_set_lines(bufnr, -1, -1, false, data)
  end
end

---@param name string
M.get_augroup_name = function(name)
  return "watch." .. name
end

---@param name string
M.get_augroup_file = function(name)
  return "watch#" .. name
end

---Apply decorator
---@param str string
---@return string
M.apply_decorator = function(str)
  return M.config.decorator.left .. str .. M.config.decorator.right
end

---Execute command and write to stdout when all jobs will finish.
---@param name string
M.execute_single = function(name)
  util.create_file_if_not_exist(name)
  local bufnr = util.open_buffer(name, M.config.is_buflisted)
  local command = M.data[name].command
  -- fn
  local function with_buffer(chan_id, data, stream)
    M.append_data(bufnr, chan_id, data, stream)
  end

  -- execute cmd and print output to the file, after that write file
  api.nvim_buf_set_lines(bufnr, 0, -1, false, { "[FNAME] " .. name, "" })
  api.nvim_buf_set_lines(bufnr, -1, -1, false, { "[COMMAND] " .. command })
  fn.jobstart(command, {
    stdout_buffered = M.config.command.stdout_buffered,
    stderr_buffered = M.config.command.stderr_buffered,
    on_stdout = with_buffer,
    on_stderr = with_buffer,
    on_exit = function()
      api.nvim_buf_call(bufnr, function() vim.cmd("silent w!") end)
    end
  })
end


---Execute multiple commands at once, more customizable, more options, prefered.
---@param name string
M.execute_multiple = function(name)
  util.create_file_if_not_exist(name)
  local bufnr = util.open_buffer(name, M.config.is_buflisted)
  local commands = M.data[name].command_splitted
  local co = coroutine.create(function()
    for _, v in ipairs(commands) do
      coroutine.yield(v)
    end
  end)
  -- fn
  local function with_buffer(chan_id, data, stream)
    util.append_data(bufnr, chan_id, data, stream)
  end

  local function recursive()
    local ok, command = coroutine.resume(co)
    if not ok or command == nil then return end
    local job_id = nil
    api.nvim_buf_set_lines(bufnr, -2, -1, false, { "[COMMAND] " .. command })
    job_id = fn.jobstart(command, {
      stdout_buffered = M.config.command.stdout_buffered,
      stderr_buffered = M.config.command.stderr_buffered,
      on_stdout = with_buffer,
      on_stderr = with_buffer,
      on_exit = function(_, exit, _)
        if M.config.command.save_after_each then
          api.nvim_buf_call(bufnr, function() vim.cmd("silent w!") end)
        end
        if M.config.command.exit_on_error and job_id <= 0 or exit ~= 0 then
          return
        else
          recursive()
        end
      end
    })
  end

  -- api.nvim_buf_set_lines(bufnr, 0, -1, false, { "[FNAME] " .. name, "", "" })
  api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
  recursive()
  if not M.config.command.save_after_each then
    api.nvim_buf_call(bufnr, function() vim.cmd("silent w!") end)
  end
end

M.execute = function(name)
  if M.config.command.split.enabled then
    M.execute_multiple(name)
  else
    M.execute_single(name)
  end
end

---@param name string
---@param command string
---@param pattern string
M.create_record = function(name, command, pattern)
  -- save and override
  if vim.tbl_contains(vim.tbl_keys(M.data), name) then
    util.notify("Watcher " .. name .. " is overridden.", vim.log.levels.WARN)
  end
  -- split commands
  local command_list = { command }
  for _, p in pairs(M.config.command.split.pattern) do
    for i, c in ipairs(command_list) do
      command_list[i] = vim.split(c, p, { trimempty = true })
    end
    command_list = vim.tbl_flatten(command_list)
  end
  -- trim commands
  if M.config.command.trim then
    command = util.trim(command)
    for i, c in pairs(command_list) do
      command_list[i] = util.trim(c)
    end
  end
  -- decorator
  if M.config.decorator.enabled then
    for i, c in pairs(command_list) do
      command_list[i] = M.apply_decorator(c)
    end
    command = M.apply_decorator(command)
  end
  -- store
  M.data[name] = { command_splitted = command_list, command = command, pattern = pattern }
end


return M
