package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  "./?.lua",
  package.path,
}, ";")

local report = {
  suite = "render_integration",
  tests = {},
}

local function add_result(name, ok, detail)
  report.tests[#report.tests + 1] = {
    name = name,
    ok = ok,
    detail = detail,
  }
end

local function fail(message)
  error(message, 2)
end

local function assert_true(condition, message)
  if not condition then
    fail(message)
  end
end

local function run_test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    add_result(name, true, "ok")
    return
  end
  add_result(name, false, tostring(err))
end

local function wait_for(predicate, timeout_ms)
  local ok = vim.wait(timeout_ms, predicate, 10)
  return ok == true
end

local function has_extmark_with(bufnr, ns, predicate)
  local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { -1, -1 }, { details = true })
  for i = 1, #extmarks do
    local details = extmarks[i][4] or {}
    if predicate(details) then
      return true
    end
  end
  return false
end

local function run_suite()
  local cellmode = require("cellmode")
  local session_store = require("cellmode.runtime.session_store")
  local cell_layout = require("cellmode.view.cell_layout")
  local overlay = require("cellmode.view.overlay")

  cellmode.setup({})

  local tmpfile = vim.fn.tempname() .. ".csv"
  vim.fn.writefile({
    "name,age",
    "alice,7",
    "bob,10",
  }, tmpfile)

  vim.cmd("edit " .. vim.fn.fnameescape(tmpfile))

  local bufnr = vim.api.nvim_get_current_buf()
  local ns = overlay.namespace()

  run_test("session_opened", function()
    assert_true(session_store.get(bufnr) ~= nil, "session missing after open")
    local session = session_store.get(bufnr)
    assert_true(session.format == "csv", "format not detected")
  end)

  run_test("buffer_is_raw_csv", function()
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert_true(#lines == 3, "unexpected line count")
    assert_true(lines[1] == "name,age", "row 1 not raw CSV")
    assert_true(lines[2] == "alice,7", "row 2 not raw CSV")
  end)

  run_test("layout_built", function()
    local layout = cell_layout.get(bufnr)
    assert_true(layout ~= nil, "layout missing")
    assert_true(#layout.records == 3, "expected 3 records")
    assert_true(#layout.records[1].fields == 2, "expected 2 fields in row 1")
    assert_true(layout.records[2].fields[1].value == "alice", "field value mismatch")
  end)

  run_test("overlay_extmarks_placed", function()
    local has_pipe = has_extmark_with(bufnr, ns, function(d)
      if not d.virt_text then return false end
      for i = 1, #d.virt_text do
        if d.virt_text[i][2] == "CellmodePipe" then
          return true
        end
      end
      return false
    end)
    assert_true(has_pipe, "no CellmodePipe extmark placed")
  end)

  run_test("set_cell_updates_buffer", function()
    vim.cmd("Cellmode op set-cell 2 1 charlie")
    local line = vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1]
    assert_true(line == "charlie,7", "set-cell did not update raw csv: got " .. line)
  end)

  run_test("edit_triggers_relayout", function()
    vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { "z,100" })
    local relaid = wait_for(function()
      local layout = cell_layout.get(bufnr)
      return layout and layout.records[3] and layout.records[3].fields[1].value == "z"
    end, 1200)
    assert_true(relaid, "layout did not refresh after edit")
  end)

  run_test("toggle_overlay", function()
    vim.cmd("Cellmode toggle")
    local marks_after_off = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { -1, -1 }, {})
    assert_true(#marks_after_off == 0, "extmarks remained after toggle off")
    vim.cmd("Cellmode toggle")
    local marks_after_on = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { -1, -1 }, {})
    assert_true(#marks_after_on > 0, "extmarks not restored after toggle on")
  end)

  run_test("save_writes_raw_csv", function()
    vim.cmd("write")
    local lines = vim.fn.readfile(tmpfile)
    assert_true(lines[1] == "name,age", "saved header mismatch")
    assert_true(lines[2] == "charlie,7", "saved row 2 mismatch: " .. (lines[2] or ""))
    assert_true(lines[3] == "z,100", "saved row 3 mismatch: " .. (lines[3] or ""))
  end)

  pcall(vim.fn.delete, tmpfile)
end

run_suite()

local failed = false
for i = 1, #report.tests do
  if not report.tests[i].ok then
    failed = true
    break
  end
end

report.ok = not failed
print(vim.json.encode(report))

if failed then
  vim.cmd("cq")
else
  vim.cmd("qa!")
end
