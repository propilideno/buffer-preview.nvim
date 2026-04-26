--- sqlite3 CLI wrapper for buffer-preview.nvim.
--- Feeds SQL via stdin and returns structured output/error.
local M = {}

local SQLITE3_BIN = "sqlite3"

---@return boolean
function M.is_available()
  return vim.fn.executable(SQLITE3_BIN) == 1
end

---@param s string|nil
---@return string[]
local function to_lines(s)
  if not s or s == "" then
    return {}
  end
  local lines = vim.split(s, "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines
end

--- Run arbitrary SQL against a SQLite database.
---
---@param db_path string Absolute path to the SQLite file
---@param sql string SQL source (may contain multiple statements)
---@return { ok: boolean, output: string[], err: string|nil }
function M.run(db_path, sql)
  local cmd = { SQLITE3_BIN, "-header", "-column", "-bail", db_path }
  local result = vim.system(cmd, { stdin = sql, text = true }):wait()

  if result.code == 0 then
    return { ok = true, output = to_lines(result.stdout), err = nil }
  end

  local err = result.stderr
  if not err or err == "" then
    err = result.stdout or "unknown error"
  end
  return { ok = false, output = {}, err = err }
end

return M
