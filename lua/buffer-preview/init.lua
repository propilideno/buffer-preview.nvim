--- buffer-preview.nvim — in-buffer previews for non-text formats.
local config = require("buffer-preview.config")

---@class BufferPreviewModule
local M = {}

--- Configure the plugin. Call this from your Neovim config:
---
---   require("buffer-preview").setup({ dpi = 300 })
---
---@param opts buffer-preview.UserConfig|nil
function M.setup(opts)
  config.setup(opts)
end

return M
