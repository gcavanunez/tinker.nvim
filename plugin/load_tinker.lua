vim.api.nvim_create_user_command("PresentStart", function()
  -- Easy Reloading
  -- package.loaded["tinker"] = nil

  require("tinker").create_scratch_buffer()
end, {})
