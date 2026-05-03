<div align="center">

<h1>
  <img src="assets/logo.svg" alt="buffer-preview.nvim logo" width="45" height="45" align="absmiddle" />
  buffer-preview.nvim
</h1>

Give your Neovim buffers real previews instead of raw file bytes.

![Neovim version](https://img.shields.io/badge/Neovim-0.10.0%2B-57A143?style=for-the-badge&labelColor=1E1E2E)
![License](https://img.shields.io/github/license/propilideno/buffer-preview.nvim?style=for-the-badge&labelColor=1E1E2E&color=3B8ED0)
![Last Release](https://img.shields.io/github/v/release/propilideno/buffer-preview.nvim?style=for-the-badge&labelColor=1E1E2E&color=3B8ED0)
![GitHub issues](https://img.shields.io/github/issues/propilideno/buffer-preview.nvim?style=for-the-badge&labelColor=1E1E2E&color=3B8ED0)
![GitHub last commit](https://img.shields.io/github/last-commit/propilideno/buffer-preview.nvim?style=for-the-badge&labelColor=1E1E2E&color=3B8ED0)

[Features](#features) • [Install](#installation) • [Usage](#usage)

<img src="assets/example-pdf.png" alt="buffer-preview.nvim rendering a PDF directly inside a Neovim buffer" width="50%" />
<img src="assets/example-presentation.png" alt="buffer-preview.nvim rendering a presentation directly inside a Neovim buffer" width="49%" />

<img src="assets/example-sqlite.png" alt="buffer-preview.nvim opening a SQLite database in a two-buffer SQL workspace" width="100%" />

`buffer-preview.nvim` hijacks the normal buffer read for supported
files and replaces raw bytes with a read-only, navigable in-buffer preview.
Keep the document inside Neovim, move with familiar Vim keys, and avoid
context-switching to a separate viewer.

</div>

## Requirements

The requirements depends on which preview you want, install only what you need.

### Image preview

For PDF and presentation files (`.pdf`, `.pptx`, `.ppt`, `.odp`):

- [image.nvim](https://github.com/3rd/image.nvim): handles image rendering
- ImageMagick: required by image.nvim
- pdftoppm: required to convert pdf to png
- pdfinfo: required to show metadata (status line)
- soffice: for presentation conversion (.pptx, .ppt, .odp)

#### Tmux support

For running image preview inside tmux, add to `~/.tmux.conf`:

```tmux
# https://github.com/3rd/image.nvim#tmux
set -gq allow-passthrough on
set -g visual-activity off
set -g focus-events on
```

### Data preview

- sqlite3: for SQLite files (.db, .sqlite, .sqlite3)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "propilideno/buffer-preview.nvim",
  event = {
    -- Image preview
    "BufReadCmd *.pdf", "BufReadCmd *.pptx", "BufReadCmd *.ppt", "BufReadCmd *.odp",
    -- Data preview
    "BufReadCmd *.db", "BufReadCmd *.sqlite", "BufReadCmd *.sqlite3",
  },
  dependencies = {
    "3rd/image.nvim", -- only needed for image preview (PDF / presentation)
  },
  opts = {},
}
```

#### Arch Linux

```sh
# Image preview dependencies
sudo pacman -S poppler imagemagick \
               libreoffice-fresh # Optional: for presentation preview

# Data preview dependencies
sudo pacman -S sqlite
```

#### Ubuntu / Debian

```sh
# Image preview dependencies
sudo apt install poppler-utils imagemagick \
                 libreoffice # Optional: for presentation preview

# Data preview dependencies
sudo apt install sqlite3
```

## Default Configuration

All fields are optional. These currently configure the PDF rendering backend.

```lua
require("buffer-preview").setup({
  -- "pdftoppm" (default) or "pdftocairo"
  rasterizer = "pdftoppm",
  -- Rasterization DPI (higher = sharper but slower)
  dpi = 200,
  -- Where rendered page PNGs are cached
  cache_dir = vim.fn.stdpath("cache") .. "/buffer-preview.nvim",
})
```

## Features

- [x] buffer-hijacking: supported buffers are hijacked and rendered as previews instead of raw bytes
- [x] page-viewer: read-only buffer with Vim-style page movement
- [x] PDF support (.pdf)
- [x] PowerPoint support (.pptx, .ppt)
- [x] OpenDocument Presentation support (.odp)
- [x] SQLite support (.db, .sqlite, .sqlite3)
- [ ] Parquet support
- [ ] Excel support

## Usage

### PDF / Presentation

| Key                                              | Action        |
| ------------------------------------------------ | ------------- |
| `j` `l` `↓` `]` `}` `Space` `Ctrl-d` `Ctrl-f`    | Next page     |
| `k` `h` `↑` `[` `{` `Ctrl-u` `Ctrl-b`            | Previous page |
| `g`                                              | First page    |
| `G`                                              | Last page     |
| `<number>G`                                      | Go to page N  |
| `r` `Ctrl-l`                                     | Refresh       |
| `q`                                              | Close viewer  |

### SQLite

Opening a `.db` / `.sqlite` / `.sqlite3` file spawns a two-buffer workspace:

- **Top** — read-only result preview. Initially shows the database schema
  (tables, views, triggers).
- **Bottom** — editable SQL buffer. Write any SQL that `sqlite3` accepts,
  including writes and DDL.

| Key / Command                | Action                                    |
| ---------------------------- | ----------------------------------------- |
| `:w` (save the buffer)<br>`:BufferPreviewRunQuery` | Run the whole bottom buffer as SQL |

The bottom buffer's contents are preserved after a run. Successful write
statements render `Query executed successfully` in the top buffer; errors
render `-- Error` followed by the `sqlite3` stderr.

## How It Works

1. `BufReadCmd` hijacks supported files before Neovim reads their raw bytes.
2. The plugin replaces the file buffer with a read-only scratch buffer.
3. A format-specific backend generates preview data for that buffer.
4. The preview is rendered in-place while normal Neovim navigation remains in
   control.

For PDFs, the backend:

1. Detects page count with `pdfinfo`
2. Rasterizes pages to PNG with `pdftoppm` or `pdftocairo`
3. Displays the page with `image.nvim`
4. Uses page-navigation mappings instead of normal text editing

For presentation files (`.pptx`, `.ppt`, `.odp`), the backend:

1. Converts the presentation to PDF with `soffice --headless`
2. Reuses the same PDF page-count, rasterization, and display pipeline
3. Keeps the same in-buffer navigation and `Page` layout

For SQLite files (`.db`, `.sqlite`, `.sqlite3`), the backend:

1. Opens a two-buffer workspace: a read-only result buffer on top and an
   editable SQL buffer on the bottom
2. Runs an initial schema query against `sqlite_master` to orient the user
3. Pipes the bottom buffer's contents into the `sqlite3` CLI via stdin and
   renders the result (table / success message / error) into the top buffer

## Architecture

- `plugin/buffer-preview.lua`: dispatches buffer hijacking per backend
- `lua/buffer-preview/image/viewer.lua`: PDF / presentation preview buffer lifecycle
- `lua/buffer-preview/image/converter.lua`: converts presentation files to cached PDF with `soffice`
- `lua/buffer-preview/image/rasterizer.lua`: PDF page rasterization and cache
- `lua/buffer-preview/image/display.lua`: image rendering via `image.nvim`
- `lua/buffer-preview/data/runner.lua`: `sqlite3` CLI wrapper (data backends)
- `lua/buffer-preview/data/viewer.lua`: two-buffer data workspace
- `lua/buffer-preview/config.lua`: backend configuration

## Star History

<p align="center">
  <a href="https://www.star-history.com/?repos=propilideno%2Fbuffer-preview.nvim&type=date&legend=top-left">
   <picture>
     <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=propilideno/buffer-preview.nvim&type=Date&theme=dark&legend=top-left" />
     <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=propilideno/buffer-preview.nvim&type=Date&legend=top-left" />
     <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=propilideno/buffer-preview.nvim&type=date&legend=top-left" width="600"/>
   </picture>
  </a>
</p>
