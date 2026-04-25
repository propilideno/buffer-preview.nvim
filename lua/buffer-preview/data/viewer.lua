--- SQLite data-viewer for buffer-preview.nvim.
--- Two-buffer workspace:
---   * top buffer   — hijacked file buffer, read-only result preview
---   * bottom buffer — editable SQL input buffer
--- The bottom buffer runs arbitrary SQL through the sqlite3 CLI and renders
--- the result into the top buffer.
local runner = require("buffer-preview.data.runner")

local M = {}

---@class buffer-preview.SqliteState
---@field db_path string
---@field top_buf number
---@field bottom_buf number
---@field augroup number

---@type table<number, buffer-preview.SqliteState>
M._states = {}

--- Reverse lookup: bottom buffer -> top buffer.
---@type table<number, number>
M._bottom_to_top = {}

local SCHEMA_QUERY = [[
SELECT
  type,
  name,
  tbl_name AS table_name,
  sql
FROM sqlite_master
WHERE type IN ('table', 'view', 'trigger')
  AND name NOT LIKE 'sqlite_%'
ORDER BY type, name;
]]

local STARTER_HINT = vim.list_extend(
  { "-- Write SQL here. Save the buffer (:w) to run it." },
  vim.split(vim.trim(SCHEMA_QUERY), "\n", { plain = true })
)

---@param buf number
---@param lines string[]
local function set_top_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

---@param state buffer-preview.SqliteState
---@param result { ok: boolean, output: string[], err: string|nil }
local function render_result(state, result)
  if result.ok then
    if #result.output == 0 then
      set_top_lines(state.top_buf, { "Query executed successfully" })
    else
      set_top_lines(state.top_buf, result.output)
    end
    return
  end

  local lines = { "-- Error" }
  for _, line in ipairs(vim.split(result.err or "", "\n", { plain = true })) do
    lines[#lines + 1] = line
  end
  set_top_lines(state.top_buf, lines)
end

---@param state buffer-preview.SqliteState
local function run_query(state)
  if not vim.api.nvim_buf_is_valid(state.bottom_buf) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(state.bottom_buf, 0, -1, false)
  local sql = table.concat(lines, "\n")
  if sql:match("^%s*$") then
    set_top_lines(state.top_buf, { "-- empty query" })
    return
  end
  render_result(state, runner.run(state.db_path, sql))
end

---@param state buffer-preview.SqliteState
local function setup_bottom(state)
  local buf = state.bottom_buf

  vim.api.nvim_buf_create_user_command(buf, "BufferPreviewRunQuery", function()
    run_query(state)
    vim.bo[buf].modified = false
  end, { desc = "Run SQL from the buffer-preview.nvim SQLite workspace" })
end

---@param state buffer-preview.SqliteState
local function setup_autocmds(state)
  local group = vim.api.nvim_create_augroup("BufferPreviewSqlite_" .. state.top_buf, { clear = true })
  state.augroup = group

  -- Tear down the companion when either buffer is unloaded. The buffer that
  -- fired BufUnload is already being wiped by `bufhidden=wipe`, so we must
  -- not touch it (E937). The companion delete is scheduled to avoid running
  -- buffer ops mid-unload.
  local function teardown(ev)
    if not M._states[state.top_buf] then
      return
    end
    M._states[state.top_buf] = nil
    M._bottom_to_top[state.bottom_buf] = nil
    pcall(vim.api.nvim_del_augroup_by_id, group)

    local companion = ev.buf == state.top_buf and state.bottom_buf or state.top_buf
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(companion) then
        pcall(vim.api.nvim_buf_delete, companion, { force = true })
      end
    end)
  end

  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    buffer = state.top_buf,
    callback = teardown,
  })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    buffer = state.bottom_buf,
    callback = teardown,
  })

  -- `:w` on the SQL buffer runs the query. `acwrite` + BufWriteCmd lets us
  -- hijack the write without touching disk.
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = group,
    buffer = state.bottom_buf,
    callback = function()
      run_query(state)
      vim.bo[state.bottom_buf].modified = false
    end,
  })
end

--- Open a SQLite file in the two-buffer workspace.
---@param source_path string
---@return buffer-preview.SqliteState|nil
function M.open(source_path)
  source_path = vim.fn.fnamemodify(source_path, ":p")

  if vim.fn.filereadable(source_path) ~= 1 then
    vim.notify("buffer-preview.nvim: file not found: " .. source_path, vim.log.levels.ERROR)
    return nil
  end

  if not runner.is_available() then
    vim.notify(
      "buffer-preview.nvim: sqlite3 CLI is required but not found in PATH",
      vim.log.levels.ERROR
    )
    return nil
  end

  local top_buf = vim.api.nvim_get_current_buf()
  vim.bo[top_buf].buftype = "nofile"
  vim.bo[top_buf].bufhidden = "wipe"
  vim.bo[top_buf].swapfile = false
  vim.bo[top_buf].modifiable = false
  vim.bo[top_buf].filetype = "sqlite-preview"

  vim.cmd("belowright new")
  local bottom_buf = vim.api.nvim_get_current_buf()
  -- `acwrite` lets `:w` fire BufWriteCmd instead of erroring on "no file name".
  vim.bo[bottom_buf].buftype = "acwrite"
  vim.bo[bottom_buf].bufhidden = "wipe"
  vim.bo[bottom_buf].swapfile = false
  vim.bo[bottom_buf].filetype = "sql"
  pcall(
    vim.api.nvim_buf_set_name,
    bottom_buf,
    "buffer-preview://" .. vim.fn.fnamemodify(source_path, ":t") .. "/query.sql"
  )
  vim.api.nvim_buf_set_lines(bottom_buf, 0, -1, false, STARTER_HINT)
  vim.bo[bottom_buf].modified = false

  local state = {
    db_path = source_path,
    top_buf = top_buf,
    bottom_buf = bottom_buf,
    augroup = 0,
  }
  M._states[top_buf] = state
  M._bottom_to_top[bottom_buf] = top_buf

  setup_bottom(state)
  setup_autocmds(state)

  render_result(state, runner.run(source_path, SCHEMA_QUERY))

  return state
end

return M
