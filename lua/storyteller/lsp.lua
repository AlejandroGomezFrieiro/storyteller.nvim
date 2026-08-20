-- storyteller.lsp
-- Thin client for the storyteller-lsp `workspace/executeCommand` automation
-- bus. Commands prefer the LSP path when a storyteller client is attached and
-- fall back to the in-process Lua implementation otherwise.

local M = {}

M.client = function()
  for _, client in ipairs(vim.lsp.get_clients()) do
    if client.name == "storyteller" then
      return client
    end
  end
  return nil
end

M.available = function()
  return M.client() ~= nil
end

-- Run a storyteller command. Heavy commands (compile/manuscript) dispatch
-- asynchronously and deliver through `cb(result)`; everything else is
-- synchronous. Returns the result value (or nil, err on failure).
M.command = function(name, args, cb)
  local client = M.client()
  if not client then
    return nil, "no storyteller client attached"
  end
  if name == "storyteller.compile" or name == "storyteller.manuscript" then
    client:request("workspace/executeCommand", { command = name, arguments = args or {} }, function(err, result)
      if cb then
        cb(err and nil or result, err)
      end
    end)
    return true
  end
  local ok, res = pcall(client.request_sync, client, "workspace/executeCommand", {
    command = name,
    arguments = args or {},
  }, 3000, 0)
  if not ok then
    return nil, tostring(res)
  end
  local err = res and res[1]
  local result = res and res[2]
  if err then
    return nil, tostring(err)
  end
  return result
end

return M
