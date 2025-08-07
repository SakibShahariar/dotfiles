local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- Statusline
  "nvim-lualine/lualine.nvim",

  -- File explorer
  "nvim-tree/nvim-tree.lua",

  -- Fuzzy finder
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },

  -- Syntax highlighting engine
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },

  -- Theme
  { "catppuccin/nvim", name = "catppuccin" }
})

