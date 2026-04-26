--- buffer-preview.nvim — hijack supported buffers as previews.
local group = vim.api.nvim_create_augroup("BufferPreviewNvim", { clear = true })

local backends = {
  {
    patterns = { "*.pdf", "*.pptx", "*.ppt", "*.odp" },
    module = "buffer-preview.image.viewer",
    exts = { "pdf", "pptx", "ppt", "odp" },
  },
  {
    patterns = { "*.db", "*.sqlite", "*.sqlite3" },
    module = "buffer-preview.data.viewer",
    exts = { "db", "sqlite", "sqlite3" },
  },
}

local function path_has_ext(path, exts)
  for _, ext in ipairs(exts) do
    if path:sub(-(#ext + 1)) == "." .. ext then
      return true
    end
  end
  return false
end

for _, backend in ipairs(backends) do
  -- Primary path: intercept the buffer before Neovim reads raw bytes.
  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = backend.patterns,
    group = group,
    callback = function(ev)
      require(backend.module).open(ev.match)
    end,
  })

  --- Fallback for lazy-loaders (e.g. lazy.nvim with ft = {...}):
  -- When the plugin loads after BufReadCmd has already fired, the current
  -- buffer may contain raw file bytes. Re-hijack any supported buffer that
  -- hasn't been set up yet.
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    pattern = backend.patterns,
    group = group,
    callback = function(ev)
      local buf = ev.buf
      if require(backend.module)._states[buf] then
        return
      end
      -- Skip buffers that this plugin already manages (e.g. workspace
      -- buffers in their teardown limbo). The flag is buffer-local, so it
      -- disappears when the buffer is wiped, letting fresh `:e file.db`
      -- still trigger a hijack.
      if vim.b[buf].buffer_preview_handled then
        return
      end
      local path = vim.api.nvim_buf_get_name(buf)
      if path ~= "" and path_has_ext(path, backend.exts) then
        require(backend.module).open(path)
      end
    end,
  })
end
