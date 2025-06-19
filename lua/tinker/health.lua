local utils = require("tinker.utils")
local tinker = require("tinker")
local M = {}

M.check = function()
  vim.health.start("tinker.nvim report")

  -- Get the configured PHP executable
  local php_executable = tinker.get_php_executable and tinker.get_php_executable() or "php"

  -- Check for Laravel project
  local project_root = utils.find_laravel_project()
  if project_root then
    vim.health.ok("Laravel project detected at: " .. project_root)
  else
    vim.health.warn("No Laravel project detected", {
      "Make sure you're in a Laravel project directory",
      "The artisan file should be present in the project root",
    })
  end

  -- Check for PHP
  if vim.fn.executable(php_executable) == 1 then
    vim.health.ok("PHP executable found: " .. php_executable)
  else
    vim.health.error("PHP executable not found: " .. php_executable, {
      "Install PHP to use tinker.nvim",
      "Make sure PHP is in your PATH",
      "Or configure php_executable in your setup",
    })
  end

  -- Check for artisan tinker command if Laravel project exists
  if project_root then
    local artisan_check =
        vim.fn.system("cd " .. vim.fn.shellescape(project_root) .. " && " .. php_executable .. " artisan list | grep tinker")
    if vim.v.shell_error == 0 then
      vim.health.ok("Artisan tinker command available")
    else
      vim.health.error("Artisan tinker command not available", {
        "Make sure Laravel Tinker is installed",
        "Run: composer require laravel/tinker",
      })
    end
  end
end

return M
