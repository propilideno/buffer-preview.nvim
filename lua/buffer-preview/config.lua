---@class buffer-preview.Config
---@field rasterizer string "pdftoppm" or "pdftocairo"
---@field dpi number Rasterization DPI
---@field cache_dir string Cache directory for rendered page images

---@class buffer-preview.UserConfig
---@field rasterizer? string
---@field dpi? number
---@field cache_dir? string

local M = {}

---@type buffer-preview.Config
local defaults = {
  rasterizer = "pdftoppm",
  dpi = 200,
  cache_dir = vim.fn.stdpath("cache") .. "/buffer-preview.nvim",
}

---@type buffer-preview.Config
local state = vim.deepcopy(defaults)

---@return buffer-preview.Config
function M.get()
  return state
end

---@param opts buffer-preview.UserConfig|nil
---@return buffer-preview.Config
function M.setup(opts)
  state = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return state
end

return M
