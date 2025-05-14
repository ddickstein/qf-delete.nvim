local M = {}

local function errormsg(message)
  vim.api.nvim_echo({ { message, "ErrorMsg" } }, false, {})
end

local function getqf_and_setqf()
  local getqf, setqf = vim.fn.getqflist, vim.fn.setqflist
  if vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].loclist == 1 then
    getqf = function(...) return vim.fn.getloclist(0, ...) end
    setqf = function(...) return vim.fn.setloclist(0, ...) end
  end
  return getqf, setqf
end

local undo_stacks_by_buffer = {}

-- Purge state to avoid memory leaks.
local function purge_undo_stack()
  for bufnr, _ in pairs(undo_stacks_by_buffer) do
    if not vim.api.nvim_buf_is_valid(bufnr) then
      undo_stacks_by_buffer[bufnr] = 0
    end
  end
  local bufnr = vim.api.nvim_get_current_buf()
  local undo_stacks = undo_stacks_by_buffer[bufnr]
  if not undo_stacks then
    undo_stacks_by_buffer[bufnr] = {}
    return
  end
  local getqf = getqf_and_setqf()
  local active_ids = {}
  for nr = 1, getqf { nr = "$" }.nr do
    local id = getqf { nr = nr, id = 0 }.id
    active_ids[id] = true
  end
  for id, _ in pairs(undo_stacks) do
    if not active_ids[id] then
      undo_stacks[id] = nil
    end
  end
end

-- In the functions below we use `getcurpos` and `cursor` for best-effort cursor
-- placement as the quickfix list size changes.

local function delete_qf_entries(filter)
  local getqf, setqf = getqf_and_setqf()
  local qf = getqf { all = true }
  qf.nr = nil
  qf.idx = nil
  qf.changedtick = nil
  qf.size = nil
  local bufnr = vim.api.nvim_get_current_buf()
  local undo_stacks = undo_stacks_by_buffer[bufnr]
  local undo_stack = undo_stacks[qf.id]
  if not undo_stack then
    undo_stack = { idx = 1, stack = { vim.deepcopy(qf) } }
    undo_stacks[qf.id] = undo_stack
  end
  local filtered_items = {}
  for idx, item in ipairs(qf.items) do
    if filter(idx, item) then
      table.insert(filtered_items, item)
    end
  end
  qf.items = filtered_items
  undo_stack.stack = vim.list_slice(undo_stack.stack, 1, undo_stack.idx)
  table.insert(undo_stack.stack, vim.deepcopy(qf))
  undo_stack.idx = undo_stack.idx + 1
  local cursor = vim.fn.getcurpos()
  table.remove(cursor, 1) -- Remove bufnr
  setqf({}, "u", qf)
  vim.fn.cursor(cursor)
end

local function undo_or_redo(operation)
  local bufnr = vim.api.nvim_get_current_buf()
  local getqf, setqf = getqf_and_setqf()
  local id = getqf { id = 0 }.id
  local undo_stack = undo_stacks_by_buffer[bufnr][id]
  if operation == "undo"
      and (not undo_stack or undo_stack.idx == 1)
  then
    errormsg("Nothing to undo.")
    return
  elseif operation == "redo"
      and (not undo_stack or undo_stack.idx == #(undo_stack.stack))
  then
    errormsg("Nothing to redo.")
    return
  end
  print("")
  if operation == "undo" then
    undo_stack.idx = undo_stack.idx - 1
  elseif operation == "redo" then
    undo_stack.idx = undo_stack.idx + 1
  else
    -- Should not arise in practice.
    error("Unknown operation: " .. operation)
  end
  local qf = undo_stack.stack[undo_stack.idx]
  local cursor = vim.fn.getcurpos()
  table.remove(cursor, 1) -- Remove bufnr
  setqf({}, "u", qf)
  vim.fn.cursor(cursor)
end

local function delete_qf_entries_in_range(start_row, end_row)
  local function filter(index, _)
    return index < start_row or index > end_row
  end
  delete_qf_entries(filter)
end

function M.delete_qf_entries_opfunc(motionwise)
  if motionwise ~= "line" then
    errormsg("Entries can only be deleted with linewise motions.")
    return
  end
  local start_op_pos = vim.api.nvim_buf_get_mark(0, "[")
  local end_op_pos = vim.api.nvim_buf_get_mark(0, "]")
  local start_row = start_op_pos[1]
  local end_row = end_op_pos[1]
  delete_qf_entries_in_range(start_row, end_row)
end

function M.on_filetype()
  purge_undo_stack() -- The filetype event is triggered on each qf window open.
  vim.keymap.set("n", "d", function()
      vim.o.operatorfunc = "v:lua.require'qf-delete'.delete_qf_entries_opfunc"
      return "g@"
    end,
    { desc = "Delete entries", buffer = true, expr = true })
  vim.keymap.set("o", "d", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    delete_qf_entries_in_range(row, row + vim.v.count1 - 1)
    return "<Esc>"
  end, { desc = "Delete entries", buffer = true, expr = true })
  vim.keymap.set("x", "d", function()
    local mode = vim.api.nvim_get_mode().mode
    if mode ~= "V" then
      errormsg("Entries can only be deleted with linewise motions.")
      return
    end
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    local other_end_row = vim.fn.getpos("v")[2]
    local start_row = math.min(cursor_row, other_end_row)
    local end_row = math.max(cursor_row, other_end_row)
    delete_qf_entries_in_range(start_row, end_row)
    return "<Esc>"
  end, { desc = "Delete entries", buffer = true, expr = true })
  vim.keymap.set("n", "u", function() undo_or_redo("undo") end,
    { desc = "Undo deletion", buffer = true })
  vim.keymap.set("n", "<C-r>", function() undo_or_redo("redo") end,
    { desc = "Redo deletion", buffer = true })
  local is_loclist =
      vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].loclist == 1
  local filter_cmd = is_loclist and "Lfilter" or "Cfilter"
  vim.api.nvim_buf_create_user_command(0, filter_cmd, function(opts)
    local pattern = opts.args
    local invert_filter = opts.bang
    local first_char = pattern:sub(1, 1)
    local last_char = pattern:sub(-1)
    if first_char == last_char
        and (first_char == "/" or first_char == '"' or first_char == "'")
    then
      pattern = pattern:sub(2, -2)
    end
    local function item_matches(item)
      local text_matches = vim.fn.match(item.text, pattern) >= 0
      if text_matches then
        return true
      end
      local bufnr = item.bufnr
      if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
        local bufname = vim.api.nvim_buf_get_name(item.bufnr)
        local filename_matches = vim.fn.match(bufname, pattern) >= 0
        if filename_matches then
          return true
        end
      end
      return false
    end
    local function filter(_, item)
      return item_matches(item) == not invert_filter
    end
    delete_qf_entries(filter)
  end, { desc = "Filter entries", bang = true, nargs = "+" })
end

return M
