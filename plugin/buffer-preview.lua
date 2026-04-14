--- buffer-preview.nvim — hijack PDF buffers as image viewers.
local group = vim.api.nvim_create_augroup("BufferPreviewNvim", { clear = true })

-- Primary path: intercept the buffer before Neovim reads raw bytes.
vim.api.nvim_create_autocmd("BufReadCmd", {
  pattern = "*.pdf",
  group = group,
  callback = function(ev)
    require("buffer-preview.viewer").open(ev.match)
  end,
})

-- Fallback for lazy-loaders (e.g. lazy.nvim with ft = {"pdf"}):
-- When the plugin loads after BufReadCmd has already fired, the current
-- buffer may contain raw PDF bytes.  Re-hijack any PDF buffer that hasn't
-- been set up yet.
vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
  pattern = "*.pdf",
  group = group,
  callback = function(ev)
    local buf = ev.buf
    -- Skip buffers already managed by the viewer.
    if require("buffer-preview.viewer")._states[buf] then
      return
    end
    local path = vim.api.nvim_buf_get_name(buf)
    if path ~= "" and path:match("%.pdf$") then
      require("buffer-preview.viewer").open(path)
    end
  end,
})
