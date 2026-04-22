local has_sqlite3 = vim.fn.executable("sqlite3") == 1

local function test(name, fn)
  if has_sqlite3 then
    it(name, fn)
  else
    pending(name .. " (sqlite3 not available)")
  end
end

local function make_db()
  local path = vim.fn.tempname() .. ".db"
  vim.fn.system({
    "sqlite3",
    path,
    "CREATE TABLE t (id INTEGER, name TEXT); INSERT INTO t VALUES (1, 'alice'), (2, 'bob');",
  })
  return path
end

describe("buffer-preview.data.runner", function()
  local runner = require("buffer-preview.data.runner")
  local db

  before_each(function()
    if has_sqlite3 then
      db = make_db()
    end
  end)

  after_each(function()
    if db then
      vim.fn.delete(db)
      db = nil
    end
  end)

  test("returns rows for a SELECT", function()
    local r = runner.run(db, "SELECT * FROM t ORDER BY id;")
    assert.is_true(r.ok)
    assert.is_nil(r.err)
    local combined = table.concat(r.output, "\n")
    assert.is_truthy(combined:match("alice"))
    assert.is_truthy(combined:match("bob"))
  end)

  test("returns empty output on successful writes", function()
    local r = runner.run(db, "INSERT INTO t VALUES (3, 'carol');")
    assert.is_true(r.ok)
    assert.equals(0, #r.output)
  end)

  test("returns empty output on successful DDL", function()
    local r = runner.run(db, "CREATE TABLE u (id INTEGER);")
    assert.is_true(r.ok)
    assert.equals(0, #r.output)
  end)

  test("returns error on invalid SQL", function()
    local r = runner.run(db, "SELECT * FROM not_a_table;")
    assert.is_false(r.ok)
    assert.is_string(r.err)
    assert.is_truthy(r.err:lower():match("no such table"))
  end)
end)

describe("buffer-preview.data.viewer", function()
  local data_viewer = require("buffer-preview.data.viewer")
  local db

  before_each(function()
    if has_sqlite3 then
      db = make_db()
      vim.cmd("silent! %bwipeout!")
      vim.cmd("enew")
    end
  end)

  after_each(function()
    vim.cmd("silent! %bwipeout!")
    if db then
      vim.fn.delete(db)
      db = nil
    end
  end)

  test("opens a two-buffer workspace and loads the schema", function()
    local state = data_viewer.open(db)
    assert.is_not_nil(state)
    assert.is_true(vim.api.nvim_buf_is_valid(state.top_buf))
    assert.is_true(vim.api.nvim_buf_is_valid(state.bottom_buf))
    assert.are_not.equals(state.top_buf, state.bottom_buf)

    assert.equals(false, vim.bo[state.top_buf].modifiable)
    assert.equals(true, vim.bo[state.bottom_buf].modifiable)

    local top_lines = vim.api.nvim_buf_get_lines(state.top_buf, 0, -1, false)
    local top_text = table.concat(top_lines, "\n")
    assert.is_truthy(top_text:match("table"))
    assert.is_truthy(top_text:match("t"))
  end)

  test("runs the query on :w and updates only the top", function()
    local state = data_viewer.open(db)

    local sql = { "SELECT * FROM t ORDER BY id;" }
    vim.api.nvim_buf_set_lines(state.bottom_buf, 0, -1, false, sql)

    vim.api.nvim_buf_call(state.bottom_buf, function()
      vim.cmd("silent write")
    end)

    local top_text = table.concat(vim.api.nvim_buf_get_lines(state.top_buf, 0, -1, false), "\n")
    assert.is_truthy(top_text:match("alice"))
    assert.is_truthy(top_text:match("bob"))

    local bottom_after = vim.api.nvim_buf_get_lines(state.bottom_buf, 0, -1, false)
    assert.are.same(sql, bottom_after)
    assert.equals(false, vim.bo[state.bottom_buf].modified)
  end)

  test("shows success message for write queries", function()
    local state = data_viewer.open(db)

    vim.api.nvim_buf_set_lines(state.bottom_buf, 0, -1, false, {
      "INSERT INTO t VALUES (3, 'carol');",
    })

    vim.api.nvim_buf_call(state.bottom_buf, function()
      vim.cmd("BufferPreviewRunQuery")
    end)

    local top_lines = vim.api.nvim_buf_get_lines(state.top_buf, 0, -1, false)
    assert.are.same({ "Query executed successfully" }, top_lines)
  end)

  test("shows error output for invalid queries", function()
    local state = data_viewer.open(db)

    vim.api.nvim_buf_set_lines(state.bottom_buf, 0, -1, false, {
      "SELECT * FROM not_a_table;",
    })

    vim.api.nvim_buf_call(state.bottom_buf, function()
      vim.cmd("BufferPreviewRunQuery")
    end)

    local top_text = table.concat(vim.api.nvim_buf_get_lines(state.top_buf, 0, -1, false), "\n")
    assert.is_truthy(top_text:match("-- Error"))
    assert.is_truthy(top_text:lower():match("no such table"))
  end)
end)
