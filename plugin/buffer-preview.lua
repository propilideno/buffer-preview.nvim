--- buffer-preview.nvim phase 1 hijacks PDF buffers before Neovim reads raw content.
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "*.pdf",
  group = vim.api.nvim_create_augroup("BufferPreviewNvim", { clear = true }),
  callback = function(ev)
    require("buffer-preview.viewer").open(ev.match)
  end,
})
