--- PDF page rasterization for buffer-preview.nvim phase 1.
--- Converts individual PDF pages to PNG images using pdftoppm or pdftocairo.
local config = require("buffer-preview.config")

local M = {}

--- Get the number of pages in a PDF file.
---@param pdf_path string
---@return number|nil
function M.get_page_count(pdf_path)
  -- Try qpdf first (fast, dedicated tool)
  local result = vim.fn.system({ "qpdf", "--show-npages", pdf_path })
  if vim.v.shell_error == 0 then
    local count = tonumber(vim.trim(result))
    if count then
      return count
    end
  end

  -- Fallback: pdfinfo (from poppler-utils)
  result = vim.fn.system(
    "pdfinfo " .. vim.fn.shellescape(pdf_path) .. " 2>/dev/null | grep '^Pages:' | awk '{print $2}'"
  )
  if vim.v.shell_error == 0 then
    local count = tonumber(vim.trim(result))
    if count then
      return count
    end
  end

  return nil
end

--- Build a deterministic cache directory for a given PDF file.
---@param pdf_path string
---@return string
function M.get_cache_dir(pdf_path)
  local cfg = config.get()
  local hash = vim.fn.sha256(pdf_path)
  local dir = cfg.cache_dir .. "/" .. hash:sub(1, 16)
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Rasterize a single PDF page to PNG (synchronous).
---
--- Returns the cached image immediately if it already exists.
---
---@param pdf_path string Absolute path to the PDF
---@param page_num number 1-indexed page number
---@return string|nil png_path Absolute path to the rendered PNG, or nil on failure
function M.rasterize_page(pdf_path, page_num)
  local cfg = config.get()
  local cache_dir = M.get_cache_dir(pdf_path)
  local output_prefix = cache_dir .. "/page-" .. page_num
  local output_path = output_prefix .. ".png"

  if vim.fn.filereadable(output_path) == 1 then
    return output_path
  end

  local cmd
  if cfg.rasterizer == "pdftocairo" then
    cmd = {
      "pdftocairo",
      "-png",
      "-f", tostring(page_num),
      "-l", tostring(page_num),
      "-r", tostring(cfg.dpi),
      "-singlefile",
      pdf_path,
      output_prefix,
    }
  else
    cmd = {
      "pdftoppm",
      "-png",
      "-f", tostring(page_num),
      "-l", tostring(page_num),
      "-r", tostring(cfg.dpi),
      "-singlefile",
      pdf_path,
      output_prefix,
    }
  end

  vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end

  if vim.fn.filereadable(output_path) == 1 then
    return output_path
  end

  return nil
end

--- Remove all cached page images for a PDF file.
---@param pdf_path string
function M.cleanup(pdf_path)
  local cache_dir = M.get_cache_dir(pdf_path)
  vim.fn.delete(cache_dir, "rf")
end

return M
