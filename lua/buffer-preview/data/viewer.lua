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
---@field top_win number|nil    -- window currently in the "top" role (showing top_buf)
---@field bottom_win number|nil -- window currently in the "bottom" role (showing bottom_buf)
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
  vim.api.nvim_buf_create_user_command(state.bottom_buf, "BufferPreviewRunQuery", function()
    run_query(state)
    vim.bo[state.bottom_buf].modified = false
  end, { desc = "Run SQL from the buffer-preview.nvim SQLite workspace" })
end

---@param win number|nil
---@return boolean
local function win_valid(win)
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---@param state buffer-preview.SqliteState
local function setup_autocmds(state)
  local group = vim.api.nvim_create_augroup("BufferPreviewSqlite_" .. state.top_buf, { clear = true })
  state.augroup = group

  -- Reentrancy guard for our own programmatic window/buffer changes.
  local syncing = false

  -- Hard kill: drop state and wipe both buffers. Idempotent. Schedule the
  -- wipe so it runs after the autocmd that triggered it has completed.
  local function kill_workspace()
    if not M._states[state.top_buf] then
      return
    end
    M._states[state.top_buf] = nil
    M._bottom_to_top[state.bottom_buf] = nil
    pcall(vim.api.nvim_del_augroup_by_id, group)

    local top_buf, bottom_buf = state.top_buf, state.bottom_buf
    vim.schedule(function()
      for _, buf in ipairs({ top_buf, bottom_buf }) do
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end)
  end

  -- Refresh top_win/bottom_win to drop closed-window entries.
  local function refresh_role_wins()
    if not win_valid(state.top_win) then
      state.top_win = nil
    end
    if not win_valid(state.bottom_win) then
      state.bottom_win = nil
    end
  end

  -- Layout follows focus:
  --   * focus on a workspace buffer → ensure the split exists and snap the
  --     two role windows to their canonical buffers (no double-view).
  --   * foreign buffer in a tracked role window → collapse the split by
  --     closing the OTHER role window. The foreign window stays.
  --   * foreign buffer in a non-workspace window (sidebar, etc.) → no-op.
  local function reconcile()
    if syncing then
      return
    end
    if not M._states[state.top_buf] then
      return
    end

    refresh_role_wins()

    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_get_current_buf()
    local in_workspace = current_buf == state.top_buf or current_buf == state.bottom_buf

    syncing = true

    if not in_workspace then
      -- Collapse only when the foreign buf landed in a tracked role window.
      if current_win == state.top_win or current_win == state.bottom_win then
        for _, win in ipairs({ state.top_win, state.bottom_win }) do
          if win ~= current_win and win_valid(win) and #vim.api.nvim_list_wins() > 1 then
            pcall(vim.api.nvim_win_close, win, true)
          end
        end
        if current_win == state.top_win then
          state.top_win = nil
        else
          state.bottom_win = nil
        end
      end
      syncing = false
      return
    end

    -- Snap canonical layout: top_win shows top_buf, bottom_win shows bottom_buf.
    -- If the user landed in a role window with the *other* role's buffer
    -- (e.g. Tabbed bottom_win to top_buf), restore the buffers and shift
    -- focus to the role that actually matches the current buffer.
    if current_win == state.bottom_win and current_buf == state.top_buf and win_valid(state.top_win) then
      pcall(vim.api.nvim_win_set_buf, state.bottom_win, state.bottom_buf)
      pcall(vim.api.nvim_set_current_win, state.top_win)
      pcall(vim.api.nvim_win_set_buf, state.top_win, state.top_buf)
      syncing = false
      return
    end
    if current_win == state.top_win and current_buf == state.bottom_buf and win_valid(state.bottom_win) then
      pcall(vim.api.nvim_win_set_buf, state.top_win, state.top_buf)
      pcall(vim.api.nvim_set_current_win, state.bottom_win)
      pcall(vim.api.nvim_win_set_buf, state.bottom_win, state.bottom_buf)
      syncing = false
      return
    end

    -- Adopt the current window into the matching role.
    if current_buf == state.top_buf then
      state.top_win = current_win
    else
      state.bottom_win = current_win
    end

    -- If the companion isn't visible anywhere, split the current window.
    local companion_buf = current_buf == state.top_buf and state.bottom_buf or state.top_buf
    if #vim.fn.win_findbuf(companion_buf) == 0 then
      local cmd = current_buf == state.top_buf and "belowright sb " or "aboveleft sb "
      local ok = pcall(vim.cmd, cmd .. companion_buf)
      if ok then
        local new_win = vim.api.nvim_get_current_win()
        if current_buf == state.top_buf then
          state.bottom_win = new_win
        else
          state.top_win = new_win
        end
        if win_valid(current_win) then
          pcall(vim.api.nvim_set_current_win, current_win)
        end
      end
    end

    syncing = false
  end

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = reconcile,
  })

  -- `:q` / `:close` on a window currently showing a workspace buf kills both.
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      if syncing then
        return
      end
      if not M._states[state.top_buf] then
        return
      end
      local closed_win = tonumber(ev.match)
      if not closed_win then
        return
      end
      local ok, buf = pcall(vim.api.nvim_win_get_buf, closed_win)
      if not ok then
        return
      end
      if buf == state.top_buf or buf == state.bottom_buf then
        kill_workspace()
      end
    end,
  })

  -- `:bd` / `:bw` on either workspace buffer kills both.
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    buffer = state.top_buf,
    callback = function() if not syncing then kill_workspace() end end,
  })
  vim.api.nvim_create_autocmd("BufUnload", {
    group = group,
    buffer = state.bottom_buf,
    callback = function() if not syncing then kill_workspace() end end,
  })

  -- `:w` on the SQL buffer runs the query.
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
  local top_win = vim.api.nvim_get_current_win()
  vim.bo[top_buf].buftype = "nofile"
  -- `hide` keeps the buffer alive when the window swaps, so cycling through
  -- the bufferline doesn't destroy the workspace.
  vim.bo[top_buf].bufhidden = "hide"
  vim.bo[top_buf].swapfile = false
  vim.bo[top_buf].modifiable = false
  vim.bo[top_buf].filetype = "sqlite-preview"
  -- Tells the BufEnter fallback in plugin/buffer-preview.lua not to re-hijack
  -- this buffer during teardown limbo. The flag dies with the buffer.
  vim.b[top_buf].buffer_preview_handled = true

  vim.cmd("belowright new")
  local bottom_buf = vim.api.nvim_get_current_buf()
  local bottom_win = vim.api.nvim_get_current_win()
  -- `acwrite` lets `:w` fire BufWriteCmd instead of erroring on "no file name".
  vim.bo[bottom_buf].buftype = "acwrite"
  vim.bo[bottom_buf].bufhidden = "hide"
  vim.bo[bottom_buf].swapfile = false
  vim.bo[bottom_buf].filetype = "sql"
  pcall(
    vim.api.nvim_buf_set_name,
    bottom_buf,
    "buffer-preview://" .. vim.fn.fnamemodify(source_path, ":t") .. "/query.sql"
  )
  vim.api.nvim_buf_set_lines(bottom_buf, 0, -1, false, STARTER_HINT)
  vim.bo[bottom_buf].modified = false
  vim.b[bottom_buf].buffer_preview_handled = true

  local state = {
    db_path = source_path,
    top_buf = top_buf,
    bottom_buf = bottom_buf,
    top_win = top_win,
    bottom_win = bottom_win,
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
