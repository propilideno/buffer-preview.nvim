local config = require("buffer-preview.config")

local M = {}

---@param source_path string
---@return string
local function cache_dir_for(source_path)
  local cfg = config.get()
  local hash = vim.fn.sha256(source_path)
  local dir = cfg.cache_dir .. "/converted/" .. hash:sub(1, 16)
  vim.fn.mkdir(dir, "p")
  return dir
end

---@param source_path string
---@param output_path string
---@return boolean
local function is_cache_fresh(source_path, output_path)
  if vim.fn.filereadable(output_path) ~= 1 then
    return false
  end

  local source_mtime = vim.fn.getftime(source_path)
  local output_mtime = vim.fn.getftime(output_path)
  return source_mtime > 0 and output_mtime >= source_mtime
end

---@return string|nil
local function soffice_binary()
  if vim.fn.executable("soffice") == 1 then
    return "soffice"
  end

  return nil
end

---@param source_path string
---@return string|nil, string|nil
function M.presentation_to_pdf(source_path)
  local soffice = soffice_binary()
  if not soffice then
    return nil, "buffer-preview.nvim: soffice is required to preview .pptx files"
  end

  local absolute_path = vim.fn.fnamemodify(source_path, ":p")
  local output_dir = cache_dir_for(absolute_path)
  local base_name = vim.fn.fnamemodify(absolute_path, ":t:r")
  local output_path = output_dir .. "/" .. base_name .. ".pdf"

  if is_cache_fresh(absolute_path, output_path) then
    return output_path, nil
  end

  local cmd = {
    soffice,
    "--headless",
    "--convert-to",
    "pdf",
    "--outdir",
    output_dir,
    absolute_path,
  }

  vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, "buffer-preview.nvim: failed to convert .pptx to PDF with soffice"
  end

  if vim.fn.filereadable(output_path) ~= 1 then
    return nil, "buffer-preview.nvim: soffice did not produce a PDF output"
  end

  return output_path, nil
end

---@param source_path string
---@return string|nil preview_pdf_path
---@return string|nil error_message
function M.to_pdf(source_path)
  local absolute_path = vim.fn.fnamemodify(source_path, ":p")
  local extension = vim.fn.fnamemodify(absolute_path, ":e"):lower()

  if extension == "pdf" then
    return absolute_path, nil
  end

  if extension == "pptx" then
    return M.presentation_to_pdf(absolute_path)
  end

  return nil, "buffer-preview.nvim: unsupported file type: ." .. extension
end

return M
