local utils = require("tinker.utils")
local M = {}

---@class tinker.Options
---@field php_executable string: The php_executable that will be used to run the cmd
---@field cmd string: The cmd that will be used to run the tinker
---@field buffer_split_direction string: Window split direction: 'horizontal', 'vertical', or 'tab'
---@field results_split_direction string: Window split direction: 'horizontal', 'vertical', or 'tab'
---@field keymaps table<string, string>: Keymaps to use for tinker.nvim

---@type tinker.Options
local options = {
  php_executable = "php",
  cmd = "artisan tinker",
  keymaps = {
    run_tinker = "<leader>tr",
    create_scratch = "<leader>ts",
  },
  buffer_split_direction = "horizontal",
  results_split_direction = "vertical",
}

--- Setup the plugin
---@param opts tinker.Options
M.setup = function(opts)
  options = vim.tbl_deep_extend("force", options, opts or {})

  -- Setup global keymap for creating scratch buffer
  if options.keymaps.create_scratch then
    vim.keymap.set("n", options.keymaps.create_scratch, function()
      M.create_scratch_buffer()
    end, { desc = "Create PHP Tinker scratch buffer" })
  end
end

M.get_php_executable = function()
  return options.php_executable
end

M.result_buf = nil

local function create_split(split_direction)
  if split_direction == "vertical" then
    vim.cmd("vsplit")
  elseif split_direction == "horizontal" then
    vim.cmd("split")
  elseif split_direction == "tab" then
    vim.cmd("tabnew")
  else
    vim.cmd("split") -- default to horizontal
  end
end

local function create_buffer_split()
  create_split(options.buffer_split_direction)
end

local function create_results_split()
  create_split(options.results_split_direction)
end

local function get_scratch_file_path(project_root)
  local scratch_dir = project_root .. "/vendor/_tinker_nvim_ide"
  local scratch_file = scratch_dir .. "/scratch.php"
  vim.fn.mkdir(scratch_dir, "p")
  return scratch_file
end

local function create_initial_scratch_file(scratch_file)
  if vim.fn.filereadable(scratch_file) == 0 then
    local initial_content = { "<?php", "" }
    vim.fn.writefile(initial_content, scratch_file)
  end
end

local function setup_scratch_buffer_keymap(buf_id)
  vim.keymap.set("n", options.keymaps.run_tinker, M.run_tinker, {
    buffer = buf_id,
    desc = "Run PHP code in artisan tinker",
  })
end

local function handle_existing_buffer(existing_buf_id)
  local win_id = vim.fn.bufwinid(existing_buf_id)
  if win_id ~= -1 then
    vim.api.nvim_set_current_win(win_id)
    return existing_buf_id
  else
    create_buffer_split()
    vim.api.nvim_win_set_buf(0, existing_buf_id)
    setup_scratch_buffer_keymap(existing_buf_id)
    return existing_buf_id
  end
end

function M.create_scratch_buffer()
  local project_root = utils.find_laravel_project()
  if not project_root then
    vim.notify("Error: No Laravel project detected. Cannot create scratch buffer.", vim.log.levels.ERROR)
    return
  end

  local scratch_file = get_scratch_file_path(project_root)

  local existing_buf_id = vim.fn.bufnr(scratch_file)
  if existing_buf_id ~= -1 and vim.api.nvim_buf_is_valid(existing_buf_id) then
    return handle_existing_buffer(existing_buf_id)
  end

  create_initial_scratch_file(scratch_file)
  create_buffer_split()
  vim.cmd("edit " .. vim.fn.fnameescape(scratch_file))

  local buf_id = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("filetype", "php", { buf = buf_id })

  setup_scratch_buffer_keymap(buf_id)

  return buf_id
end

local function close_results_buf()
  if M.result_buf and vim.api.nvim_buf_is_valid(M.result_buf) then
    vim.api.nvim_buf_delete(M.result_buf, { force = true })
    M.result_buf = nil
  end
end

-- Create results buffer
local function reset_or_create_output_buf()
  close_results_buf()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("filetype", "text", { buf = buf })
  vim.api.nvim_buf_set_name(buf, "PHP Tinker Results")
  M.result_buf = buf

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    buffer = buf,
    callback = function()
      M.result_buf = nil
    end,
    once = true,
  })

  return buf
end

local function write_temp_file(content)
  local temp_file = vim.fn.tempname() .. ".php"
  local file = io.open(temp_file, "w")

  if not file then
    vim.notify("Could not create temporary file", vim.log.levels.ERROR)
    return nil
  end

  file:write(content)
  file:close()

  return temp_file
end

local function ensure_exit_statement(lines)
  local has_exit = false
  for _, line in ipairs(lines) do
    if string.match(line, "exit%s*%(") then
      has_exit = true
      break
    end
  end

  if not has_exit then
    table.insert(lines, "")
    table.insert(lines, "exit(0);")
  end

  return lines
end

local function get_buffer_content(buf_id)
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  lines = ensure_exit_statement(lines)
  return table.concat(lines, "\n")
end

local function setup_results_window(results_buf)
  local results_win = vim.fn.bufwinid(results_buf)
  if results_win == -1 then
    create_results_split()
    vim.api.nvim_win_set_buf(0, results_buf)
  end
end

local function build_tinker_command(project_root, temp_file)
  return string.format(
    "cd %s && %s %s %s",
    vim.fn.shellescape(project_root),
    options.php_executable,
    options.cmd,
    vim.fn.shellescape(temp_file)
  )
end

local function create_job_callbacks(current_buf, temp_file)
  return {
    term = true,
    on_stdout = function(_, data, _)
      vim.schedule(function()
        local current_win = vim.fn.bufwinid(current_buf)
        vim.api.nvim_set_current_win(current_win)
      end)
    end,
    on_exit = function(_, exit_code)
      if temp_file and vim.fn.filereadable(temp_file) == 1 then
        vim.fn.delete(temp_file)
      end
    end,
  }
end

-- Execute PHP code in artisan tinker
function M.run_tinker()
  local current_buf = vim.api.nvim_get_current_buf()

  local project_root = utils.find_laravel_project()
  if not project_root then
    vim.notify("Error: artisan file not found. Make sure you are in a Laravel project root.", vim.log.levels.ERROR)
    return
  end

  local content = get_buffer_content(current_buf)
  local results_buf = reset_or_create_output_buf()

  setup_results_window(results_buf)

  local temp_file = write_temp_file(content)
  local cmd = build_tinker_command(project_root, temp_file)
  local job_opts = create_job_callbacks(current_buf, temp_file)
  job_opts.buf = results_buf

  vim.fn.jobstart(cmd, job_opts)
end

return M
