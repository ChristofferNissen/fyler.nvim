---@alias Fyler.Text.Word { str: string, hl: string }
---@alias Fyler.Text.Line { words: Fyler.Text.Word[] }

---@class Fyler.Text.Options
---@field left_margin? integer

---@class Fyler.Text : Fyler.Text.Options
---@field lines Fyler.Text.Line[]
local Text = {}

---@param options? Fyler.Text.Options
---@return Fyler.Text
function Text.new(options)
  return setmetatable({}, {
    __index = Text,
    __add = function(t1, t2)
      if #t1.lines == 0 then
        return t2
      end

      if #t2.lines == 0 then
        return t1
      end

      local result = Text.new {}
      result.lines = {}
      for _, line in ipairs(t1.lines) do
        table.insert(result.lines, line)
      end

      for _, word in ipairs(t2.lines[1].words) do
        table.insert(result.lines[#result.lines].words, word)
      end

      for i = 2, #t2.lines do
        table.insert(result.lines, t2.lines[i])
      end

      return result
    end,
  }):init(options)
end

---@param options? Fyler.Text.Options
---@return Fyler.Text
function Text:init(options)
  options = options or {}
  self.left_margin = options.left_margin or 0
  self.lines = { { words = {} } }

  return self
end

---@param count? integer
---@return Fyler.Text
function Text:nl(count)
  for _ = 1, (count or 1) do
    table.insert(self.lines, { words = {} })
  end

  return self
end

---@param str string
---@param hl string
---@return Fyler.Text
function Text:append(str, hl)
  table.insert(self.lines[#self.lines].words, { str = str, hl = hl })

  return self
end

---@return Fyler.Text
function Text:remove_trailing_empty_lines()
  while #self.lines >= 1 and vim.tbl_isempty(self.lines[#self.lines].words) do
    table.remove(self.lines)
  end

  return self
end

---@param bufnr integer
function Text:render(bufnr)
  local ns = require('fyler.config').values.namespace
  local start_line = 0
  if not (bufnr and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end

  local was_modifiable = vim.bo[bufnr].modifiable
  if not was_modifiable then
    vim.bo[bufnr].modifiable = true
  end

  local virt_lines = {}
  for _, line in ipairs(self.lines) do
    local text = string.rep(' ', self.left_margin)
    for _, word in ipairs(line.words) do
      text = text .. word.str
    end
    table.insert(virt_lines, text)
  end

  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, virt_lines)
  vim.api.nvim_buf_clear_namespace(bufnr, ns.highlights, 0, -1)
  for i, line in ipairs(self.lines) do
    local col = self.left_margin
    for _, segment in ipairs(line.words) do
      if segment.hl and segment.hl ~= '' then
        vim.api.nvim_buf_set_extmark(bufnr, ns.highlights, start_line + i - 1, col, {
          end_col = col + #segment.str,
          hl_group = segment.hl,
        })
      end
      col = col + #segment.str
    end
  end

  if not was_modifiable then
    vim.bo[bufnr].modifiable = false
  end
end

return Text
