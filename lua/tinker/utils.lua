local M = {}

M.find_laravel_project = function()
  -- First, try walking up from current file's directory
  -- given you're in vendor or other nested dir
  local search_dir = vim.fn.expand("%:p:h")
  while search_dir ~= "/" and search_dir ~= "" do
    if vim.fn.filereadable(search_dir .. "/artisan") == 1 then
      return search_dir
    end
    search_dir = vim.fn.fnamemodify(search_dir, ":h")
  end

  -- If not found, check current working directory
  local cwd = vim.fn.getcwd()
  if vim.fn.filereadable(cwd .. "/artisan") == 1 then
    return cwd
  end

  -- No Laravel project found
  return nil
end

return M
