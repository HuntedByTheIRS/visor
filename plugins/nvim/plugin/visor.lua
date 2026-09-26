-- Commands and the filetype hook.
--
-- Loading this file starts no server. The filetype event is what starts one, so
-- an editor with no V buffers open never pays for a process, and
-- setup({ autostart = false }) turns the automatic start off without losing the
-- commands.
local config = require('visor.config')

local function visor()
  return require('visor')
end

local commands = {
  {
    name = 'VisorStart',
    desc = 'Start the visor server for this buffer',
    run = function()
      local client = visor().start()
      if not client then
        vim.notify('visor: no client attached to this buffer', vim.log.levels.WARN)
      end
    end,
  },
  {
    name = 'VisorStop',
    desc = 'Stop every visor client',
    run = function()
      local stopped = visor().stop()
      vim.notify(string.format('visor: stopped %d client(s)', stopped))
    end,
  },
  {
    name = 'VisorRestart',
    desc = 'Stop every visor client and start one for this buffer',
    run = function()
      visor().stop()
      visor().start()
    end,
  },
  {
    name = 'VisorFormat',
    desc = 'Format this buffer through the server',
    run = function()
      require('visor.format').format_buffer()
    end,
  },
  {
    name = 'VisorInfo',
    desc = 'Print what the visor plugin is connected to',
    run = function()
      print(table.concat(visor().info(), '\n'))
    end,
  },
}

for _, command in ipairs(commands) do
  vim.api.nvim_create_user_command(command.name, command.run, { desc = command.desc })
end

local group = vim.api.nvim_create_augroup('visor', { clear = true })

vim.api.nvim_create_autocmd('FileType', {
  group = group,
  pattern = 'v',
  callback = function(args)
    if config.options.autostart then
      visor().start(args.buf)
    end
  end,
})

-- The save hook is registered for every buffer and decides per buffer whether to
-- format. Registering it per filetype would miss a buffer whose filetype was set
-- after the plugin loaded, and the check inside is cheap.
vim.api.nvim_create_autocmd('BufWritePre', {
  group = group,
  callback = function(args)
    require('visor.format').on_save(args.buf)
  end,
})
