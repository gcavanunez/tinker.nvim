local M = {}

---@class tinker.Options
---@field cmd string: The cmd that will be used to run the tinker
---@field split_direction string: Window split direction: 'horizontal', 'vertical', or 'tab'

---@type tinker.Options
local options = {
  cmd = "php artisan tinker",
  split_direction = "horizontal",
}

--- Setup the plugin
---@param opts present.Options
M.setup = function(opts)
  options = vim.tbl_deep_extend("force", opts or {})
end

M.scratch_buffers = {}
M.result_buf = nil

M.health = function() end

function M.create_scratch_buffer()
  local project_root = vim.fn.getcwd()

  local search_dir = vim.fn.expand("%:p:h")
  while search_dir ~= "/" and search_dir ~= "" do
    if vim.fn.filereadable(search_dir .. "/artisan") == 1 then
      project_root = search_dir
      break
    end
    search_dir = vim.fn.fnamemodify(search_dir, ":h")
  end

  if vim.fn.filereadable(project_root .. "/artisan") == 0 then
    if vim.fn.filereadable(vim.fn.getcwd() .. "/artisan") == 1 then
      project_root = vim.fn.getcwd()
    else
      vim.notify("Warning: No Laravel project detected. Creating scratch buffer anyway.", vim.log.levels.WARN)
    end
  end

  -- Define the scratch file path
  local scratch_dir = project_root .. "/vendor/_tinker_nvim_ide"
  local scratch_file = scratch_dir .. "/scratch.php"

  -- Create the directory if it doesn't exist
  vim.fn.mkdir(scratch_dir, "p")

  -- Check if we already have a buffer open for this scratch file
  local existing_buf_id = vim.fn.bufnr(scratch_file)
  if existing_buf_id ~= -1 and vim.api.nvim_buf_is_valid(existing_buf_id) then
    -- Find if the buffer is already open in a window
    local win_id = vim.fn.bufwinid(existing_buf_id)
    if win_id ~= -1 then
      -- Buffer is already open, just focus it
      vim.api.nvim_set_current_win(win_id)
      -- vim.notify('Switched to existing scratch buffer for project: ' .. vim.fn.fnamemodify(project_root, ':t'),
      --     vim.log.levels.INFO)
      return existing_buf_id
    else
      -- Buffer exists but not open, open it in a new window
      vim.cmd("split")
      vim.api.nvim_win_set_buf(0, existing_buf_id)

      vim.keymap.set("n", "<leader>tr", M.run_tinker, {
        buffer = existing_buf_id,
        desc = "Run PHP code in artisan tinker",
      })
      -- vim.notify('Reopened existing scratch buffer for project: ' .. vim.fn.fnamemodify(project_root, ':t'),
      --     vim.log.levels.INFO)
      return existing_buf_id
    end
  end

  -- Create the scratch file if it doesn't exist
  if vim.fn.filereadable(scratch_file) == 0 then
    local initial_content = {
      "<?php",
      "",
    }

    vim.fn.writefile(initial_content, scratch_file)
  end

  vim.cmd("split")
  vim.cmd("edit " .. vim.fn.fnameescape(scratch_file))

  local buf_id = vim.api.nvim_get_current_buf()

  -- Set buffer options
  vim.api.nvim_set_option_value("filetype", "php", { buf = buf_id })

  M.scratch_buffers = M.scratch_buffers or {}
  M.scratch_buffers[project_root] = {
    buf_id = buf_id,
    project_root = project_root,
    file_path = scratch_file,
  }

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    buffer = buf_id,
    callback = function()
      if M.scratch_buffers then
        M.scratch_buffers[project_root] = nil
      end
    end,
    once = true,
  })

  -- Set up the tinker run keybinding
  vim.keymap.set("n", "<leader>tr", M.run_tinker, {
    buffer = buf_id,
    desc = "Run PHP code in artisan tinker",
  })

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

-- Execute PHP code in artisan tinker
function M.run_tinker()
  local current_buf = vim.api.nvim_get_current_buf()

  -- Find the project root (look for artisan file)
  local project_root = vim.fn.getcwd()
  local current_dir = vim.fn.expand("%:p:h")

  -- Walk up the directory tree to find artisan file
  local search_dir = current_dir
  while search_dir ~= "/" and search_dir ~= "" do
    if vim.fn.filereadable(search_dir .. "/artisan") == 1 then
      project_root = search_dir
      break
    end
    search_dir = vim.fn.fnamemodify(search_dir, ":h")
  end

  if vim.fn.filereadable(project_root .. "/artisan") == 0 then
    vim.notify("Error: artisan file not found. Make sure you are in a Laravel project root.", vim.log.levels.ERROR)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)

  lines = ensure_exit_statement(lines)

  local content = table.concat(lines, "\n")

  local results_buf = reset_or_create_output_buf()

  -- Open results buffer in a split if not already visible
  local results_win = vim.fn.bufwinid(results_buf)
  if results_win == -1 then
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, results_buf)
  end

  local temp_file = write_temp_file(content)

  local cmd =
      string.format("cd %s && %s %s", vim.fn.shellescape(project_root), options.cmd, vim.fn.shellescape(temp_file))

  vim.fn.jobstart(cmd, {
    term = true,
    buf = results_buf,
    on_stdout = function(_, data, _)
      vim.schedule(function()
        local current_win = vim.fn.bufwinid(current_buf)
        vim.api.nvim_set_current_win(current_win)
      end)
    end,
    on_exit = function(_, exit_code) end,
  })
end

return M
