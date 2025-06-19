vim.api.nvim_create_user_command("TinkerScratch", function()
  -- Easy Reloading
  -- package.loaded["tinker"] = nil

  require("tinker").create_scratch_buffer()
end, {})
