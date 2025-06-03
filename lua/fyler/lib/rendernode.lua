local Text = require 'fyler.lib.text'
local algos = require 'fyler.algos'
local state = require 'fyler.state'
local luv = vim.uv or vim.loop
local node_count = 0

local function generate_node_meta_key()
  node_count = node_count + 1

  return string.format('/%d', node_count)
end

local function get_node_prefix(node)
  local mini_icons_status, mini_icons = pcall(require, 'mini.icons')
  if mini_icons_status then
    ---@diagnostic disable-next-line: undefined-field
    return mini_icons.get(node.type == 'directory' and 'directory' or 'file', node.path)
  end
end

---@class Fyler.RenderNode.Options
---@field name string
---@field type string
---@field path string
---@field revealed boolean

---@class Fyler.RenderNode : Fyler.RenderNode.Options
---@field meta_key string
---@field children Fyler.RenderNode[]
---@field parent? Fyler.RenderNode
local RenderNode = {}

---@param options Fyler.RenderNode.Options
---@return Fyler.RenderNode
function RenderNode.new(options)
  return setmetatable({}, {
    __index = RenderNode,
  }):init(options)
end

---@param options Fyler.RenderNode.Options
---@return Fyler.RenderNode
function RenderNode:init(options)
  for k, v in pairs(options or {}) do
    self[k] = v
  end

  self.children = {}
  self.revealed = options.revealed or false
  self.meta_key = generate_node_meta_key()
  state.meta_data[algos.extract_meta_key(self.meta_key)] = { name = self.name, type = self.type, path = self.path }
  state.render_node[self.path] = self

  return self
end

---@param child Fyler.RenderNode.Options
function RenderNode:add_child(child)
  table.insert(
    self.children,
    RenderNode.new(vim.tbl_deep_extend('force', child, {
      parent = self,
    }))
  )
end

function RenderNode:delete_node()
  if not self.parent then
    return
  end

  ---@param child Fyler.RenderNode
  self.parent.children = vim.tbl_filter(function(child)
    return child.path ~= self.path
  end, self.parent.children)
end

---@return integer
function RenderNode:get_depth()
  if not self.parent then
    return 0
  end

  return self.get_depth(self.parent) + 1
end

---@return { name: string, type: string, path: string }[]
function RenderNode:scan_dir()
  if not self.path then
    return {}
  end

  local items = {}
  local fs = luv.fs_scandir(self.path)
  if not fs then
    return {}
  end

  while true do
    local name, type = luv.fs_scandir_next(fs)
    if not name then
      break
    end

    table.insert(items, {
      name = name,
      type = type,
      path = string.format('%s/%s', self.path, name),
    })
  end

  return items
end

function RenderNode:get_equivalent_text()
  local indentation = self:get_depth() * 2
  local text = Text.new {}
  if self.revealed then
    local results = self:scan_dir()
    for _, result in ipairs(results) do
      if not self:find(result.path) then
        self:add_child(RenderNode.new(result))
      end
    end

    table.sort(self.children, function(a, b)
      if a.type == 'directory' and b.type == 'file' then
        return true
      elseif a.type == 'file' and b.type == 'directory' then
        return false
      else
        return a.name < b.name
      end
    end)

    for _, child in ipairs(self.children or {}) do
      local icon, hl = get_node_prefix(child)
      text
        :append(string.rep(' ', indentation), 'FylerBlank')
        :append(icon, hl)
        :append(' ', 'FylerBlank')
        :append(child.name, 'FylerParagraph')
        :append(' ', 'FylerBlank')
        :append(child.meta_key, 'FylerBlank')

      text = text:nl() + child:get_equivalent_text()
    end
  end

  return text
end

---@param path string
---@return Fyler.RenderNode|nil
function RenderNode:find(path)
  if self.path == path then
    return self
  end

  for _, child in ipairs(self.children or {}) do
    local found = child:find(path)
    if found then
      return found
    end
  end

  return nil
end

---@param path string
function RenderNode:toggle_reveal(path)
  local node = self:find(path)
  if node then
    node.revealed = not node.revealed
  end
end

---@param target_path string
---@return boolean success - true if the path was found and revealed, false otherwise
function RenderNode:reveal_path(target_path)
  -- Normalize paths to handle different formats
  local normalized_target = vim.fn.fnamemodify(target_path, ':p'):gsub('/$', '')
  local normalized_self = vim.fn.fnamemodify(self.path, ':p'):gsub('/$', '')

  -- If this is the target path, ensure it's revealed (if it's a directory)
  if normalized_self == normalized_target then
    if self.type == 'directory' then
      self.revealed = true
    end
    return true
  end

  -- If the target path doesn't start with our path, it's not under this node
  if not vim.startswith(normalized_target, normalized_self) then
    return false
  end

  -- This directory is on the path to the target, so reveal it
  if self.type == 'directory' then
    self.revealed = true

    -- Scan directory to ensure children are populated
    local results = self:scan_dir()
    for _, result in ipairs(results) do
      if not self:find(result.path) then
        self:add_child(RenderNode.new(result))
      end
    end

    -- Recursively reveal path in children
    for _, child in ipairs(self.children) do
      if child:reveal_path(target_path) then
        return true
      end
    end
  end

  return false
end

---@param file_path string
---@return boolean success - true if all parent directories were revealed, false otherwise
function RenderNode:reveal_file_path(file_path)
  -- Get the directory containing the file
  local parent_dir = vim.fn.fnamemodify(file_path, ':h')

  -- Reveal all parent directories leading to the file
  return self:reveal_path(parent_dir)
end

return RenderNode
