--
--  __  __ _                                                    _
-- |  \/  (_)_ __   ___  _____      _____  ___ _ __   ___ _ __| |
-- | |\/| | | '_ \ / _ \/ __\ \ /\ / / _ \/ _ \ '_ \ / _ \ '__| |
-- | |  | | | | | |  __/\__ \\ V  V /  __/  __/ |_) |  __/ |  |_|
-- |_|  |_|_|_| |_|\___||___/ \_/\_/ \___|\___| .__/ \___|_|  (_)
--                                             |_|
--[[---------------------------------------------------------------------------
  Minesweeper
  Classic Minesweeper for grandMA3.
  Click cells to reveal them. Use "Mark Cell" to place flags.
  Clicking a revealed number whose neighbors are fully flagged chord-reveals.
  Mines are placed after the first click — the first reveal is always safe.

  Author:   t-60
  Version:  1.0.0
  GMA3:     tested on 2.3.2.0
  GitHub:   https://github.com/tminus60/GrandMA3-Plugins
  License:  t-60 Plugin License (Non-Commercial) — see bottom of file
---------------------------------------------------------------------------]]

local pluginVersion = "1.0.0"

-- ── t-60 Crash Reporter ── 
local _T60_WEBHOOK   = "https://discord.com/api/webhooks/1507368948876837085/FqeuJCUYmpebjQlDC9GlrjD3d5JjB3V_z98WUNHHUeyrP3e6bIDdAOi46Nu5-qWCNJSj"
local _T60_PLUGIN_ID = "minesweeper"
-- ─────────────────────────────────────────────────────────────

-- ── t-60 Update Checker ──
local _T60_UPDATE_URL = "https://raw.githubusercontent.com/tminus60/GrandMA3-Plugins/master/Games/Minesweeper/version.txt"
-- ─────────────────────────────────────────────────────────────

local pluginName  = select(1, ...)
local signalTable = select(3, ...)
local my_handle   = select(4, ...)

local fct   = {}
local dialog

--------------------------------------------------------------------------------
-- Difficulty presets
--------------------------------------------------------------------------------
local DIFFS = {
    {label="Easy",   rows=9,  cols=9,  mines=10, cell=58, bonusMul=5},
    {label="Medium", rows=16, cols=16, mines=40, cell=46, bonusMul=10},
    {label="Hard",   rows=16, cols=30, mines=99, cell=36, bonusMul=20},
}
local diffIdx = 1

local MAX_ROWS = 16
local MAX_COLS = 30

--------------------------------------------------------------------------------
-- Colours
--------------------------------------------------------------------------------
local C_TITLEBAR, C_HIDDEN, C_REVEALED
local C_ORANGE, C_GREEN, C_RED, C_BLUE, C_PURPLE, C_DIM
local NUM_COLORS

--------------------------------------------------------------------------------
-- Board state
--------------------------------------------------------------------------------
local board, cells
local ROWS, COLS, MINES, CELL_SIZE
local gameState   -- "idle" | "playing" | "won" | "lost"
local firstClick, flagMode, flagCount
local timerSecs, gameTimerHandle
local score, highscores
local revealedCount  -- tracks revealed non-mine cells for win detection

local function inBounds(r, c) return r >= 1 and r <= ROWS and c >= 1 and c <= COLS end

local function hiKey() return "ms_hi_" .. DIFFS[diffIdx].label end

local function loadHighscore()
    local v = 0
    pcall(function() v = tonumber(GetVar(GlobalVars(), hiKey())) or 0 end)
    return v
end

local function saveHighscore(s)
    pcall(function() SetVar(GlobalVars(), hiKey(), tostring(s)) end)
end

local function initBoard()
    local d    = DIFFS[diffIdx]
    ROWS       = d.rows; COLS = d.cols; MINES = d.mines; CELL_SIZE = d.cell
    board      = {}
    for r = 1, ROWS do
        board[r] = {}
        for c = 1, COLS do
            board[r][c] = {mine=false, revealed=false, flagged=false, count=0}
        end
    end
    gameState    = "idle"
    firstClick   = true
    flagMode     = false
    flagCount    = 0
    timerSecs    = 0
    score        = 0
    revealedCount = 0
    if not highscores then highscores = {} end
    highscores[diffIdx] = highscores[diffIdx] or loadHighscore()
end

local function placeMines(safeR, safeC)
    math.randomseed(os.time())
    local placed = 0
    while placed < MINES do
        local r = math.random(1, ROWS)
        local c = math.random(1, COLS)
        if not board[r][c].mine then
            local isSafe = false
            for dr = -1, 1 do
                for dc = -1, 1 do
                    if r == safeR+dr and c == safeC+dc then isSafe = true end
                end
            end
            if not isSafe then board[r][c].mine = true; placed = placed + 1 end
        end
    end
    for r = 1, ROWS do
        for c = 1, COLS do
            if not board[r][c].mine then
                local cnt = 0
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if not (dr==0 and dc==0) and inBounds(r+dr,c+dc) and board[r+dr][c+dc].mine then
                            cnt = cnt + 1
                        end
                    end
                end
                board[r][c].count = cnt
            end
        end
    end
end

local function cellColor(r, c)
    local cell = board[r][c]
    if not cell.revealed then return cell.flagged and C_ORANGE or C_HIDDEN end
    if cell.mine then return C_RED end
    return cell.count > 0 and (NUM_COLORS[cell.count] or C_REVEALED) or C_REVEALED
end

local function cellText(r, c)
    local cell = board[r][c]
    if not cell.revealed then return "" end
    if cell.mine then return "" end
    return cell.count > 0 and tostring(cell.count) or ""
end

local function cellIcon(r, c)
    local cell = board[r][c]
    if not cell.revealed then return cell.flagged and "message_center_warning" or "" end
    if cell.mine then return "cancel" end
    return ""
end

local function updateCellUI(r, c)
    if not (cells and cells[r] and cells[r][c]) then return end
    pcall(function()
        local btn = cells[r][c]
        btn.Text      = cellText(r, c)
        btn.Icon      = cellIcon(r, c)
        btn.BackColor = cellColor(r, c)
    end)
end

local function updateInfoBar()
    if not dialog then return end
    pcall(function()
        if dialog.scoreLbl     then dialog.scoreLbl.Text     = "Score: " .. tostring(score) end
        if dialog.highscoreLbl then dialog.highscoreLbl.Text = "My Highscore: " .. tostring(highscores[diffIdx] or 0) end
    end)
end

local function cancelGameTimer()
    if gameTimerHandle then
        pcall(function() gameTimerHandle:Cancel() end)
        gameTimerHandle = nil
    end
end

local function checkWin()
    if revealedCount < ROWS * COLS - MINES then return end
    gameState = "won"
    cancelGameTimer()
    -- Flag remaining mines + win bonus
    for r = 1, ROWS do
        for c = 1, COLS do
            if board[r][c].mine and not board[r][c].flagged then
                board[r][c].flagged = true; updateCellUI(r, c)
            end
        end
    end
    local bonus = math.max(0, 999 - timerSecs) * DIFFS[diffIdx].bonusMul
    score = score + bonus
    if score > (highscores[diffIdx] or 0) then
        highscores[diffIdx] = score
        saveHighscore(score)
    end
    updateInfoBar()
    pcall(function() if dialog and dialog.markBtn then dialog.markBtn.Text = ":D  You Win!" end end)
end

local function onGameOver()
    gameState = "lost"
    cancelGameTimer()
    for r = 1, ROWS do
        for c = 1, COLS do
            if board[r][c].mine then board[r][c].revealed = true; updateCellUI(r, c) end
        end
    end
    pcall(function() if dialog and dialog.markBtn then dialog.markBtn.Text = "X_X  Game Over" end end)
    pcall(function()
        if dialog and dialog.scoreLbl then
            dialog.scoreLbl.Text     = "Score: " .. tostring(score) .. "  —  tap to restart"
            dialog.scoreLbl.HasHover = "Yes"
            dialog.scoreLbl.BackColor = C_ORANGE
        end
    end)
end

local function revealFlood(startR, startC)
    local queue   = {{startR, startC}}
    local visited = {}
    local function key(r, c) return r * 100 + c end
    visited[key(startR, startC)] = true
    local head = 1
    while head <= #queue do
        local r, c = queue[head][1], queue[head][2]; head = head + 1
        if inBounds(r, c) then
            local cell = board[r][c]
            if not cell.revealed and not cell.flagged then
                cell.revealed = true
                if cell.mine then updateCellUI(r, c); onGameOver(); return end
                score = score + 10
                revealedCount = revealedCount + 1
                updateCellUI(r, c)
                if cell.count == 0 then
                    for dr = -1, 1 do
                        for dc = -1, 1 do
                            if not (dr==0 and dc==0) then
                                local nr, nc = r+dr, c+dc
                                local k = key(nr, nc)
                                if inBounds(nr,nc) and not visited[k] and not board[nr][nc].revealed then
                                    visited[k] = true; table.insert(queue, {nr, nc})
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    checkWin()
end

local function handleCellClick(r, c)
    if gameState == "lost" or gameState == "won" then return end
    local cell = board[r][c]

    if flagMode then
        if cell.revealed then return end
        cell.flagged = not cell.flagged
        flagCount    = flagCount + (cell.flagged and 1 or -1)
        updateCellUI(r, c)
        return
    end

    if cell.flagged then return end

    if cell.revealed then
        if cell.count > 0 then
            local adjFlags = 0
            for dr = -1, 1 do
                for dc = -1, 1 do
                    if not (dr==0 and dc==0) and inBounds(r+dr,c+dc) and board[r+dr][c+dc].flagged then
                        adjFlags = adjFlags + 1
                    end
                end
            end
            if adjFlags == cell.count then
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if not (dr==0 and dc==0) and inBounds(r+dr,c+dc) then
                            local nb = board[r+dr][c+dc]
                            if not nb.flagged and not nb.revealed then
                                revealFlood(r+dr, c+dc)
                                if gameState == "lost" then return end
                            end
                        end
                    end
                end
                updateInfoBar()
            end
        end
        return
    end

    if firstClick then
        firstClick = false
        placeMines(r, c)
        gameState = "playing"
        gameTimerHandle = Timer(function()
            if gameState ~= "playing" then return false end
            local alive = false
            pcall(function() local _ = dialog.win.Name; alive = true end)
            if not alive then cancelGameTimer(); return false end
            timerSecs = math.min(timerSecs + 1, 999)
        end, 1, 1)
    end

    revealFlood(r, c)
    updateInfoBar()
end

--------------------------------------------------------------------------------
-- Crash Handler
--------------------------------------------------------------------------------
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- t-60 Crash Reporter  ·  copy-paste block (nicht ändern)
local function _t60Str(s)
    return '"' .. tostring(s or "")
        :gsub('\\','\\\\'):gsub('"','\\"')
        :gsub('\n','\\n'):gsub('\r',''):gsub('\t','  ') .. '"'
end
local function _t60SendCrash(version, err, logPath)
    if not _T60_WEBHOOK or _T60_WEBHOOK == "" then return end
    pcall(function()
        local gma = ""; pcall(function() gma = string.format("Software version: %s", Version()) end)
        local msg = "**[" .. _T60_PLUGIN_ID .. "  v" .. tostring(version) .. "  —  CRASH]**\n"
            .. "```\n"
            .. "Plugin:  " .. _T60_PLUGIN_ID .. " v" .. tostring(version) .. "\n"
            .. "Fehler:  " .. tostring(err)                            .. "\n"
            .. "GMA3:    " .. gma                                       .. "\n"
            .. "OS:      " .. HostOS()                                  .. "\n"
            .. "Zeit:    " .. os.date("%Y-%m-%d %H:%M:%S")              .. "\n"
            .. "```"
        local tmp = GetPath(Enums.PathType.Temp)
        local uid = tostring(os.clock()):gsub("%.", "")
        if HostOS() == "Windows" then
            local tmpW = tmp:gsub("/","\\")
            local jf   = tmpW .. "\\t60_crash_" .. uid .. ".json"
            local bat  = tmpW .. "\\t60_crash_" .. uid .. ".bat"
            local lp   = logPath:gsub("/","\\")
            local fw = io.open(jf, "w")
            if fw then fw:write('{"content":' .. _t60Str(msg) .. '}'); fw:close() end
            local fb = io.open(bat, "w")
            if fb then
                fb:write("@echo off\r\n")
                fb:write('curl -sf -X POST -F "payload_json=<' .. jf .. '" -F "files[0]=@' .. lp .. '" "' .. _T60_WEBHOOK .. '"\r\n')
                fb:close()
            end
            os.execute('start /b cmd /c ""' .. bat .. '""')
        else
            local jf = tmp .. "/t60_crash_" .. uid .. ".json"
            local fw = io.open(jf, "w")
            if fw then fw:write('{"content":' .. _t60Str(msg) .. '}'); fw:close() end
            os.execute('curl -sf -X POST'
                .. ' -F "payload_json=<' .. jf .. '"'
                .. ' -F "files[0]=@' .. logPath .. '"'
                .. ' "' .. _T60_WEBHOOK .. '"'
                .. ' >/dev/null 2>&1 ; true')
        end
    end)
end
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local function crashHandler(err)
    local path = GetPath(Enums.PathType.Temp) .. "/" .. pluginName .. "_crash.log"
    local f = io.open(path, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. "v" .. pluginVersion .. " | " .. tostring(err) .. "\n")
        f:close()
    end
    Printf("[ERROR] " .. pluginName .. ": " .. tostring(err))
    _t60SendCrash(pluginVersion, err, path)
    MessageBox({
        title = "Plugin Error — " .. pluginName, backColor = "Global.Focus",
        titleTextColor = "Global.Text",
        message = pluginName .. " v" .. pluginVersion .. " encountered an error.\n\n"
            .. tostring(err) .. "\n\nCrash log: " .. path,
        commands = {{value = 0, name = "Close"}},
    })
end

local function safe(fn)
    return function(caller, ...)
        local ok, err = pcall(fn, caller, ...)
        if not ok then crashHandler(err) end
    end
end

--------------------------------------------------------------------------------
-- Update Checker
--------------------------------------------------------------------------------
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- t-60 Update Checker  ·  copy-paste block (nicht ändern)
local _t60UpdateWin = nil
local function _t60ShowUpdate(latest)
    if _t60UpdateWin then return end
    local ov; pcall(function()
        local idx = 1
        pcall(function() local d = GetFocusDisplay(); idx = Obj.Index(d) end)
        if idx < 1 or idx > 5 then idx = 1 end
        ov = GetDisplayByIndex(idx).ScreenOverlay
    end)
    if not ov then return end
    local win = ov:Append("BaseInput")
    win.Name = "Update Available"; win.W = 520; win.H = 300
    win.Rows = 2; win.Columns = 1
    win[1][1].SizePolicy = "Fixed"; win[1][1].Size = 40
    win[1][2].SizePolicy = "Stretch"
    win.AutoClose = "No"; win.CloseOnEscape = "Yes"
    local tb = win:Append("TitleBar")
    tb.Columns = 2; tb.Rows = 1; tb.Anchors = "0,0"; tb.Texture = "corner2"
    tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "50"
    local ttl = tb:Append("TitleButton")
    ttl.Text = "Update Available"; ttl.Texture = "corner1"; ttl.Anchors = "0,0"
    local cls = tb:Append("CloseButton"); cls.Anchors = "1,0"; cls.Texture = "corner2"
    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"; fr.Columns = 1; fr.Rows = 2
    fr[1][1].SizePolicy = "Stretch"; fr[1][2].SizePolicy = "Fixed"; fr[1][2].Size = "55"
    local msg = fr:Append("UIObject"); msg.Anchors = "0,0"
    msg.Text = _T60_PLUGIN_ID .. " " .. latest .. " is available.\n"
             .. "You are running v" .. pluginVersion .. ".\n\n"
             .. "Download at:\ngithub.com/tminus60/GrandMA3-Plugins"
    msg.Font = "Medium20"; msg.TextalignmentH = "Center"
    msg.TextalignmentV = "Center"; msg.HasHover = "No"
    local br = fr:Append("UILayoutGrid"); br.Anchors = "0,1"; br.Columns = 2; br.Rows = 1
    local okBtn = br:Append("Button"); okBtn.Anchors = "0,0"; okBtn.Text = "OK"
    okBtn.Font = "Medium20"; okBtn.Textshadow = 1; okBtn.HasHover = "Yes"; okBtn.TextalignmentH = "Centre"
    okBtn.BackColor = Root().ColorTheme.ColorGroups.Global.PartlySelected
    okBtn.PluginComponent = my_handle; okBtn.Clicked = "_T60UpdateClose"
    local skipBtn = br:Append("Button"); skipBtn.Anchors = "1,0"; skipBtn.Text = "Don't show again for v" .. latest
    skipBtn.Font = "Medium20"; skipBtn.Textshadow = 1; skipBtn.HasHover = "Yes"; skipBtn.TextalignmentH = "Centre"
    skipBtn.BackColor = Root().ColorTheme.ColorGroups.Global.Focus
    skipBtn.PluginComponent = my_handle; skipBtn.Clicked = "_T60UpdateSkip"
    _t60UpdateWin = {win=win, overlay=ov, skipVersion=latest}
end
local function _t60CheckUpdate()
    if not _T60_UPDATE_URL or _T60_UPDATE_URL == "" then return end
    local tmp = GetPath(Enums.PathType.Temp)
    local uid  = tostring(os.clock()):gsub("%.", "")
    local out  = tmp .. "/t60_upd_" .. uid .. ".txt"
    local done = tmp .. "/t60_upd_" .. uid .. "_done.txt"
    if HostOS() == "Windows" then
        local outW  = out:gsub("/","\\")
        local doneW = done:gsub("/","\\")
        local bat   = tmp:gsub("/","\\") .. "\\t60_upd_" .. uid .. ".bat"
        local f = io.open(bat, "w"); if not f then return end
        f:write("@echo off\r\n")
        f:write('curl -sf --max-time 10 "' .. _T60_UPDATE_URL .. '" -o "' .. outW .. '"\r\n')
        f:write('echo done>"' .. doneW .. '"\r\n')
        f:close()
        os.execute('start /b cmd /c ""' .. bat .. '""')
    else
        os.execute('curl -sf --max-time 10 "' .. _T60_UPDATE_URL .. '" -o "' .. out .. '"'
            .. ' ; echo done > "' .. done .. '" &')
    end
    local checked = false
    Timer(function()
        pcall(function()
            if checked then return end
            local f = io.open(done, "r"); if not f then return end
            f:close(); checked = true
            local fv = io.open(out, "r")
            local latest = fv and fv:read("*a") or ""; if fv then fv:close() end
            latest = latest:match("^%s*(.-)%s*$")
            if latest == "" then return end
            if latest == pluginVersion then
                Printf("[" .. _T60_PLUGIN_ID .. "] v" .. pluginVersion .. " — up to date.")
                return
            end
            local function vn(v)
                local a,b,c = v:match("^(%d+)%.(%d+)%.?(%d*)")
                return (tonumber(a) or 0)*10000 + (tonumber(b) or 0)*100 + (tonumber(c) or 0)
            end
            if vn(latest) > vn(pluginVersion) then
                local skipped = ""
                pcall(function() skipped = GetVar(GlobalVars(), "t60_skip_" .. _T60_PLUGIN_ID) or "" end)
                if skipped ~= "" and vn(skipped) >= vn(latest) then return end
                pcall(_t60ShowUpdate, latest)
            end
        end)
    end, 4, 2)
end
signalTable._T60UpdateClose = function()
    pcall(function()
        if _t60UpdateWin then
            Obj.Delete(_t60UpdateWin.overlay, Obj.Index(_t60UpdateWin.win))
            _t60UpdateWin = nil
        end
    end)
end
signalTable._T60UpdateSkip = function()
    pcall(function()
        if _t60UpdateWin then
            SetVar(GlobalVars(), "t60_skip_" .. _T60_PLUGIN_ID, _t60UpdateWin.skipVersion)
            Obj.Delete(_t60UpdateWin.overlay, Obj.Index(_t60UpdateWin.win))
            _t60UpdateWin = nil
        end
    end)
end
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------
local function main()
    C_TITLEBAR = Root().ColorTheme.ColorGroups.PoolWindow.Bitmaps
    C_ORANGE   = Root().ColorTheme.ColorGroups.Global.PartlySelected
    C_GREEN    = Root().ColorTheme.ColorGroups.Button.BackgroundPlease
    C_RED      = Root().ColorTheme.ColorGroups.Button.BackgroundClear
    C_BLUE     = Root().ColorTheme.ColorGroups.Assignment.Group
    C_PURPLE   = Root().ColorTheme.ColorGroups.NumericInput.SoundValueBackground
    C_DIM      = Root().ColorTheme.ColorGroups.Global.Focus
    C_HIDDEN   = Root().ColorTheme.ColorGroups.Beat.DisabledBeat
    C_REVEALED = Root().ColorTheme.ColorGroups.Global.Default
    C_ORANGE     = Root().ColorTheme.ColorGroups.Global.PartlySelected
    C_RED     = Root().ColorTheme.ColorGroups.Button.BackgroundClear

    NUM_COLORS = {C_BLUE, C_GREEN, C_RED, C_PURPLE, C_RED, C_BLUE, C_DIM, C_DIM}

    local shortcuts = CurrentProfile().KeyboardShortCuts
    shortcuts.KeyboardShortcutsActive = false

    highscores = {}
    initBoard()
    dialog = fct.buildGameWindow()
    pcall(_t60CheckUpdate)
end

--------------------------------------------------------------------------------
-- UI builder
--------------------------------------------------------------------------------
function fct.buildGameWindow()
    local result = {}
    local display = GetDisplayByIndex(1)
    local overlay = display.ScreenOverlay
    result.display = display; result.overlay = overlay

    local boardW = COLS * CELL_SIZE
    local boardH = ROWS * CELL_SIZE
    local winW   = math.max(boardW, 400)  -- minimum width so info bar fits
    local winH   = 40 + 50 + boardH   -- titlebar + info bar + board

    local win = overlay:Append("BaseInput")
    win.Name = "Minesweeper"; win.W = winW; win.H = winH
    win.Rows = 2; win.Columns = 1
    win[1][1].SizePolicy = "Fixed"; win[1][1].Size = "40"
    win[1][2].SizePolicy = "Stretch"
    win.AutoClose = "No"; win.CloseOnEscape = "Yes"
    result.win = win

    -- TitleBar: [icon 40 | title stretch | settings 50 | close 50]
    local tb = win:Append("TitleBar")
    tb.Columns = 4; tb.Rows = 1; tb.Anchors = "0,0"; tb.Texture = "corner2"
    tb.BackColor = C_TITLEBAR
    tb[2][1].SizePolicy = "Fixed"; tb[2][1].Size = "40"
    tb[2][3].SizePolicy = "Fixed"; tb[2][3].Size = "50"
    tb[2][4].SizePolicy = "Fixed"; tb[2][4].Size = "50"

    local ico = tb:Append("AppearancePreview")
    ico.Anchors = "0,0"; ico.W = "40"; ico.BackColor = C_TITLEBAR
    pcall(function()
        local app = GetObject("Appearance tsixtyLogo")
        if app then ico.Appearance = app end
        ico.Texture = "corner1"
    end)

    local ttl = tb:Append("TitleButton")
    ttl.Text = "Minesweeper"; ttl.Texture = "corner0"
    ttl.Anchors = "1,0"; ttl.BackColor = C_TITLEBAR

    local settingsBtn = tb:Append("Button")
    settingsBtn.Anchors = "2,0"; settingsBtn.Icon = "settings"
    settingsBtn.HasHover = "Yes"; settingsBtn.Texture = "corner0"; settingsBtn.BackColor = C_TITLEBAR
    settingsBtn.PluginComponent = my_handle; settingsBtn.Clicked = "MsOpenSettings"

    local cls = tb:Append("CloseButton")
    cls.Anchors = "3,0"; cls.Texture = "corner2"; cls.BackColor = C_TITLEBAR

    -- Content: info bar | board
    local content = win:Append("DialogFrame")
    content.H = "100%"; content.W = "100%"; content.Anchors = "0,1"
    content.Rows = 2; content.Columns = 1
    content[1][1].SizePolicy = "Fixed"; content[1][1].Size = "50"
    content[1][2].SizePolicy = "Fixed"; content[1][2].Size = tostring(boardH)

    -- Info bar: [Mark Cell | Score: XXXX | My Highscore: XXXX]
    local info = content:Append("UILayoutGrid")
    info.Anchors = "0,0"; info.Columns = 3; info.Rows = 1
    info[2][1].SizePolicy = "Fixed"; info[2][1].Size = "150"
    info[2][3].SizePolicy = "Fixed"; info[2][3].Size = "190"

    local markBtn = info:Append("Button")
    markBtn.Anchors = "0,0"; markBtn.Text = "Mark Cell"
    markBtn.Font = "Medium20"; markBtn.Textshadow = 1; markBtn.HasHover = "Yes"
    markBtn.TextalignmentH = "Centre"; markBtn.BackColor = C_DIM
    markBtn.PluginComponent = my_handle; markBtn.Clicked = "MsFlagMode"
    result.markBtn = markBtn

    local scoreLbl = info:Append("Button")
    scoreLbl.Anchors = "1,0"; scoreLbl.Text = "Score: 0"
    scoreLbl.Font = "Medium20"; scoreLbl.Textshadow = 1; scoreLbl.HasHover = "No"
    scoreLbl.TextalignmentH = "Centre"
    scoreLbl.PluginComponent = my_handle; scoreLbl.Clicked = "MsScoreClick"
    result.scoreLbl = scoreLbl

    local highscoreLbl = info:Append("UIObject")
    highscoreLbl.Anchors = "2,0"
    highscoreLbl.Text = "My Highscore: " .. tostring(highscores[diffIdx] or 0)
    highscoreLbl.Font = "Medium20"; highscoreLbl.TextalignmentH = "Center"
    highscoreLbl.TextalignmentV = "Center"; highscoreLbl.HasHover = "No"
    result.highscoreLbl = highscoreLbl

    -- Board grid
    local boardGrid = content:Append("UILayoutGrid")
    boardGrid.Anchors = "0,1"; boardGrid.Columns = COLS; boardGrid.Rows = ROWS
    boardGrid.W = "100%"; boardGrid.H = "100%"
    for c = 1, COLS do
        boardGrid[2][c].SizePolicy = "Fixed"; boardGrid[2][c].Size = tostring(CELL_SIZE)
    end
    for r = 1, ROWS do
        boardGrid[1][r].SizePolicy = "Fixed"; boardGrid[1][r].Size = tostring(CELL_SIZE)
    end

    cells = {}
    for r = 1, ROWS do
        cells[r] = {}
        for c = 1, COLS do
            local btn = boardGrid:Append("Button")
            btn.Anchors = tostring(c-1) .. "," .. tostring(r-1)
            btn.Text = ""; btn.HasHover = "Yes"; btn.Textshadow = 1
            btn.Font = "Medium20"; btn.TextalignmentH = "Centre"
            btn.BackColor = C_HIDDEN; btn.Margin = "2,2,2,2"
            btn.PluginComponent = my_handle
            btn.Clicked = "Ms_" .. r .. "_" .. c
            cells[r][c] = btn
        end
    end

    dialog = result
    return result
end

function fct.buildSettingsDialog()
    if dialog.settingsWin then
        local alive = false
        pcall(function() local _ = dialog.settingsWin.win.Name; alive = true end)
        if alive then return end
        dialog.settingsWin = nil
    end
    local display = GetDisplayByIndex(1)
    local overlay = display.ScreenOverlay
    local s = {}; s.display = display; s.overlay = overlay

    local win = overlay:Append("BaseInput")
    win.Name = "Minesweeper — Settings"; win.W = 400; win.H = 320
    win.Rows = 2; win.Columns = 1
    win[1][1].SizePolicy = "Fixed"; win[1][1].Size = "40"
    win[1][2].SizePolicy = "Stretch"
    win.AutoClose = "No"; win.CloseOnEscape = "Yes"
    win.BackColor = C_TITLEBAR
    s.win = win

    local tb = win:Append("TitleBar")
    tb.Columns = 2; tb.Rows = 1; tb.Anchors = "0,0"; tb.Texture = "corner2"
    tb.BackColor = C_TITLEBAR
    tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "50"
    local ttl = tb:Append("TitleButton")
    ttl.Text = "Settings"; ttl.Texture = "corner1"; ttl.Anchors = "0,0"; ttl.BackColor = C_TITLEBAR
    local cls = tb:Append("CloseButton")
    cls.Anchors = "1,0"; cls.Texture = "corner2"; cls.BackColor = C_TITLEBAR

    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"
    fr.Rows = 5; fr.Columns = 1
    fr[1][1].SizePolicy = "Fixed"; fr[1][1].Size = "42"
    fr[1][2].SizePolicy = "Fixed"; fr[1][2].Size = "55"
    fr[1][3].SizePolicy = "Fixed"; fr[1][3].Size = "55"
    fr[1][4].SizePolicy = "Fixed"; fr[1][4].Size = "55"
    fr[1][5].SizePolicy = "Stretch"

    -- Difficulty header
    local hdr = fr:Append("UILayoutGrid")
    hdr.Anchors = "0,0"; hdr.Columns = 1; hdr.Rows = 1
    local hdrLbl = hdr:Append("UIObject")
    hdrLbl.Anchors = "0,0"; hdrLbl.Text = "Difficulty"
    hdrLbl.Font = "Medium20"; hdrLbl.TextalignmentH = "Center"; hdrLbl.HasHover = "No"
    hdrLbl.BackColor = C_BLUE; hdrLbl.Texture = "corner1"; hdrLbl.Margin = "0,0,0,8"

    -- Difficulty buttons
    s.diffBtns = {}
    for i, d in ipairs(DIFFS) do
        local row = fr:Append("UILayoutGrid")
        row.Anchors = "0," .. i; row.Columns = 1; row.Rows = 1
        local btn = row:Append("Button")
        btn.Anchors = "0,0"; btn.Text = d.label .. "  (" .. d.cols .. "×" .. d.rows .. ", " .. d.mines .. " mines)"
        btn.Font = "Medium20"; btn.Textshadow = 1; btn.HasHover = "Yes"
        btn.TextalignmentH = "Centre"
        btn.BackColor = (i == diffIdx) and C_GREEN or C_DIM
        btn.PluginComponent = my_handle; btn.Clicked = "MsSetDiff_" .. i
        s.diffBtns[i] = btn
    end

    -- New Game button
    local ngRow = fr:Append("UILayoutGrid")
    ngRow.Anchors = "0,4"; ngRow.Columns = 1; ngRow.Rows = 1
    local ngBtn = ngRow:Append("Button")
    ngBtn.Anchors = "0,0"; ngBtn.Text = "New Game"
    ngBtn.Font = "Medium20"; ngBtn.Textshadow = 1; ngBtn.HasHover = "Yes"
    ngBtn.TextalignmentH = "Centre"; ngBtn.BackColor = C_ORANGE
    ngBtn.PluginComponent = my_handle; ngBtn.Clicked = "MsNewGame"

    dialog.settingsWin = s
end

--------------------------------------------------------------------------------
-- Signal callbacks
--------------------------------------------------------------------------------
for r = 1, MAX_ROWS do
    for c = 1, MAX_COLS do
        local r0, c0 = r, c
        signalTable["Ms_" .. r .. "_" .. c] = safe(function()
            handleCellClick(r0, c0)
        end)
    end
end

local function rebuildGame()
    cancelGameTimer()
    local ov = dialog.overlay
    if dialog.settingsWin then
        pcall(function() Obj.Delete(dialog.settingsWin.overlay, Obj.Index(dialog.settingsWin.win)) end)
    end
    Obj.Delete(ov, Obj.Index(dialog.win))
    initBoard()
    dialog = fct.buildGameWindow()
end

signalTable.MsNewGame = safe(function() rebuildGame() end)

signalTable.MsScoreClick = safe(function()
    if gameState == "lost" or gameState == "won" then rebuildGame() end
end)

signalTable.MsFlagMode = safe(function()
    if gameState == "lost" or gameState == "won" then return end
    flagMode = not flagMode
    if dialog and dialog.markBtn then
        dialog.markBtn.Text      = flagMode and "Mark Cell  ON" or "Mark Cell"
        dialog.markBtn.BackColor = flagMode and C_ORANGE or C_DIM
    end
end)

signalTable.MsOpenSettings = safe(function()
    fct.buildSettingsDialog()
end)

for i = 1, #DIFFS do
    local idx = i
    signalTable["MsSetDiff_" .. i] = safe(function()
        if diffIdx == idx then return end
        diffIdx = idx
        -- Update button colors in settings
        if dialog.settingsWin and dialog.settingsWin.diffBtns then
            for j, btn in ipairs(dialog.settingsWin.diffBtns) do
                btn.BackColor = (j == diffIdx) and C_GREEN or C_DIM
            end
        end
        rebuildGame()
    end)
end

--------------------------------------------------------------------------------
-- Plugin entry point
--------------------------------------------------------------------------------
fct.main = function()
    local ok, err = pcall(main)
    if not ok then crashHandler(err) end
end
return fct.main

--[[
================================================================================
  t-60 Plugin License — Non-Commercial Distribution, Version 1.0

  Copyright (c) 2026 t-60
  https://github.com/tminus60/GrandMA3-Plugins

  Free to use — including in paid professional work (shows, events, tours).
  Free to share and modify, as long as this license and author credit are kept.

  NOT permitted:
    - Selling this plugin or any modified version of it.
    - Including it in any paid product, bundle, or paid service.
    - Republishing it under a different name claiming it as your own work.

  Full license: https://github.com/tminus60/GrandMA3-Plugins/blob/master/LICENSE
================================================================================
--]]
