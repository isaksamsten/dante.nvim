local config = require("sia.config")
local utils = require("sia.utils")
local Conversation = require("sia.conversation").Conversation
local SplitStrategy = require("sia.strategy").SplitStrategy
local DiffStrategy = require("sia.strategy").DiffStrategy
local InsertStrategy = require("sia.strategy").InsertStrategy
-- local EditStrategy = require("sia.strategy").EditStrategy

local M = {}

function M.setup(options)
  config.setup(options)
  require("sia.markers").setup()
  require("sia.mappings").setup()

  vim.api.nvim_create_user_command("SiaAccept", function()
    require("sia.markers").accept(vim.api.nvim_get_current_buf())
  end, {})

  vim.api.nvim_create_user_command("SiaReject", function()
    require("sia.markers").reject(vim.api.nvim_get_current_buf())
  end, {})

  vim.api.nvim_create_user_command("SiaAdd", function(args)
    local split = SplitStrategy.by_buf()
    if #args.fargs == 0 then
      local files
      if split then
        files = split.files
      else
        files = utils.get_global_files()
      end
      print(table.concat(files, ", "))
    else
      local files = {}
      for _, arg in ipairs(args.fargs) do
        vim.list_extend(files, vim.fn.glob(arg, true, true))
      end

      if split then
        split:add_files(files)
      else
        utils.add_global_files(files)
      end
    end
    if split then
      print("Add files to %s", split.name)
    else
      print("Add files to the global list")
    end
  end, { nargs = "*", bar = true, complete = "file" })

  vim.api.nvim_create_user_command("SiaDelete", function(args)
    local split = SplitStrategy.by_buf()
    if split then
      split:remove_files(args.fargs)
    else
      utils.remove_global_files(args.fargs)
    end
  end, {
    nargs = "+",
    complete = function(arg_lead)
      local split = SplitStrategy.by_buf()
      local files
      if split then
        files = split.files
      else
        files = utils.get_global_files()
      end
      local matches = {}
      for _, file in ipairs(files) do
        if vim.fn.match(file, "^" .. vim.fn.escape(arg_lead, "\\")) >= 0 then
          table.insert(matches, file)
        end
      end
      return matches
    end,
  })

  vim.treesitter.language.register("markdown", "sia")

  local augroup = vim.api.nvim_create_augroup("SiaGroup", { clear = true })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = augroup,
    pattern = "*",
    callback = function(args)
      if vim.bo[args.buf].filetype == "sia" then
        SplitStrategy.remove(args.buf)
      end
    end,
  })
  if config.options.report_usage == true then
    vim.api.nvim_create_autocmd("User", {
      group = augroup,
      pattern = "SiaUsageReport",
      callback = function(args)
        local data = args.data
        if data then
          vim.notify("Total tokens: " .. data.total_tokens)
        end
      end,
    })
  end
end

--- @param action sia.config.Action
--- @param opts sia.ActionArgument
function M.main(action, opts)
  if vim.api.nvim_buf_is_valid(opts.buf) and vim.api.nvim_buf_is_loaded(opts.buf) then
    local strategy
    if vim.bo[opts.buf].filetype == "sia" then
      strategy = SplitStrategy.by_buf(opts.buf)
      if strategy then
        local last_instruction = action.instructions[#action.instructions] --[[@as sia.config.Instruction ]]
        strategy:add_instruction(last_instruction, opts)
      end
    else
      local conversation = Conversation:new(action, opts)
      if conversation.mode == "diff" then
        local options = vim.tbl_deep_extend("force", config.options.defaults.diff, action.diff or {})
        strategy = DiffStrategy:new(conversation, options)
      elseif conversation.mode == "insert" then
        local options = vim.tbl_deep_extend("force", config.options.defaults.insert, action.insert or {})
        strategy = InsertStrategy:new(conversation, options)
      else
        local options = vim.tbl_deep_extend("force", config.options.defaults.split, action.split or {})
        strategy = SplitStrategy:new(conversation, options)
      end
    end

    --- @cast strategy sia.Strategy
    require("sia.assistant").execute_strategy(strategy)
  end
end

return M
