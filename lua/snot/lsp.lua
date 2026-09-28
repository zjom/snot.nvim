--- The snot language server, when it is installed: starting it for the notes
--- directory and asking it things. Each function returns nil when the server
--- is off or missing, so callers can fall back to reading notes in Lua.

local config = require("snot.config")

local M = {}

--- How long to wait for the server, in milliseconds.
M.timeout = 5000

--- True if the `lsp` option is on and the server's command is installed.
---@return boolean
function M.enabled()
  if not config.get().lsp then
    return false
  end
  local cmd = (vim.lsp.config.snot or {}).cmd
  return type(cmd) == "table" and vim.fn.executable(cmd[1]) == 1
end

--- `client` once it has initialized, or nil if it doesn't in time.
---@param client vim.lsp.Client
---@return vim.lsp.Client?
local function ready(client)
  vim.wait(M.timeout, function()
    return client.initialized or client:is_stopped()
  end)
  return client.initialized and not client:is_stopped() and client or nil
end

--- The server for the notes directory, started if need be. Servers for
--- directories no longer configured are stopped once no buffer uses them.
---@return vim.lsp.Client?
function M.client()
  if not M.enabled() then
    return nil
  end
  local root = config.get().directory
  for _, client in ipairs(vim.lsp.get_clients({ name = "snot" })) do
    if client.root_dir ~= root and vim.tbl_isempty(client.attached_buffers) then
      client:stop()
    end
  end
  local conf = vim.tbl_extend("force", vim.lsp.config.snot, { name = "snot", root_dir = root })
  local id = vim.lsp.start(conf, { attach = false })
  local client = id and vim.lsp.get_client_by_id(id)
  return client and ready(client)
end

--- The server attached to `bufnr`, a note, once it is ready. It attaches
--- shortly after the buffer's filetype is set, so this waits for it.
---@param bufnr integer
---@return vim.lsp.Client?
function M.attached(bufnr)
  if not M.enabled() or vim.bo[bufnr].filetype ~= "snot" then
    return nil
  end
  local client
  vim.wait(M.timeout, function()
    client = vim.lsp.get_clients({ bufnr = bufnr, name = "snot" })[1]
    return client ~= nil
  end)
  return client and ready(client)
end

--- Ask the server, waiting for the answer.
---@param method string
---@param params? table
---@return any? result, string? err
function M.request(method, params)
  local client = M.client()
  if not client then
    return nil, "the snot language server is not running"
  end
  local res, err = client:request_sync(method, params or vim.NIL, M.timeout)
  if not res then
    return nil, err
  end
  if res.err then
    return nil, res.err.message
  end
  return res.result
end

--- Ask the server, calling `on_done(result)` or `on_done(nil, err)` on the
--- main loop. Returns false if the server isn't running.
---@param method string
---@param params? table
---@param on_done fun(result?: any, err?: string)
---@return boolean
function M.request_async(method, params, on_done)
  local client = M.client()
  if not client then
    return false
  end
  client:request(method, params or vim.NIL, function(err, result)
    if err then
      on_done(nil, err.message)
    else
      on_done(result)
    end
  end)
  return true
end

--- Locations from the server as `snot.Location`s.
---@param locations lsp.Location[]
---@return snot.Location[]
function M.to_locations(locations)
  local client = M.client()
  local items = vim.lsp.util.locations_to_items(locations, client and client.offset_encoding or "utf-16")
  return vim.tbl_map(function(item)
    return { path = item.filename, lnum = item.lnum, col = item.col, text = item.text }
  end, items)
end

return M
