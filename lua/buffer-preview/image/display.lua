--- Image display for buffer-preview.nvim.
--- Delegates all rendering to image.nvim (3rd/image.nvim), which handles
--- Kitty, ueberzug, and sixel backends transparently.
local M = {}

--- Active image objects keyed by buffer number.
---@type table<number, table>
M._images = {}

--- Remove the currently displayed image for a buffer.
---@param buf number
function M.clear(buf)
  local img = M._images[buf]
  if img then
    img:clear()
    M._images[buf] = nil
  end
end

--- Render a PNG image inside a Neovim window via image.nvim.
---
---@param image_path string Absolute path to the PNG file
---@param win_id number Neovim window handle
---@param buf number Buffer number
function M.show(image_path, win_id, buf)
  local ok, api = pcall(require, "image")
  if not ok then
    vim.notify("buffer-preview.nvim: image.nvim is required but not found", vim.log.levels.ERROR)
    return
  end

  local width = vim.api.nvim_win_get_width(win_id)
  local height = vim.api.nvim_win_get_height(win_id)

  -- Leave 1 row for the status bar at the bottom of the buffer
  local img_height = math.max(height - 1, 1)

  local new_img = api.from_file(image_path, {
    window = win_id,
    buffer = buf,
    with_virtual_padding = false,
    inline = false,
    x = 0,
    y = 0,
    width = width,
    height = img_height,
    -- Override image.nvim's global caps (default max_height_window_percentage = 50)
    -- so the PDF page fills the entire window.
    max_width_window_percentage = 100,
    max_height_window_percentage = 100,
  })

  if new_img then
    -- Render the replacement image before clearing the previous one so page
    -- navigation swaps in-place instead of flashing an older cached frame.
    new_img:render()

    local old_img = M._images[buf]
    if old_img then
      old_img:clear()
    end

    M._images[buf] = new_img
  end
end

--- Check whether image.nvim is available.
---@return boolean
function M.is_supported()
  local ok = pcall(require, "image")
  return ok
end

return M
