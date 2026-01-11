local M = {}

local uv = vim.loop
local api = vim.api
local fn = vim.fn

local util = require("watch.util")
local watch = require("watch.watch")

M.register_create = function()
  api.nvim_create_user_command("WatchCreate", function()
    local command = fn.input("Command: ", "", "shellcmd")
    if command == "" then
      util.notify("Aborted.", vim.log.levels.INFO)
      return
    end

    local name = fn.input("Output file: ", fn.getcwd() .. "/", "file")
    if name == "" then
      util.notify("Aborted.", vim.log.levels.INFO)
      return
    end

    if not watch.config.file.overwrite and uv.fs_stat(name) then
      local res = fn.input("File exists. Overwrite it? (y/n): "):sub(1, 1)
      if res == "n" or res == "N" then
        return
      end
    end

    local pattern = fn.input("Pattern: ")
    if pattern == "" then
      util.notify("Aborted.", vim.log.levels.INFO)
      return
    end

    watch.create_record(name, command, pattern)

    -- run-on-create
    if watch.config.run_on_create then watch.execute(name) end

    -- augroup
    local augroup = watch.get_augroup_file(name)
    api.nvim_create_augroup(augroup, { clear = true })

    api.nvim_create_autocmd("BufWritePost", {
      group = augroup,
      pattern = pattern,
      callback = function()
        watch.execute(name)
      end
    })

    -- save watch filename in register
    if watch.config.register.save_watch_path then
      local reg_cmd = "" ..
          ":redir @" .. watch.config.register.reg .. "\n" ..
          ":echon '" .. name .. "'\n" ..
          ":redir end"
      vim.cmd(":echo '' | redraw") -- clear commandline
      vim.cmd(reg_cmd)
    end
  end, {})
end

M.register_list = function()
  api.nvim_create_user_command("WatchList", function()
    print(vim.inspect(watch.data))
  end, {})
end

M.register_delete = function()
  api.nvim_create_user_command("WatchDelete", function()
    vim.ui.select(vim.tbl_keys(watch.data), {
        prompt = "Select file:",
      },
      function(choice)
        if choice == nil then return end
        local name = choice
        local augroup = watch.get_augroup_file(name)
        if vim.tbl_contains(vim.tbl_keys(watch.data), name) then
          -- augroup
          api.nvim_del_augroup_by_name(augroup)

          watch.data[name] = nil

          -- file-remove
          if watch.config.file.remove and uv.fs_stat(name) then
            local bufnr = fn.bufnr(name)
            if bufnr ~= -1 then api.nvim_buf_delete(bufnr, {}) end
            uv.fs_unlink(name)
          end
        end
      end)
  end, { nargs = 0 })
end

M.register_leave = function()
  local augroup = watch.get_augroup_name("leave")

  api.nvim_create_augroup(augroup, { clear = true })

  api.nvim_create_autocmd("BufWritePost", {
    group = augroup,
    pattern = "*",
    callback = function()
      if watch.config.file.remove then
        for name, _ in pairs(watch.data) do
          if uv.fs_stat(name) then
            uv.fs_unlink(name)
          end
        end
      end
    end
  })
end

return M
