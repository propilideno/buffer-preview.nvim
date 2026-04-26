--- PDF viewer buffer management for buffer-preview.nvim phase 1.
--- Handles buffer hijacking, keymaps, page state, and display lifecycle.
local converter = require("buffer-preview.image.converter")
local rasterizer = require("buffer-preview.image.rasterizer")
local display = require("buffer-preview.image.display")

local M = {}

--- Per-buffer viewer state.
---@class buffer-preview.ViewerState
---@field source_path string
---@field pdf_path string
---@field page_count number
---@field current_page number
---@field buf number
---@field augroup number

---@type table<number, buffer-preview.ViewerState>
M._states = {}

---------------------------------------------------------------------------
-- Internal helpers
---------------------------------------------------------------------------

--- Write the status bar and blank canvas into the buffer.
---@param state buffer-preview.ViewerState
local function update_status(state)
  local buf = state.buf
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return
  end

  local height = vim.api.nvim_win_get_height(win)
  local filename = vim.fn.fnamemodify(state.source_path, ":t")
  local status = string.format(
    "  %s  |  Page %d / %d  |  q:close  j/k:page  g/G:first/last  <num>G:goto",
    filename,
    state.current_page,
    state.page_count
  )

  vim.bo[buf].modifiable = true
  local lines = {}
  for _ = 1, math.max(height - 1, 0) do
    lines[#lines + 1] = ""
  end
  lines[#lines + 1] = status
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

--- Render the current page image and overlay it on the buffer.
---@param state buffer-preview.ViewerState
local function render_page(state)
  local png_path = rasterizer.rasterize_page(state.pdf_path, state.current_page)
  if not png_path then
    vim.notify("buffer-preview.nvim: failed to render page " .. state.current_page, vim.log.levels.ERROR)
    return
  end

  update_status(state)

  if not vim.api.nvim_buf_is_valid(state.buf) then
    return
  end
  if vim.api.nvim_get_current_buf() ~= state.buf then
    return
  end

  local win = vim.fn.bufwinid(state.buf)
  if win == -1 then
    return
  end

  display.show(png_path, win, state.buf)
end

--- Navigate to a specific page number (clamped to valid range).
---@param state buffer-preview.ViewerState
---@param page number
local function goto_page(state, page)
  page = math.max(1, math.min(page, state.page_count))
  if page == state.current_page then
    return
  end

  state.current_page = page
  render_page(state)
end

---------------------------------------------------------------------------
-- Keymaps
---------------------------------------------------------------------------

---@param state buffer-preview.ViewerState
local function setup_keymaps(state)
  local buf = state.buf
  local opts = { buffer = buf, noremap = true, silent = true, nowait = true }

  -- Next page
  for _, key in ipairs({ "j", "<Down>", "]", "}", "<C-d>", "<C-f>", "<Space>", "l" }) do
    vim.keymap.set("n", key, function()
      goto_page(state, state.current_page + 1)
    end, opts)
  end

  -- Previous page
  for _, key in ipairs({ "k", "<Up>", "[", "{", "<C-u>", "<C-b>", "h" }) do
    vim.keymap.set("n", key, function()
      goto_page(state, state.current_page - 1)
    end, opts)
  end

  -- First page (bare `g` with nowait)
  vim.keymap.set("n", "g", function()
    local count = vim.v.count
    if count > 0 then
      goto_page(state, count)
    else
      goto_page(state, 1)
    end
  end, opts)

  -- Last page / go-to-page with count (e.g. `5G` -> page 5)
  vim.keymap.set("n", "G", function()
    local count = vim.v.count
    if count > 0 then
      goto_page(state, count)
    else
      goto_page(state, state.page_count)
    end
  end, opts)

  -- Refresh display
  vim.keymap.set("n", "r", function()
    render_page(state)
  end, opts)
  vim.keymap.set("n", "<C-l>", function()
    render_page(state)
  end, opts)

  -- Close viewer
  vim.keymap.set("n", "q", function()
    display.clear(state.buf)
    vim.cmd("bdelete")
  end, opts)
end

---------------------------------------------------------------------------
-- Autocmds
---------------------------------------------------------------------------

---@param state buffer-preview.ViewerState
local function setup_autocmds(state)
  local group = vim.api.nvim_create_augroup("BufferPreviewViewer_" .. state.buf, { clear = true })
  state.augroup = group

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    buffer = state.buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_get_current_buf() == state.buf then
        render_page(state)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufLeave", {
    group = group,
    buffer = state.buf,
    callback = function()
      display.clear(state.buf)
    end,
  })

  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_get_current_buf() == state.buf then
        render_page(state)
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    buffer = state.buf,
    callback = function()
      display.clear(state.buf)
      M._states[state.buf] = nil
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------

--- Open a supported file in the current buffer as a read-only image viewer.
---@param source_path string Path to the source file (may be relative)
function M.open(source_path)
  source_path = vim.fn.fnamemodify(source_path, ":p")

  if vim.fn.filereadable(source_path) ~= 1 then
    vim.notify("buffer-preview.nvim: file not found: " .. source_path, vim.log.levels.ERROR)
    return
  end

  if not display.is_supported() then
    vim.notify(
      "buffer-preview.nvim: image.nvim is required but not installed. See :help buffer-preview-requirements",
      vim.log.levels.ERROR
    )
    return
  end

  local pdf_path, convert_error = converter.to_pdf(source_path)
  if not pdf_path then
    vim.notify(convert_error, vim.log.levels.ERROR)
    return
  end

  local page_count = rasterizer.get_page_count(pdf_path)
  if not page_count or page_count < 1 then
    vim.notify("buffer-preview.nvim: could not determine page count for " .. source_path, vim.log.levels.ERROR)
    return
  end

  local buf = vim.api.nvim_get_current_buf()

  -- Buffer options — read-only scratch buffer
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "pdf"

  -- Window options — clean canvas
  local win = vim.api.nvim_get_current_win()
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = false
  vim.wo[win].cursorcolumn = false
  vim.wo[win].colorcolumn = ""
  vim.wo[win].wrap = false
  vim.wo[win].statuscolumn = ""

  local state = {
    source_path = source_path,
    pdf_path = pdf_path,
    page_count = page_count,
    current_page = 1,
    buf = buf,
    augroup = 0,
  }

  M._states[buf] = state

  setup_keymaps(state)
  setup_autocmds(state)

  -- Wait until the hijacked buffer has been drawn once before the initial
  -- image render so image.nvim gets stable window geometry.
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_get_current_buf() == state.buf then
      render_page(state)
    end
  end, 10)
end

return M
