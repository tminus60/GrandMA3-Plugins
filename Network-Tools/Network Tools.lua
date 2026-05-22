--
--  _   _      _                      _     _____           _
-- | \ | | ___| |___      _____  _ __| | __|_   _|___  ___ | |___
-- |  \| |/ _ \ __\ \ /\ / / _ \| '__| |/ /  | |/ _ \/ _ \| / __|
-- | |\  |  __/ |_ \ V  V / (_) | |  |   <   | | (_) | (_) | \__ \
-- |_| \_|\___|\__| \_/\_/ \___/|_|  |_|\_\  |_|\___/ \___/|_|___/
--
--[[---------------------------------------------------------------------------
  Network Tools
  Network diagnostics plugin for grandMA3.
  Single Ping, Sweep, Favorites and Ping Guard with live DOWN alert.

  All network operations run async (shell scripts + done-file polling) so
  GMA3's UI thread is never blocked. Guard monitors IPs in the background
  and opens a custom popup whenever a host goes down or comes back up.

  Author:   t-60
  Version:  3.1.1
  GMA3:     tested on 2.3.2.0
  GitHub:   https://github.com/tminus60/GrandMA3-Plugins
  License:  t-60 Plugin License (Non-Commercial) — see bottom of file
---------------------------------------------------------------------------]]
local pluginVersion = "3.1.1"

-- ── t-60 Crash Reporter ── 2 Zeilen ändern, Rest copy-paste ──
local _T60_WEBHOOK   = "https://discord.com/api/webhooks/1507368948876837085/FqeuJCUYmpebjQlDC9GlrjD3d5JjB3V_z98WUNHHUeyrP3e6bIDdAOi46Nu5-qWCNJSj"
local _T60_PLUGIN_ID = "network-tools"
-- ─────────────────────────────────────────────────────────────

-- ── t-60 Update Checker ── 1 Zeile ändern, Rest copy-paste ──
local _T60_UPDATE_URL = "https://raw.githubusercontent.com/tminus60/GrandMA3-Plugins/main/Network-Tools/version.txt"
-- ─────────────────────────────────────────────────────────────

local pluginName  = select(1, ...)
local signalTable = select(3, ...)
local my_handle   = select(4, ...)

local json = require("json")

local fct    = {}
local dialog -- current foreground window

local FAV_VAR    = "nt_fav_v31"
local GUARD_VAR  = "nt_guard_v31"

local function trimStr(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function encodeFavs(favs)
    local lines = {}
    for _, f in ipairs(favs) do
        local ok = f.last_ok and "1" or "0"
        table.insert(lines, f.ip .. "\t" .. (f.name or "") .. "\t" .. ok
            .. "\t" .. (f.last_ms or "") .. "\t" .. (f.last_mac or ""))
    end
    return table.concat(lines, "\n")
end

local function decodeFavs(raw)
    local favs = {}
    raw = tostring(raw or "")
    if raw == "" then return favs end
    for line in raw:gmatch("[^\n]+") do
        local parts = {}
        for p in (line .. "\t"):gmatch("(.-)\t") do table.insert(parts, p) end
        local ip = parts[1] or ""
        if ip ~= "" then
            table.insert(favs, {
                ip       = ip,
                name     = parts[2] or "",
                last_ok  = (parts[3] == "1"),
                last_ms  = parts[4] or "",
                last_mac = parts[5] or "",
            })
        end
    end
    return favs
end

local function loadFavorites()
    local raw = ""
    pcall(function() raw = GetVar(UserVars(), FAV_VAR) or "" end)
    return decodeFavs(raw)
end

local function saveFavorites(favs)
    pcall(function() SetVar(UserVars(), FAV_VAR, encodeFavs(favs)) end)
end


local function loadGuardConfig()
    local raw = ""
    pcall(function() raw = GetVar(GlobalVars(), GUARD_VAR) or "" end)
    if raw ~= "" then
        local ok, t = pcall(json.decode, raw)
        if ok and type(t) == "table" then
            t.interval = t.interval or 60
            if t.entries then
                local ips, names = {}, {}
                for _, e in ipairs(t.entries) do
                    table.insert(ips, e.ip); names[e.ip] = e.name or ""
                end
                return {ips=ips, names=names, interval=t.interval}
            elseif t.ips then
                local names = {}
                for _, ip in ipairs(t.ips) do names[ip] = "" end
                return {ips=t.ips, names=names, interval=t.interval}
            end
        end
    end
    return {ips={}, names={}, interval=60}
end

local function saveGuardConfig(cfg)
    local ok, raw = pcall(json.encode, cfg)
    if ok then pcall(function() SetVar(GlobalVars(), GUARD_VAR, raw) end) end
end

--------------------------------------------------------------------------------
-- Guard background state
--------------------------------------------------------------------------------
local guardRunning      = false
local guardTimer        = nil
local guardPingResults  = {}
local guardPendingAlert = nil
local guardAlertWin     = nil
local guardIPs      = {}
local guardStatus   = {}
local guardNames    = {}
local guardInterval = 60
local guardWin      = nil

local function buildGuardEntries()
    local t = {}
    for _, ip in ipairs(guardIPs) do
        table.insert(t, {ip=ip, name=guardNames[ip] or ""})
    end
    return t
end

-- Display / fullscreen state
local currentDisplayIdx = 1          -- which screen windows appear on
local currentBuilderFn  = nil        -- set by each window builder so display picker can rebuild
local winNormalSizes    = {}         -- {[winName] = {w, h}} for fullscreen toggle
local displayPicker     = nil        -- separate picker popup window

--------------------------------------------------------------------------------
-- IP helper
--------------------------------------------------------------------------------
local function parseIP(str)
    local a,b,c,d = str:match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
    a,b,c,d = tonumber(a),tonumber(b),tonumber(c),tonumber(d)
    if not (a and b and c and d) then return nil end
    if a>255 or b>255 or c>255 or d>255 then return nil end
    return {a,b,c,d}
end

--------------------------------------------------------------------------------
-- Shell helpers
--------------------------------------------------------------------------------
local function makeTmpDir(prefix)
    local dir = GetPath(Enums.PathType.Temp) .. "/" .. prefix .. tostring(os.clock()):gsub("%.", "")
    if HostOS() == "Windows" then os.execute('mkdir "' .. dir .. '"')
    else os.execute('mkdir -p "' .. dir .. '"') end
    return dir
end

local function cleanup(dir)
    local d = dir:gsub("/", "\\")
    if HostOS() == "Windows" then
        os.execute('rmdir /s /q "' .. d .. '" || ver > nul')
    else
        os.execute('rm -rf "' .. dir .. '" ; true')
    end
end

local function readFile(path)
    local f = io.open(path, "r")
    local s = f and f:read("*a") or ""
    if f then f:close() end
    return s
end

local function parsePingOutput(raw, defaultSent)
    local lower = raw:lower()
    local alive = lower:find("ttl=") or lower:find("bytes from")
    local sent  = tonumber(raw:match("Sent = (%d+)")        -- EN
               or raw:match("Gesendet = (%d+)")             -- DE
               or raw:match("(%d+) packets transmitted"))   -- Linux
               or defaultSent
    local recv  = tonumber(raw:match("Received = (%d+)")    -- EN
               or raw:match("Empfangen = (%d+)")            -- DE
               or raw:match("(%d+) received"))              -- Linux
               or (alive and 1 or 0)
    local ms    = raw:match("Average = (%d+)ms")            -- EN
               or raw:match("Mittelwert = (%d+)ms")        -- DE
               or raw:match("/([%d%.]+)/[%d%.]+%s*ms")     -- Linux
    return alive, sent, recv, ms, math.floor((sent - recv) / sent * 100)
end

local function startPing(host, count)
    count = count or 4
    local d = makeTmpDir("nt_ping_")
    local out  = d .. "/out.txt"
    local done = d .. "/done.txt"
    if HostOS() == "Windows" then
        local f = io.open(d .. "/run.bat", "w")
        f:write("@echo off\r\n")
        f:write('ping -n ' .. count .. ' ' .. host .. ' > "' .. out .. '" 2>&1\r\n')
        f:write('echo done > "' .. done .. '"\r\n')
        f:close()
        os.execute('start /b cmd /c "' .. d .. '\\run.bat"')
    else
        local f = io.open(d .. "/run.sh", "w")
        f:write("#!/bin/bash\n")
        f:write('ping -c ' .. count .. ' ' .. host .. ' > "' .. out .. '" 2>&1\n')
        f:write('echo done > "' .. done .. '"\n')
        f:close()
        os.execute('chmod +x "' .. d .. '/run.sh" && "' .. d .. '/run.sh" &')
    end
    return out, done, d
end

local function startPingAllAsync(ips, count)
    count = count or 4
    local d = makeTmpDir("nt_pingall_")
    local doneFile = d .. "/all_done.txt"
    if HostOS() == "Windows" then
        local f = io.open(d .. "/pingall.bat", "w")
        f:write("@echo off\r\nsetlocal enabledelayedexpansion\r\n")
        for i, ip in ipairs(ips) do
            local out = (d .. "/ip" .. i .. ".txt"):gsub("/", "\\")
            f:write(string.format('set "OUT%d=%s"\r\n', i, out))
            f:write(string.format('start /b cmd /c "ping -n %d -w 1000 %s >!OUT%d! 2>&1"\r\n', count, ip, i))
        end
        f:write("ping -n " .. (count + 2) .. " 127.0.0.1 >nul\r\n")
        f:write('echo done>' .. doneFile:gsub("/", "\\") .. '\r\n')
        f:close()
        os.execute('start /b cmd /c "' .. d:gsub("/", "\\") .. '\\pingall.bat"')
    else
        local f = io.open(d .. "/pingall.sh", "w")
        f:write("#!/bin/bash\n")
        for i, ip in ipairs(ips) do
            f:write(string.format('ping -c %d -W 1 %s > "%s/ip%d.txt" 2>&1 &\n', count, ip, d, i))
        end
        f:write("wait\necho done > \"" .. doneFile .. "\"\n")
        f:close()
        os.execute('bash "' .. d .. '/pingall.sh" &')
    end
    return d, doneFile
end

local function runSweepSync(base, s, e)
    local d   = makeTmpDir("nt_sweep_")
    local res = d .. "/results.txt"
    if HostOS() == "Windows" then
        local f = io.open(d .. "/sweep.bat", "w")
        local resW = res:gsub("/", "\\")
        f:write("@echo off\r\nsetlocal enabledelayedexpansion\r\n")
        f:write('set "RES=' .. resW .. '"\r\n')
        for i = s, e do
            f:write(string.format(
                'start /b cmd /c "ping -n 1 -w 1000 %s.%d >nul 2>nul && echo %s.%d>>!RES!"\r\n',
                base, i, base, i))
        end
        f:write("ping -n 4 127.0.0.1 >nul\r\n")
        f:close()
        os.execute('cmd /c "' .. d:gsub("/", "\\") .. '\\sweep.bat"')
    else
        local f = io.open(d .. "/sweep.sh", "w")
        f:write("#!/bin/bash\n")
        for i = s, e do
            f:write(string.format(
                '(ping -c 1 -W 1 %s.%d > /dev/null 2>&1 && echo "%s.%d" >> "%s") &\n',
                base, i, base, i, res))
        end
        f:write("wait\n")
        f:close()
        os.execute('bash "' .. d .. '/sweep.sh"')
    end
    return res, d
end

local function getMACForIP(ip)
    local tmp = GetPath(Enums.PathType.Temp) .. "/nt_mac_" .. ip:gsub("%.", "_") .. ".txt"
    if HostOS() == "Windows" then
        os.execute('arp -a ' .. ip .. ' > "' .. tmp:gsub("/","\\") .. '" 2>&1 || ver > nul')
    else
        os.execute('arp -n ' .. ip .. ' > "' .. tmp .. '" 2>&1 ; true')
    end
    local f = io.open(tmp, "r")
    if not f then return "—" end
    local content = f:read("*a"); f:close()
    pcall(function()
        if HostOS() == "Windows" then
            os.execute('del "' .. tmp:gsub("/","\\") .. '" 2>nul || ver > nul')
        else os.execute('rm -f "' .. tmp .. '" ; true') end
    end)
    local mac = content:match("%x%x[%-%:]%x%x[%-%:]%x%x[%-%:]%x%x[%-%:]%x%x[%-%:]%x%x")
    return mac and mac:upper() or "—"
end


--------------------------------------------------------------------------------
-- Crash handler + safe wrappers
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
        local gma  = ""; pcall(function() gma  = tostring(Root().SoftwareVersion) end)
        local show = ""; pcall(function() show = tostring(Root().ShowData.Name)    end)
        local msg = "**[" .. _T60_PLUGIN_ID .. "  v" .. tostring(version) .. "  —  CRASH]**\\n"
            .. "```\\n"
            .. "Plugin:  " .. _T60_PLUGIN_ID .. " v" .. tostring(version) .. "\\n"
            .. "Fehler:  " .. tostring(err)                            .. "\\n"
            .. "GMA3:    " .. gma                                       .. "\\n"
            .. "Show:    " .. show                                      .. "\\n"
            .. "OS:      " .. HostOS()                                  .. "\\n"
            .. "Zeit:    " .. os.date("%Y-%m-%d %H:%M:%S")              .. "\\n"
            .. "```"
        local tmp = GetPath(Enums.PathType.Temp)
        if HostOS() == "Windows" then
            -- PowerShell: sendet Nachricht + Log-Datei als Anhang in einer Discord-Message
            local lp  = logPath:gsub("/","\\"):gsub("'","''")
            local wh  = _T60_WEBHOOK:gsub("'","''")
            local ps1 = tmp .. "\\t60_crash.ps1"
            local fw  = io.open(ps1, "w")
            if fw then
                fw:write("try {\n")
                fw:write("  $c=[Net.Http.HttpClient]::new()\n")
                fw:write("  $f=[Net.Http.MultipartFormDataContent]::new()\n")
                fw:write("  $pj=[Net.Http.StringContent]::new('{\"content\":" .. _t60Str(msg) .. "}','UTF-8','application/json')\n")
                fw:write("  $f.Add($pj,'payload_json')\n")
                fw:write("  if(Test-Path '" .. lp .. "'){\n")
                fw:write("    $b=[IO.File]::ReadAllBytes('" .. lp .. "')\n")
                fw:write("    $fc=[Net.Http.ByteArrayContent]::new($b)\n")
                fw:write("    $fc.Headers.ContentType=[Net.Http.Headers.MediaTypeHeaderValue]::new('text/plain')\n")
                fw:write("    $f.Add($fc,'files[0]','crash.log')\n")
                fw:write("  }\n")
                fw:write("  $c.PostAsync('" .. wh .. "',$f).Wait()\n")
                fw:write("} catch {}\n")
                fw:close()
            end
            os.execute('start /b powershell -NonInteractive -WindowStyle Hidden'
                .. ' -File "' .. ps1:gsub("/","\\") .. '" || ver >nul')
        else
            -- Linux/GMA3-Pult: curl mit Dateianhang
            local jf = tmp .. "/t60_crash_payload.json"
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
        icon = "warning", titleTextColor = "Global.Text",
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

local function safePoll(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then Printf("[ERROR] poll: " .. tostring(err)) end
    end
end

--------------------------------------------------------------------------------
-- Colour vars
--------------------------------------------------------------------------------
local C_ORANGE, C_BLUE, C_GREEN, C_RED, C_DIM, C_HDR, C_CLEAR, C_TITLEBAR

--------------------------------------------------------------------------------
-- UI helpers
--------------------------------------------------------------------------------
local function getOverlay()
    local idx = currentDisplayIdx
    if idx < 1 or idx > 5 then idx = 1 end
    local d = GetDisplayByIndex(idx)
    return d.ScreenOverlay, d
end

local function makeWin(name, w, h, noClose)
    local overlay, display = getOverlay()
    local win = overlay:Append("BaseInput")
    win.Name = name; win.W = w; win.H = h
    win.Rows = 2; win.Columns = 1
    win[1][1].SizePolicy = "Fixed"; win[1][1].Size = 40
    win[1][2].SizePolicy = "Stretch"
    win.AutoClose = "No"; win.CloseOnEscape = "Yes"
    pcall(function()
        win.MaxSize = string.format("%s,%s", display.W, display.H)
    end)
    win.BackColor = C_TITLEBAR

    local tb = win:Append("TitleBar")
    tb.Columns = 5; tb.Rows = 1; tb.Anchors = "0,0"; tb.Texture = "corner2"
    tb.BackColor = C_TITLEBAR
    tb[2][1].SizePolicy = "Fixed"; tb[2][1].Size = "40"
    tb[2][3].SizePolicy = "Fixed"; tb[2][3].Size = "50"
    tb[2][4].SizePolicy = "Fixed"; tb[2][4].Size = "50"
    tb[2][5].SizePolicy = "Fixed"; tb[2][5].Size = "50"

    local ico = tb:Append("AppearancePreview")
    ico.Anchors = "0,0"; ico.W = "40"; ico.BackColor = C_TITLEBAR
    pcall(function()
        local app = GetObject("Appearance NetworkToolsLogo")
        if app then ico.Appearance = app end
        ico.Texture = "corner1"
    end)

    local ttl = tb:Append("TitleButton")
    ttl.Text = name; ttl.Texture = "corner0"; ttl.BackColor = C_TITLEBAR
    ttl.Anchors = "1,0"

    local dispBtn = tb:Append("Button")
    dispBtn.Anchors = "2,0"; dispBtn.Icon = "display"; dispBtn.BackColor = C_TITLEBAR
    dispBtn.HasHover = "Yes"; dispBtn.Texture = "corner0"
    dispBtn.PluginComponent = my_handle; dispBtn.Clicked = "CycleDisplay"

    local fsBtn = tb:Append("Button")
    fsBtn.Anchors = "3,0"; fsBtn.Icon = "ResizeFixed"; fsBtn.BackColor = C_TITLEBAR
    fsBtn.HasHover = "Yes"; fsBtn.Texture = "corner0"
    fsBtn.PluginComponent = my_handle; fsBtn.Clicked = "ToggleFullscreen"

    if noClose then
        local cb = tb:Append("Button")
        cb.Anchors = "4,0"; cb.Icon = "close"; cb.BackColor = C_TITLEBAR
        cb.HasHover = "Yes"; cb.Texture = "corner2"
        cb.PluginComponent = my_handle; cb.Clicked = "CloseWin"
    else
        local cb = tb:Append("CloseButton")
        cb.Anchors = "4,0"; cb.Texture = "corner2"; cb.BackColor = C_TITLEBAR
    end
    return win, overlay, display
end

local function addResizer(w)
    local r = w:Append("ResizeCorner")
    r.Anchors = "0,1"
    r.AlignmentH = "Right"; r.AlignmentV = "Bottom"
end

local function sectionHdr(parent, anchor, text, color)
    local g = parent:Append("UILayoutGrid")
    g.Anchors = "0," .. anchor; g.Columns = 1; g.Rows = 1
    local lbl = g:Append("UIObject")
    lbl.Anchors = "0,0"; lbl.Text = text
    lbl.Font = "Medium20"; lbl.TextalignmentH = "Center"
    lbl.HasHover = "No"; lbl.BackColor = color
end

local function closeBtn(fr, anchor)
    local g = fr:Append("UILayoutGrid")
    g.Anchors = "0," .. anchor; g.Columns = 1; g.Rows = 1
    local cb = g:Append("Button")
    cb.Anchors = "0,0"; cb.Text = "Close"
    cb.Font = "Medium20"; cb.Textshadow = 1; cb.HasHover = "Yes"
    cb.TextalignmentH = "Centre"
    cb.PluginComponent = my_handle; cb.Clicked = "CloseWin"
end

-- Build a table header row (UILayoutGrid with column labels)
local function tableHeader(parent, anchor, cols)
    local g = parent:Append("UILayoutGrid")
    g.Anchors = "0," .. anchor; g.Columns = #cols; g.Rows = 1
    for i, col in ipairs(cols) do
        g[2][i].SizePolicy = col.policy or "Stretch"
        if col.size then g[2][i].Size = col.size end
        local lbl = g:Append("UIObject")
        lbl.Anchors = tostring(i-1) .. ",0"; lbl.Text = col.label or ""
        lbl.Font = "Medium20"; lbl.TextalignmentH = col.align or "Center"
        lbl.HasHover = "No"; lbl.BackColor = C_HDR
    end
    return g
end

--------------------------------------------------------------------------------
-- Scrollable pre-allocated table helpers
--------------------------------------------------------------------------------
local ROW_H  = 48
local MAX_SW = 30
local MAX_FV = 15
local MAX_GD = 20

local function showRow(rowHeights, r, show)
    if rowHeights[r] then
        rowHeights[r].Size = show and tostring(ROW_H) or "0"
    end
end

local function makeScrollTable(parent, anchor, numCols, colDefs, maxRows)
    local wrapper = parent:Append("UILayoutGrid")
    wrapper.Anchors = "0," .. anchor; wrapper.Columns = 2; wrapper.Rows = 1
    wrapper[2][1].SizePolicy = "Stretch"
    wrapper[2][2].SizePolicy = "Fixed"; wrapper[2][2].Size = "20"

    local sb = wrapper:Append("ScrollBox")
    sb.Anchors = "0,0"; sb.H = "100%"; sb.W = "100%"

    local sbv = wrapper:Append("ScrollBarV")
    sbv.Anchors = "1,0"; sbv.H = "100%"; sbv.ScrollTarget = sb

    local grid = sb:Append("UILayoutGrid")
    grid.Columns = numCols; grid.Rows = maxRows
    grid.W = "100%"; grid.H = 0
    for i, cd in ipairs(colDefs) do
        grid[2][i].SizePolicy = cd.policy or "Stretch"
        if cd.size then grid[2][i].Size = cd.size end
    end
    local rowHeights = {}
    for r = 1, maxRows do
        rowHeights[r] = grid[1][r]
        rowHeights[r].SizePolicy = "Fixed"
        rowHeights[r].Size = "0"
    end
    return grid, rowHeights
end

--------------------------------------------------------------------------------
-- Main entry
--------------------------------------------------------------------------------
local function main()
    C_ORANGE = Root().ColorTheme.ColorGroups.Global.PartlySelected
    C_BLUE   = Root().ColorTheme.ColorGroups.Assignment.Group
    C_GREEN  = Root().ColorTheme.ColorGroups.Button.BackgroundPlease
    C_RED    = Root().ColorTheme.ColorGroups.Button.BackgroundClear
    C_DIM    = Root().ColorTheme.ColorGroups.Global.Focus
    C_HDR    = Root().ColorTheme.ColorGroups.Global.Focus
    C_CLEAR  = Root().ColorTheme.ColorGroups.Global.Transparent
    C_TITLEBAR = Root().ColorTheme.ColorGroups.PoolWindow.Bitmaps

    local focusIdx = Obj.Index(GetFocusDisplay())
    currentDisplayIdx = (focusIdx > 0 and focusIdx <= 5) and focusIdx or 1

    local cfg = loadGuardConfig()
    guardIPs = cfg.ips; guardInterval = math.max(10, cfg.interval)
    guardNames = cfg.names or {}
    for _, ip in ipairs(guardIPs) do guardStatus[ip] = nil end

    local shortcuts = CurrentProfile().KeyboardShortCuts
    shortcuts.KeyboardShortcutsActive = false
    dialog = fct.buildLauncher()
    pcall(_t60CheckUpdate)
end

--------------------------------------------------------------------------------
-- ── LAUNCHER ──────────────────────────────────────────────────────────────────
--------------------------------------------------------------------------------
function fct.buildLauncher()
    local result = {}
    currentBuilderFn = fct.buildLauncher
    local win, overlay = makeWin("Network Tools", 780, 460)
    result.win = win; result.overlay = overlay

    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"
    fr.Columns = 1; fr.Rows = 1
    fr[1][1].SizePolicy = "Stretch"
    

    local grid = fr:Append("UILayoutGrid")
    grid.Anchors = "0,0"; grid.Columns = 1; grid.Rows = 8
    grid[1][1].SizePolicy = "Fixed";   grid[1][1].Size = 40   -- Single Ping hdr
    grid[1][2].SizePolicy = "Stretch"                           -- Single Ping card
    grid[1][3].SizePolicy = "Fixed";   grid[1][3].Size = 40   -- Sweep hdr
    grid[1][4].SizePolicy = "Stretch"                           -- Sweep card
    grid[1][5].SizePolicy = "Fixed";   grid[1][5].Size = 40   -- Fav hdr
    grid[1][6].SizePolicy = "Stretch"                           -- Fav card
    grid[1][7].SizePolicy = "Fixed";   grid[1][7].Size = 40   -- Guard hdr
    grid[1][8].SizePolicy = "Stretch"                           -- Guard card

    local function card(hdrAnchor, cardAnchor, title, color, desc, signal)
        sectionHdr(grid, hdrAnchor, title, color)
        local g = grid:Append("UILayoutGrid")
        g.Anchors = "0," .. cardAnchor; g.Columns = 2; g.Rows = 1
        g[2][2].SizePolicy = "Fixed"; g[2][2].Size = 120
        local d = g:Append("UIObject")
        d.Anchors = "0,0"; d.Text = desc
        d.Font = "Medium20"; d.TextalignmentH = "Left"
        d.TextalignmentV = "Center"; d.HasHover = "No"
        local btn = g:Append("Button")
        btn.Anchors = "1,0"; btn.Text = "Open"
        btn.Font = "Medium20"; btn.Textshadow = 1; btn.HasHover = "Yes"
        btn.TextalignmentH = "Centre"; btn.BackColor = color
        btn.PluginComponent = my_handle; btn.Clicked = signal
        return btn
    end

    card(0, 1, "Single Ping", C_ORANGE, "Ping a single host or IP address.", "Lnch_Ping")
    card(2, 3, "Ping Sweep",  C_BLUE,   "Scan an IP range in parallel.", "Lnch_Sweep")
    card(4, 5, "Favorites",   C_GREEN,  "Quick-ping saved hosts (per user).", "Lnch_Fav")

    local gb = card(6, 7, "Ping Guard", C_RED, "Monitor IPs continuously.", "Lnch_Guard")
    gb.Text = guardRunning and "Guard ON" or "Open"
    result.guardBtn = gb

    addResizer(win)
    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- ── SINGLE PING ───────────────────────────────────────────────────────────────
--------------------------------------------------------------------------------
function fct.buildPingWin()
    local result = {}
    currentBuilderFn = fct.buildPingWin
    local win, overlay = makeWin("Single Ping", 700, 560, true)
    result.win = win; result.overlay = overlay

    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"
    fr.Columns = 1; fr.Rows = 5
    fr[1][1].SizePolicy = "Fixed";   fr[1][1].Size = "42"   -- Settings hdr
    fr[1][2].SizePolicy = "Fixed";   fr[1][2].Size = "60"   -- input row
    fr[1][3].SizePolicy = "Fixed";   fr[1][3].Size = "42"   -- Result hdr
    fr[1][4].SizePolicy = "Stretch"                          -- result text (grows)
    fr[1][5].SizePolicy = "Fixed";   fr[1][5].Size = "55"   -- Close

    sectionHdr(fr, 0, "Settings", C_ORANGE)

    local inputRow = fr:Append("UILayoutGrid")
    inputRow.Anchors = "0,1"; inputRow.Columns = 3; inputRow.Rows = 1
    inputRow[2][1].SizePolicy = "Fixed"; inputRow[2][1].Size = "130"
    inputRow[2][3].SizePolicy = "Fixed"; inputRow[2][3].Size = "110"
    local lbl = inputRow:Append("UIObject")
    lbl.Anchors = "0,0"; lbl.Text = "Host / IP"
    lbl.Font = "Medium20"; lbl.TextalignmentH = "Center"; lbl.HasHover = "No"
    local edit = inputRow:Append("LineEdit")
    edit.Anchors = "1,0"; edit.Message = "192.168.1.1"
    edit.Texture = "corner0"; edit.Focus = "InitialFocus"
    edit.TextChanged = "OnChangeAll"; edit.PluginComponent = my_handle
    edit.VKPluginName = "TextInput"
    result.pingEdit = edit
    local btn = inputRow:Append("Button")
    btn.Anchors = "2,0"; btn.Text = "Ping"
    btn.Font = "Medium20"; btn.Textshadow = 1; btn.HasHover = "Yes"
    btn.TextalignmentH = "Centre"; btn.PluginComponent = my_handle
    btn.Clicked = "PingBtn"; btn.BackColor = C_RED; btn.Enabled = "No"
    result.pingBtn = btn

    sectionHdr(fr, 2, "Result", C_ORANGE)

    local resRow = fr:Append("UILayoutGrid")
    resRow.Anchors = "0,3"; resRow.Columns = 1; resRow.Rows = 1
    local res = resRow:Append("UIObject")
    res.Anchors = "0,0"; res.Text = "Enter a host and press Ping."
    res.Font = "Medium20"; res.TextalignmentH = "Left"
    res.TextalignmentV = "Top"; res.HasHover = "No"
    result.pingResult = res

    closeBtn(fr, 4)

    addResizer(win)
    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- ── PING SWEEP ────────────────────────────────────────────────────────────────
--------------------------------------------------------------------------------
function fct.buildSweepWin()
    local result = {}
    currentBuilderFn = fct.buildSweepWin
    local winH = 60 + 306 + 10 * ROW_H + 55
    local win, overlay = makeWin("Ping Sweep", 720, winH, true)
    result.win = win; result.overlay = overlay

    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"
    fr.Columns = 1; fr.Rows = 8
    fr[1][1].SizePolicy = "Fixed";  fr[1][1].Size = "42"  -- Settings hdr
    fr[1][2].SizePolicy = "Fixed";  fr[1][2].Size = "60"  -- Start IP
    fr[1][3].SizePolicy = "Fixed";  fr[1][3].Size = "60"  -- End IP
    fr[1][4].SizePolicy = "Fixed";  fr[1][4].Size = "60"  -- status + btn
    fr[1][5].SizePolicy = "Fixed";  fr[1][5].Size = "42"  -- Active Hosts hdr
    fr[1][6].SizePolicy = "Fixed";  fr[1][6].Size = "42"  -- col header
    fr[1][7].SizePolicy = "Stretch"                        -- table (grows)
    fr[1][8].SizePolicy = "Fixed";  fr[1][8].Size = "55"  -- Close

    sectionHdr(fr, 0, "Settings", C_BLUE)

    local function ipRow(anchor, label, placeholder, ref)
        local g = fr:Append("UILayoutGrid")
        g.Anchors = "0," .. anchor; g.Columns = 2; g.Rows = 1
        g[2][1].SizePolicy = "Fixed"; g[2][1].Size = "130"
        local lbl = g:Append("UIObject")
        lbl.Anchors = "0,0"; lbl.Text = label
        lbl.Font = "Medium20"; lbl.TextalignmentH = "Center"; lbl.HasHover = "No"
        local ed = g:Append("LineEdit")
        ed.Anchors = "1,0"; ed.Message = placeholder
        ed.Texture = "corner0"; ed.VKPluginName = "TextInput"
        ed.TextChanged = "OnChangeAll"; ed.PluginComponent = my_handle
        result[ref] = ed
    end

    ipRow(1, "Start IP", "192.168.1.1",   "startEdit")
    ipRow(2, "End IP",   "192.168.1.254",  "endEdit")

    local ctrlRow = fr:Append("UILayoutGrid")
    ctrlRow.Anchors = "0,3"; ctrlRow.Columns = 2; ctrlRow.Rows = 1
    ctrlRow[2][2].SizePolicy = "Fixed"; ctrlRow[2][2].Size = "110"
    local sweepStatus = ctrlRow:Append("UIObject")
    sweepStatus.Anchors = "0,0"; sweepStatus.Font = "Medium20"
    sweepStatus.TextalignmentH = "Left"; sweepStatus.TextalignmentV = "Center"
    sweepStatus.HasHover = "No"
    result.sweepStatus = sweepStatus
    local sweepBtn = ctrlRow:Append("Button")
    sweepBtn.Anchors = "1,0"; sweepBtn.Text = "Sweep"
    sweepBtn.Font = "Medium20"; sweepBtn.Textshadow = 1; sweepBtn.HasHover = "Yes"
    sweepBtn.TextalignmentH = "Centre"; sweepBtn.PluginComponent = my_handle
    sweepBtn.Clicked = "SweepBtn"; sweepBtn.BackColor = C_RED; sweepBtn.Enabled = "No"
    result.sweepBtn = sweepBtn

    sectionHdr(fr, 4, "Active Hosts", C_BLUE)

    tableHeader(fr, 5, {
        {label="",              policy="Fixed", size="20"},
        {label="IPv4 Address",  policy="Fixed", size="160"},
        {label="MAC Address",   policy="Fixed", size="240"},
        {label="Loss",          policy="Fixed", size="55"},
        {label="Result"},                                      -- Stretch
        {label="Ping",          policy="Fixed", size="65"},
        {label="Fav",           policy="Fixed", size="60"},
        {label="",              policy="Fixed", size="20"},
    })

    local grid, rowH = makeScrollTable(fr, 6, 7, {
        {policy="Fixed", size="20"},
        {policy="Fixed", size="160"},
        {policy="Fixed", size="240"},
        {policy="Fixed", size="55"},
        {},                          -- Result: Stretch
        {policy="Fixed", size="65"},
        {policy="Fixed", size="60"},
    }, MAX_SW)
    result.sweepGrid = grid

    local cells = {}
    for r = 1, MAX_SW do
        local function lbl(col, align)
            local el = grid:Append("UIObject")
            el.Anchors = col .. "," .. (r-1); el.Font = "Medium20"
            el.TextalignmentH = align or "Center"; el.TextalignmentV = "Center"
            el.HasHover = "No"; el.Padding = "6,4"; el.Margin = "0,3,0,0"; return el
        end
        local ind = grid:Append("UIObject")
        ind.Anchors = "0," .. (r-1); ind.HasHover = "No"
        local pingBtn = grid:Append("Button")
        pingBtn.Anchors = "5," .. (r-1); pingBtn.Text = "Ping"
        pingBtn.Font = "Medium20"; pingBtn.Textshadow = 1; pingBtn.HasHover = "Yes"
        pingBtn.TextalignmentH = "Centre"; pingBtn.BackColor = C_BLUE
        pingBtn.PluginComponent = my_handle; pingBtn.Clicked = "SwPing_" .. r; pingBtn.Margin = "0,3,0,0"
        local favBtn = grid:Append("Button")
        favBtn.Anchors = "6," .. (r-1); favBtn.Text = "Fav"
        favBtn.Font = "Medium20"; favBtn.Textshadow = 1; favBtn.HasHover = "Yes"
        favBtn.TextalignmentH = "Centre"; favBtn.BackColor = C_ORANGE
        favBtn.PluginComponent = my_handle; favBtn.Clicked = "SwFav_" .. r; favBtn.Margin = "0,3,0,0"
        cells[r] = {ind=ind, ip=lbl("1","Left"), mac=lbl("2","Left"), loss=lbl("3"),
                    res=lbl("4","Left"), ping=pingBtn, fav=favBtn}
    end
    result.sweepRowH = rowH; result.sweepCells = cells; result.sweepIPs = {}

    closeBtn(fr, 7)

    addResizer(win)
    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- ── FAVORITES ─────────────────────────────────────────────────────────────────
--------------------------------------------------------------------------------
function fct.buildFavWin()
    local result = {}
    currentBuilderFn = fct.buildFavWin
    local favs = loadFavorites()
    result.favs = favs

    local winH = 60 + 42 + 42 + 10 * ROW_H + 55 + 55 + 55

    local win, overlay = makeWin("Favorites", 940, winH, true)
    result.win = win; result.overlay = overlay

    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"
    fr.Columns = 1; fr.Rows = 6
    fr[1][1].SizePolicy = "Fixed";  fr[1][1].Size = "42"  -- hdr
    fr[1][2].SizePolicy = "Fixed";  fr[1][2].Size = "42"  -- col header
    fr[1][3].SizePolicy = "Stretch"                        -- table (grows)
    fr[1][4].SizePolicy = "Fixed";  fr[1][4].Size = "55"  -- Ping All + status
    fr[1][5].SizePolicy = "Fixed";  fr[1][5].Size = "55"  -- Add row
    fr[1][6].SizePolicy = "Fixed";  fr[1][6].Size = "55"  -- close

    sectionHdr(fr, 0, "Saved Hosts  (" .. #favs .. ")", C_GREEN)

    tableHeader(fr, 1, {
        {label="",       policy="Fixed", size="20"},
        {label="Name"},
        {label="IP",     policy="Fixed", size="170"},
        {label="MAC",    policy="Fixed", size="210"},
        {label="Loss",   policy="Fixed", size="55"},
        {label="Result", policy="Fixed", size="85"},
        {label="Ping",   policy="Fixed", size="65"},
        {label="",       policy="Fixed", size="50"},   -- More (icon)
        {label="Del",    policy="Fixed", size="50"},
        {label="",       policy="Fixed", size="20"},
    })

    local grid, rowH = makeScrollTable(fr, 2, 9, {
        {policy="Fixed", size="20"},
        {},              -- Name: Stretch
        {policy="Fixed", size="170"},
        {policy="Fixed", size="210"},
        {policy="Fixed", size="55"},
        {policy="Fixed", size="85"},
        {policy="Fixed", size="65"},
        {policy="Fixed", size="50"},   -- More
        {policy="Fixed", size="50"},   -- Del
    }, MAX_FV)
    result.favGrid = grid

    result.favRowH = rowH; result.favCells = {}

    for r = 1, MAX_FV do
        local function lbl(col, align)
            local el = grid:Append("UIObject"); el.Anchors = col .. "," .. (r-1)
            el.Font = "Medium20"; el.TextalignmentH = align or "Center"
            el.TextalignmentV = "Center"; el.HasHover = "No"; el.Padding = "6,4"; el.Margin = "0,3,0,0"; return el
        end
        local ind = grid:Append("UIObject"); ind.Anchors = "0," .. (r-1); ind.HasHover = "No"; ind.Margin = "0,3,0,0"
        local pingBtn = grid:Append("Button"); pingBtn.Anchors = "6," .. (r-1)
        pingBtn.Text = "Ping"; pingBtn.Font = "Medium20"; pingBtn.Textshadow = 1
        pingBtn.HasHover = "Yes"; pingBtn.TextalignmentH = "Centre"
        pingBtn.PluginComponent = my_handle; pingBtn.Clicked = "FavPing_" .. r; pingBtn.Margin = "0,3,0,0"
        local moreBtn = grid:Append("Button"); moreBtn.Anchors = "7," .. (r-1)
        moreBtn.Icon = "DialogButtonIcon"; moreBtn.HasHover = "Yes"; moreBtn.Texture = "corner0"
        moreBtn.PluginComponent = my_handle; moreBtn.Clicked = "FavMore_" .. r; moreBtn.Margin = "0,3,0,0"
        local delBtn = grid:Append("Button"); delBtn.Anchors = "8," .. (r-1)
        delBtn.Text = "Del"; delBtn.Font = "Medium20"; delBtn.Textshadow = 1
        delBtn.HasHover = "Yes"; delBtn.TextalignmentH = "Centre"; delBtn.BackColor = C_RED
        delBtn.PluginComponent = my_handle; delBtn.Clicked = "FavDel_" .. r; delBtn.Margin = "0,3,0,0"
        result.favCells[r] = {
            ind=ind, name=lbl("1","Left"), ip=lbl("2","Left"),
            mac=lbl("3","Left"), loss=lbl("4"), res=lbl("5"),
            ping=pingBtn, more=moreBtn, del=delBtn
        }
    end

    for i, fav in ipairs(favs) do
        if i > MAX_FV then break end
        showRow(rowH, i, true)
        local c = result.favCells[i]
        c.ind.BackColor = fav.last_ok and C_GREEN or (fav.last_ms ~= "" and C_RED or C_DIM)
        c.name.Text     = fav.name ~= "" and fav.name or "(unnamed)"
        c.ip.Text       = fav.ip
        c.mac.Text      = fav.last_mac ~= "" and fav.last_mac or "—"
        c.loss.Text     = fav.last_ms ~= "" and (fav.last_ok and "0%" or "100%") or "—"
        c.res.Text      = fav.last_ms ~= "" and (fav.last_ms .. " ms") or "—"
    end
    for i = #favs + 1, MAX_FV do showRow(rowH, i, false) end
    grid.H = #favs * ROW_H

    local paRow = fr:Append("UILayoutGrid")
    paRow.Anchors = "0,3"; paRow.Columns = 2; paRow.Rows = 1
    paRow[2][1].SizePolicy = "Fixed"; paRow[2][1].Size = "120"

    local pingAllBtn = paRow:Append("Button")
    pingAllBtn.Anchors = "0,0"; pingAllBtn.Text = "Ping All"
    pingAllBtn.Font = "Medium20"; pingAllBtn.Textshadow = 1; pingAllBtn.HasHover = "Yes"
    pingAllBtn.TextalignmentH = "Centre"; pingAllBtn.BackColor = C_BLUE
    pingAllBtn.PluginComponent = my_handle; pingAllBtn.Clicked = "FavPingAll"
    result.pingAllBtn = pingAllBtn

    local favStatus = paRow:Append("UIObject")
    favStatus.Anchors = "1,0"; favStatus.Font = "Medium20"
    favStatus.TextalignmentH = "Left"; favStatus.TextalignmentV = "Center"
    favStatus.HasHover = "No"
    result.favStatus = favStatus

    local btm = fr:Append("UILayoutGrid")
    btm.Anchors = "0,4"; btm.Columns = 3; btm.Rows = 1
    btm[2][1].SizePolicy = "Fixed"; btm[2][1].Size = "120"

    local addBtn = btm:Append("Button")
    addBtn.Anchors = "0,0"; addBtn.Text = "Add Host"
    addBtn.Font = "Medium20"; addBtn.Textshadow = 1; addBtn.HasHover = "Yes"
    addBtn.TextalignmentH = "Centre"; addBtn.BackColor = C_GREEN
    addBtn.PluginComponent = my_handle; addBtn.Clicked = "FavAdd"

    local favIPEdit = btm:Append("LineEdit")
    favIPEdit.Anchors = "1,0"; favIPEdit.Message = "IP address"
    favIPEdit.Texture = "corner0"; favIPEdit.VKPluginName = "TextInput"
    favIPEdit.PluginComponent = my_handle
    result.favIPEdit = favIPEdit

    local favNameEdit = btm:Append("LineEdit")
    favNameEdit.Anchors = "2,0"; favNameEdit.Message = "Name (optional)"
    favNameEdit.Texture = "corner0"; favNameEdit.VKPluginName = "TextInput"
    favNameEdit.PluginComponent = my_handle
    result.favNameEdit = favNameEdit

    closeBtn(fr, 5)

    addResizer(win)
    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- ── PING GUARD ────────────────────────────────────────────────────────────────
--------------------------------------------------------------------------------
function fct.buildGuardWin()
    local result = {}
    currentBuilderFn = fct.buildGuardWin

    local winH = 60 + 42 + 42 + 10 * ROW_H + 60 + 55 + 55

    local win, overlay = makeWin("Ping Guard", 640, winH, true)
    result.win = win; result.overlay = overlay

    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"
    fr.Columns = 1; fr.Rows = 6
    fr[1][1].SizePolicy = "Fixed";  fr[1][1].Size = "42"
    fr[1][2].SizePolicy = "Fixed";  fr[1][2].Size = "42"
    fr[1][3].SizePolicy = "Stretch"
    fr[1][4].SizePolicy = "Fixed";  fr[1][4].Size = "60"
    fr[1][5].SizePolicy = "Fixed";  fr[1][5].Size = "55"
    fr[1][6].SizePolicy = "Fixed";  fr[1][6].Size = "55"

    sectionHdr(fr, 0, "Monitored Hosts  (" .. #guardIPs .. ")", C_RED)

    tableHeader(fr, 1, {
        {label="",           policy="Fixed", size="20"},
        {label="IP Address", policy="Fixed", size="150"},
        {label="Name"},
        {label="Status",     policy="Fixed", size="80"},
        {label="",           policy="Fixed", size="50"},
        {label="",           policy="Fixed", size="20"},
    })

    local grid, rowH = makeScrollTable(fr, 2, 5, {
        {policy="Fixed", size="20"},
        {policy="Fixed", size="150"},
        {},   -- Name: Stretch
        {policy="Fixed", size="80"},
        {policy="Fixed", size="50"},
    }, MAX_GD)
    result.guardGrid = grid
    result.guardRowH = rowH; result.guardCells = {}

    for r = 1, MAX_GD do
        local function lbl(col, align)
            local el = grid:Append("UIObject"); el.Anchors = col .. "," .. (r-1)
            el.Font = "Medium20"; el.TextalignmentH = align or "Center"
            el.TextalignmentV = "Center"; el.HasHover = "No"; el.Padding = "6,4"; el.Margin = "0,3,0,0"; return el
        end
        local ind = grid:Append("UIObject"); ind.Anchors = "0," .. (r-1); ind.HasHover = "No"; ind.Margin = "0,3,0,0"
        local moreBtn = grid:Append("Button"); moreBtn.Anchors = "4," .. (r-1)
        moreBtn.Icon = "DialogButtonIcon"; moreBtn.HasHover = "Yes"; moreBtn.Texture = "corner0"
        moreBtn.PluginComponent = my_handle; moreBtn.Clicked = "GuardMore_" .. r; moreBtn.Margin = "0,3,0,0"
        result.guardCells[r] = {ind=ind, ip=lbl("1","Left"), name=lbl("2","Left"),
                                 st=lbl("3"), more=moreBtn}
    end

    for i, ip in ipairs(guardIPs) do
        if i > MAX_GD then break end
        showRow(rowH, i, true)
        local c = result.guardCells[i]; local alive = guardStatus[ip]
        c.ind.BackColor = alive == true and C_GREEN or (alive == false and C_RED or C_DIM)
        c.ip.Text   = ip
        c.name.Text = guardNames[ip] or ""
        c.st.Text   = alive == true and "UP" or (alive == false and "DOWN" or "—")
    end
    for i = #guardIPs + 1, MAX_GD do showRow(rowH, i, false) end
    grid.H = #guardIPs * ROW_H

    local addRow = fr:Append("UILayoutGrid")
    addRow.Anchors = "0,3"; addRow.Columns = 5; addRow.Rows = 1
    addRow[2][1].SizePolicy = "Fixed"; addRow[2][1].Size = "90"
    addRow[2][2].SizePolicy = "Fixed"; addRow[2][2].Size = "120"
    addRow[2][4].SizePolicy = "Fixed"; addRow[2][4].Size = "80"
    addRow[2][5].SizePolicy = "Fixed"; addRow[2][5].Size = "100"

    local addBtn = addRow:Append("Button")
    addBtn.Anchors = "0,0"; addBtn.Text = "Add IP"
    addBtn.Font = "Medium20"; addBtn.Textshadow = 1; addBtn.HasHover = "Yes"
    addBtn.TextalignmentH = "Centre"; addBtn.BackColor = C_GREEN
    addBtn.PluginComponent = my_handle; addBtn.Clicked = "GuardAdd"

    local guardIPEdit = addRow:Append("LineEdit")
    guardIPEdit.Anchors = "1,0"; guardIPEdit.Message = "IP address"
    guardIPEdit.Texture = "corner0"; guardIPEdit.VKPluginName = "TextInput"
    guardIPEdit.PluginComponent = my_handle; result.guardIPEdit = guardIPEdit

    local guardNameEdit = addRow:Append("LineEdit")
    guardNameEdit.Anchors = "2,0"; guardNameEdit.Message = "Name (optional)"
    guardNameEdit.Texture = "corner0"; guardNameEdit.VKPluginName = "TextInput"
    guardNameEdit.PluginComponent = my_handle; result.guardNameEdit = guardNameEdit

    local guardAddStatus = addRow:Append("UIObject")
    guardAddStatus.Anchors = "3,0"; guardAddStatus.Font = "Medium20"
    guardAddStatus.TextalignmentH = "Left"; guardAddStatus.TextalignmentV = "Center"
    guardAddStatus.HasHover = "No"; result.guardAddStatus = guardAddStatus

    local intEdit = addRow:Append("LineEdit")
    intEdit.Anchors = "4,0"; intEdit.Content = tostring(guardInterval)
    intEdit.Texture = "corner0"; intEdit.VKPluginName = "TextInput"
    intEdit.Filter = "1234567890"; intEdit.PluginComponent = my_handle
    intEdit.Message = "Interval (s)"; result.guardIntEdit = intEdit

    local ctrlRow = fr:Append("UILayoutGrid")
    ctrlRow.Anchors = "0,4"; ctrlRow.Columns = 2; ctrlRow.Rows = 1
    local toggleBtn = ctrlRow:Append("Button")
    toggleBtn.Anchors = "0,0"
    toggleBtn.Text = guardRunning and "Stop Guard" or "Start Guard"
    toggleBtn.Font = "Medium20"; toggleBtn.Textshadow = 1; toggleBtn.HasHover = "Yes"
    toggleBtn.TextalignmentH = "Centre"
    toggleBtn.BackColor = guardRunning and C_GREEN or C_RED
    toggleBtn.PluginComponent = my_handle; toggleBtn.Clicked = "GuardToggle"
    result.guardToggle = toggleBtn
    local guardStLbl = ctrlRow:Append("UIObject")
    guardStLbl.Anchors = "1,0"; guardStLbl.Font = "Medium20"
    guardStLbl.TextalignmentH = "Center"; guardStLbl.TextalignmentV = "Center"
    guardStLbl.HasHover = "No"
    guardStLbl.Text = guardRunning and ("Running — every " .. guardInterval .. "s") or "Stopped"
    result.guardStLbl = guardStLbl

    closeBtn(fr, 5)

    addResizer(win)
    guardWin = result
    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- Guard live update helper
--------------------------------------------------------------------------------
local function guardUpdateUI(i, ip)
    if not (guardWin and guardWin.guardCells and guardWin.guardCells[i]) then return end
    pcall(function()
        local c     = guardWin.guardCells[i]
        local alive = guardStatus[ip]
        c.ind.BackColor = alive == true and C_GREEN or (alive == false and C_RED or C_DIM)
        c.st.Text       = alive == true and "UP" or (alive == false and "DOWN" or "—")
    end)
end

local function guardTick()
    if not guardRunning or #guardIPs == 0 then return end
    for i, ip in ipairs(guardIPs) do
        local outFile, doneFile, d = startPing(ip, 1)
        table.insert(guardPingResults, {i=i, ip=ip, out=outFile, done=doneFile, d=d})
    end
end

local function showGuardAlert(msg)
    if guardAlertWin then
            pcall(function()
            if guardAlertWin.msgLbl then
                guardAlertWin.msgLbl.Text = guardAlertWin.msgLbl.Text .. "\n" .. msg
            end
        end)
        return
    end
    local overlay = getOverlay()
    local win = overlay:Append("BaseInput")
    win.Name = "Guard Alert"; win.W = 460; win.H = 230
    win.Rows = 2; win.Columns = 1
    win[1][1].SizePolicy = "Fixed"; win[1][1].Size = 40
    win[1][2].SizePolicy = "Stretch"
    win.AutoClose = "No"; win.CloseOnEscape = "Yes"

    local tb = win:Append("TitleBar")
    tb.Columns = 2; tb.Rows = 1; tb.Anchors = "0,0"; tb.Texture = "corner2"
    tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "50"
    local ttl = tb:Append("TitleButton")
    ttl.Text = "Guard Alert"; ttl.Texture = "corner1"; ttl.Anchors = "0,0"; ttl.Icon = "warning"
    local clsBtn = tb:Append("Button")
    clsBtn.Anchors = "1,0"; clsBtn.Icon = "close"
    clsBtn.HasHover = "Yes"; clsBtn.Texture = "corner2"
    clsBtn.PluginComponent = my_handle; clsBtn.Clicked = "GuardAlertClose"

    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"
    fr.Columns = 1; fr.Rows = 2
    fr[1][1].SizePolicy = "Stretch"
    fr[1][2].SizePolicy = "Fixed"; fr[1][2].Size = "55"

    local msgLbl = fr:Append("UIObject")
    msgLbl.Anchors = "0,0"; msgLbl.Text = msg
    msgLbl.Font = "Medium20"; msgLbl.TextalignmentH = "Left"
    msgLbl.TextalignmentV = "Top"; msgLbl.HasHover = "No"; msgLbl.Padding = "12,8"

    local btnRow = fr:Append("UILayoutGrid")
    btnRow.Anchors = "0,1"; btnRow.Columns = 1; btnRow.Rows = 1
    local okBtn = btnRow:Append("Button")
    okBtn.Anchors = "0,0"; okBtn.Text = "OK"
    okBtn.Font = "Medium20"; okBtn.Textshadow = 1; okBtn.HasHover = "Yes"
    okBtn.TextalignmentH = "Centre"; okBtn.BackColor = C_RED
    okBtn.PluginComponent = my_handle; okBtn.Clicked = "GuardAlertClose"

    guardAlertWin = {win=win, overlay=overlay, msgLbl=msgLbl}
end

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
    win.Name = "Update Available"; win.W = 440; win.H = 190
    win.Rows = 2; win.Columns = 1
    win[1][1].SizePolicy = "Fixed"; win[1][1].Size = 40
    win[1][2].SizePolicy = "Stretch"
    win.AutoClose = "No"; win.CloseOnEscape = "Yes"
    local tb = win:Append("TitleBar")
    tb.Columns = 2; tb.Rows = 1; tb.Anchors = "0,0"; tb.Texture = "corner2"
    tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "50"
    local ttl = tb:Append("TitleButton")
    ttl.Text = "Update Available"; ttl.Texture = "corner1"; ttl.Anchors = "0,0"; ttl.Icon = "download"
    local cls = tb:Append("CloseButton"); cls.Anchors = "1,0"; cls.Texture = "corner2"
    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"; fr.Columns = 1; fr.Rows = 2
    fr[1][1].SizePolicy = "Stretch"; fr[1][2].SizePolicy = "Fixed"; fr[1][2].Size = "55"
    local msg = fr:Append("UIObject"); msg.Anchors = "0,0"
    msg.Text = _T60_PLUGIN_ID .. " " .. latest .. " is available.\n"
             .. "You are running v" .. pluginVersion .. ".\n\n"
             .. "github.com/tminus60/GrandMA3-Plugins"
    msg.Font = "Medium20"; msg.TextalignmentH = "Center"
    msg.TextalignmentV = "Center"; msg.HasHover = "No"
    local br = fr:Append("UILayoutGrid"); br.Anchors = "0,1"; br.Columns = 1; br.Rows = 1
    local btn = br:Append("Button"); btn.Anchors = "0,0"; btn.Text = "OK"
    btn.Font = "Medium20"; btn.Textshadow = 1; btn.HasHover = "Yes"; btn.TextalignmentH = "Centre"
    btn.BackColor = Root().ColorTheme.ColorGroups.Global.PartlySelected
    btn.PluginComponent = my_handle; btn.Clicked = "_T60UpdateClose"
    _t60UpdateWin = {win=win, overlay=ov}
end
local function _t60CheckUpdate()
    if not _T60_UPDATE_URL or _T60_UPDATE_URL == "" then return end
    local tmp = GetPath(Enums.PathType.Temp)
    local out  = tmp .. "/t60_update.txt"
    local done = tmp .. "/t60_update_done.txt"
    pcall(function()
        if HostOS() == "Windows" then
            os.execute('del "' .. out:gsub("/","\\") .. '" "' .. done:gsub("/","\\") .. '" 2>nul || ver>nul')
        else os.execute('rm -f "' .. out .. '" "' .. done .. '" ; true') end
    end)
    if HostOS() == "Windows" then
        local bat = tmp .. "\\t60_update.bat"
        local f = io.open(bat, "w"); if not f then return end
        f:write("@echo off\r\n")
        f:write('powershell -NonInteractive -WindowStyle Hidden -Command '
            .. '"try{(New-Object Net.WebClient).DownloadFile(\''
            .. _T60_UPDATE_URL .. '\',\'' .. out:gsub("/","\\"):gsub("'","''") .. '\')}catch{}"\r\n')
        f:write('echo done > "' .. done:gsub("/","\\") .. '"\r\n')
        f:close()
        os.execute('start /b cmd /c "' .. bat .. '"')
    else
        os.execute('curl -sf --max-time 5 "' .. _T60_UPDATE_URL .. '" -o "' .. out .. '"'
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
            if vn(latest) > vn(pluginVersion) then pcall(_t60ShowUpdate, latest) end
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
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local function guardPoll()
    if #guardPingResults == 0 then return end
    local remaining, alerts = {}, {}
    for _, r in ipairs(guardPingResults) do
        local f = io.open(r.done, "r")
        if f then
            f:close()
            local raw   = readFile(r.out)
            local lower = raw:lower()
            local alive = lower:find("ttl=") ~= nil or lower:find("bytes from") ~= nil
            local prev  = guardStatus[r.ip]
            guardStatus[r.ip] = alive
            local name  = guardNames[r.ip] or ""
            local label = name ~= "" and (name .. " (" .. r.ip .. ")") or r.ip
            if prev == true and not alive then
                table.insert(alerts, label .. " — DOWN")
            elseif prev == false and alive then
                table.insert(alerts, label .. " — back UP")
            end
            guardUpdateUI(r.i, r.ip)
        else
            table.insert(remaining, r)
        end
    end
    guardPingResults = remaining
    if #alerts > 0 then
        local alertMsg = table.concat(alerts, "\n")
        guardPendingAlert = alertMsg
        pcall(function()
            if guardWin and guardWin.guardStLbl then
                guardWin.guardStLbl.Text = alerts[1]
            end
        end)
        pcall(function()
            if dialog and dialog.guardBtn then
                dialog.guardBtn.Text = "ALERT"
                dialog.guardBtn.BackColor = C_ORANGE
            end
        end)
        pcall(showGuardAlert, alertMsg)
    end
end

local function cancelTimer()
    if guardTimer then
        pcall(function() guardTimer:Cancel() end)
        guardTimer = nil
    end
end

local function startGuard()
    if guardRunning then return end
    guardRunning = true
    safePoll(guardTick)()
    guardTimer = Timer(function()
        if not guardRunning then return false end
        safePoll(guardPoll)()
        safePoll(guardTick)()
    end, guardInterval, 0.5)
end

local function stopGuard()
    guardRunning = false
    cancelTimer()
    guardPingResults = {}
end

--------------------------------------------------------------------------------
-- ── SIGNAL CALLBACKS ──────────────────────────────────────────────────────────
--------------------------------------------------------------------------------
signalTable.CloseWin = safe(function()
    if dialog then
        if dialog == guardWin then guardWin = nil end
        Obj.Delete(dialog.overlay, Obj.Index(dialog.win))
    end
    dialog = fct.buildLauncher()
end)

local function openTool(builder)
    Obj.Delete(dialog.overlay, Obj.Index(dialog.win))
    dialog = builder()
end

for _, t in ipairs({{"Ping",fct.buildPingWin},{"Sweep",fct.buildSweepWin},{"Fav",fct.buildFavWin}}) do
    signalTable["Lnch_"..t[1]] = safe(function() openTool(t[2]) end)
end

signalTable.Lnch_Guard = safe(function()
    openTool(fct.buildGuardWin)
    guardPendingAlert = nil
end)

-- Validation
signalTable.OnChangeAll = safe(function()
    if dialog.pingEdit then
        local ready = (dialog.pingEdit.Content or "") ~= ""
        dialog.pingBtn.Enabled   = ready and "Yes" or "No"
        dialog.pingBtn.BackColor = ready and C_GREEN or C_RED
    end
    if dialog.startEdit then
        local sIP = parseIP(dialog.startEdit.Content or "")
        local eIP = parseIP(dialog.endEdit.Content   or "")
        local ready, msg = false, ""
        if sIP and eIP then
            if sIP[1]~=eIP[1] or sIP[2]~=eIP[2] or sIP[3]~=eIP[3] then msg = "Must be same /24."
            elseif eIP[4] <= sIP[4] then msg = "End must be > Start."
            else msg = eIP[4]-sIP[4]+1 .. " hosts"; ready = true end
        elseif (dialog.startEdit.Content or "")~="" or (dialog.endEdit.Content or "")~="" then
            msg = "Invalid IP."
        end
        dialog.sweepBtn.Enabled   = ready and "Yes" or "No"
        dialog.sweepBtn.BackColor = ready and C_GREEN or C_RED
        dialog.sweepStatus.Text   = msg
    end
end)

-- Single Ping
signalTable.PingBtn = safe(function()
    local host = dialog.pingEdit.Content or ""
    if host == "" then return end
    dialog.pingBtn.Enabled = "No"; dialog.pingBtn.BackColor = C_RED
    dialog.pingResult.Text = "Pinging " .. host .. " ..."
    local outFile, doneFile, d = startPing(host, 4)
    local done = false
    Timer(safePoll(function()
        if done then return end
        local f = io.open(doneFile, "r"); if not f then return end
        f:close(); done = true
        local raw = readFile(outFile)
        dialog.pingResult.Text   = raw ~= "" and raw or ("No response from " .. host)
        dialog.pingBtn.Enabled   = "Yes"
        dialog.pingBtn.BackColor = C_GREEN
        cleanup(d)
    end), 0, 0.5)
end)

signalTable.SweepBtn = safe(function()
    local sIP = parseIP(dialog.startEdit.Content or "")
    local eIP = parseIP(dialog.endEdit.Content   or "")
    if not (sIP and eIP) then return end
    local base  = string.format("%d.%d.%d", sIP[1], sIP[2], sIP[3])
    local s, e  = sIP[4], eIP[4]
    local count = e - s + 1
    dialog.sweepBtn.Enabled = "No"; dialog.sweepBtn.BackColor = C_RED
    dialog.sweepStatus.Text = string.format("Scanning %s.%d – %s.%d …", base, s, base, e)

    local idx = StartProgress(string.format("Sweeping %s.%d – %s.%d (%d hosts)", base, s, base, e, count))
    local resFile, d = runSweepSync(base, s, e)
    StopProgress(idx)

    local raw    = readFile(resFile)
    local active = {}
    for ip in raw:gmatch("(%d+%.%d+%.%d+%.%d+)") do table.insert(active, ip) end
    table.sort(active, function(a, b)
        return (tonumber(a:match("(%d+)$")) or 0) < (tonumber(b:match("(%d+)$")) or 0)
    end)

    local savedIPs = {}
    for _, f in ipairs(loadFavorites()) do savedIPs[f.ip] = true end
    for i = 1, MAX_SW do
        local ip = active[i]
        showRow(dialog.sweepRowH, i, ip ~= nil)
        if ip then
            local c   = dialog.sweepCells[i]
            local mac = getMACForIP(ip)
            c.ind.BackColor = C_GREEN
            c.ip.Text       = ip
            c.mac.Text      = mac
            c.loss.Text     = "0%"
            c.res.Text      = "1 / 1"
            c.fav.BackColor = savedIPs[ip] and C_GREEN or C_ORANGE
            dialog.sweepIPs[i] = ip
        end
    end
    for i = #active + 1, MAX_SW do
        showRow(dialog.sweepRowH, i, false)
        dialog.sweepIPs[i] = nil
    end

    local shown = math.min(#active, MAX_SW)
    if dialog.sweepGrid then dialog.sweepGrid.H = shown * ROW_H end
    local extra = #active > MAX_SW and ("  +" .. (#active - MAX_SW) .. " more") or ""
    dialog.sweepStatus.Text = string.format("Done — %d / %d active%s", #active, count, extra)
    dialog.sweepBtn.Enabled = "Yes"; dialog.sweepBtn.BackColor = C_GREEN
    cleanup(d)
end)

for i = 1, MAX_SW do
    local idx = i
    signalTable["SwPing_" .. idx] = safe(function()
        local ip = dialog.sweepIPs and dialog.sweepIPs[idx]
        if not ip then return end
        local c = dialog.sweepCells[idx]; if not c then return end
        c.ping.Enabled = "No"; c.ping.BackColor = C_DIM
        c.res.Text = "Pinging…"
        local outFile, doneFile, d = startPing(ip, 5)
        local done = false
        Timer(safePoll(function()
            if done then return end
            local f = io.open(doneFile, "r"); if not f then return end
            f:close(); done = true
            local _, sent, recv, avg, loss = parsePingOutput(readFile(outFile), 5)
            c.ind.BackColor  = recv > 0 and C_GREEN or C_RED
            c.mac.Text       = getMACForIP(ip)
            c.loss.Text      = loss .. "%"
            c.res.Text       = recv .. " / " .. sent .. (avg and ("  " .. avg .. "ms") or "")
            c.ping.Enabled   = "Yes"
            c.ping.BackColor = recv > 0 and C_BLUE or C_RED
            cleanup(d)
        end), 0, 0.5)
    end)
end

for i = 1, MAX_SW do
    local idx = i
    signalTable["SwFav_" .. idx] = safe(function()
        local ip = dialog.sweepIPs and dialog.sweepIPs[idx]
        if not ip then return end
        local favs = loadFavorites()
        for _, f in ipairs(favs) do
            if f.ip == ip then
                local c = dialog.sweepCells and dialog.sweepCells[idx]
                if c then c.fav.BackColor = C_GREEN end
                return
            end
        end
        table.insert(favs, {ip=ip, name="", last_ok=false, last_ms="", last_mac=""})
        saveFavorites(favs)
        local c = dialog.sweepCells and dialog.sweepCells[idx]
        if c then c.fav.BackColor = C_GREEN end
    end)
end

signalTable.FavAdd = safe(function()
    local ip   = trimStr(dialog.favIPEdit   and dialog.favIPEdit.Content   or "")
    local name = trimStr(dialog.favNameEdit and dialog.favNameEdit.Content or "")
    if not parseIP(ip) then
        if dialog.favStatus then
            dialog.favStatus.Text = ip ~= "" and "Invalid IP." or "Enter an IP."
        end
        return
    end
    local favs = loadFavorites()
    for _, f in ipairs(favs) do
        if f.ip == ip then
            if dialog.favStatus then dialog.favStatus.Text = ip .. " already saved." end
            return
        end
    end
    table.insert(favs, {ip=ip, name=name, last_ok=false, last_ms="", last_mac=""})
    saveFavorites(favs)
    openTool(fct.buildFavWin)
end)

for i = 1, MAX_FV do
    local idx = i
    signalTable["FavPing_" .. idx] = safe(function()
        local favs = loadFavorites()
        local fav  = favs[idx]; if not fav then return end
        local c    = dialog.favCells[idx]
        if c then c.ping.Enabled = "No"; c.ping.BackColor = C_RED end
        if dialog.favStatus then dialog.favStatus.Text = "Pinging " .. fav.ip .. " ..." end
        local outFile, doneFile, d = startPing(fav.ip, 4)
        local done = false
        Timer(safePoll(function()
            if done then return end
            local f = io.open(doneFile, "r"); if not f then return end
            f:close(); done = true
            local alive, sent, recv, ms, loss = parsePingOutput(readFile(outFile), 4)
            local mac   = alive and getMACForIP(fav.ip) or (fav.last_mac or "—")
            local favs2 = loadFavorites()
            for _, fv in ipairs(favs2) do
                if fv.ip == fav.ip then
                    fv.last_ok = alive ~= nil; fv.last_ms = ms or ""
                    fv.last_mac = mac ~= "—" and mac or (fv.last_mac or ""); break
                end
            end
            saveFavorites(favs2)
            if c then
                c.ind.BackColor = alive and C_GREEN or C_RED
                c.mac.Text = mac; c.loss.Text = loss .. "%"
                c.res.Text = recv .. "/" .. sent .. (ms and ("  " .. ms .. "ms") or "")
                c.ping.Enabled = "Yes"; c.ping.BackColor = C_GREEN
            end
            if dialog.favStatus then dialog.favStatus.Text = fav.ip .. ": " .. (alive and "UP" or "DOWN") end
            cleanup(d)
        end), 0, 0.5)
    end)

    signalTable["FavDel_" .. idx] = safe(function()
        local favs = loadFavorites()
        if not favs[idx] then return end
        table.remove(favs, idx)
        saveFavorites(favs)
        openTool(fct.buildFavWin)
    end)
end

for i = 1, MAX_FV do
    local idx = i
    signalTable["FavMore_" .. idx] = safe(function()
        local favs = loadFavorites()
        local fav = favs[idx]; if not fav then return end
        local r = MessageBox({
            title   = fav.ip,
            message = "Name: " .. (fav.name ~= "" and fav.name or "(unnamed)"),
            commands = {
                {value=1, name="Back"},
                {value=2, name="Rename"},
                {value=3, name="Add to Guard"},
            }
        })
        if not r then return end
        if r.result == 2 then
            local newName = TextInput("Rename " .. fav.ip, fav.name or "")
            if newName == nil then return end
            favs[idx].name = trimStr(newName)
            saveFavorites(favs)
            local c = dialog.favCells and dialog.favCells[idx]
            if c then c.name.Text = favs[idx].name ~= "" and favs[idx].name or "(unnamed)" end
        elseif r.result == 3 then
            for _, ip in ipairs(guardIPs) do
                if ip == fav.ip then
                    if dialog.favStatus then dialog.favStatus.Text = fav.ip .. " already in Guard." end
                    return
                end
            end
            table.insert(guardIPs, fav.ip)
            guardNames[fav.ip] = fav.name or ""
            guardStatus[fav.ip] = nil
            saveGuardConfig({entries=buildGuardEntries(), interval=guardInterval})
            if guardWin and guardWin.guardCells then
                local n = #guardIPs
                if n <= MAX_GD then
                    showRow(guardWin.guardRowH, n, true)
                    local c = guardWin.guardCells[n]
                    if c then
                        c.ip.Text = fav.ip; c.name.Text = fav.name or ""
                        c.ind.BackColor = C_DIM; c.st.Text = "—"
                    end
                    if guardWin.guardGrid then guardWin.guardGrid.H = n * ROW_H end
                end
            end
            if dialog.favStatus then dialog.favStatus.Text = fav.ip .. " → Guard." end
        end
    end)
end

signalTable.FavPingAll = safe(function()
    local favs = loadFavorites()
    if #favs == 0 then return end
    local count = math.min(#favs, MAX_FV)
    local ips = {}
    for i = 1, count do ips[i] = favs[i].ip end

    if dialog.pingAllBtn then dialog.pingAllBtn.Enabled = "No"; dialog.pingAllBtn.BackColor = C_DIM end
    if dialog.favStatus  then dialog.favStatus.Text = "Pinging " .. count .. " hosts…" end
    for i = 1, count do
        local c = dialog.favCells and dialog.favCells[i]
        if c then c.ping.Enabled = "No"; c.ping.BackColor = C_DIM; c.res.Text = "…" end
    end

    local d, doneFile = startPingAllAsync(ips)
    local finished = false
    Timer(safePoll(function()
        if finished then return end
        local f = io.open(doneFile, "r"); if not f then return end
        f:close(); finished = true

        local favs2 = loadFavorites()
        for i = 1, count do
            local fav   = favs[i]
            local alive, sent, recv, ms, loss = parsePingOutput(readFile(d .. "/ip" .. i .. ".txt"), 4)
            local mac   = alive and getMACForIP(fav.ip) or (fav.last_mac or "—")
            for _, fv in ipairs(favs2) do
                if fv.ip == fav.ip then
                    fv.last_ok = alive ~= nil; fv.last_ms = ms or ""
                    fv.last_mac = mac ~= "—" and mac or (fv.last_mac or ""); break
                end
            end
            local c = dialog.favCells and dialog.favCells[i]
            if c then
                c.ind.BackColor = alive and C_GREEN or C_RED
                c.mac.Text = mac; c.loss.Text = loss .. "%"
                c.res.Text = recv .. "/" .. sent .. (ms and ("  " .. ms .. "ms") or "")
                c.ping.Enabled = "Yes"; c.ping.BackColor = C_GREEN
            end
        end
        saveFavorites(favs2)
        if dialog.pingAllBtn then dialog.pingAllBtn.Enabled = "Yes"; dialog.pingAllBtn.BackColor = C_BLUE end
        if dialog.favStatus  then dialog.favStatus.Text = "Done — " .. count .. " hosts." end
        cleanup(d)
    end), 0, 0.5)
end)

signalTable.GuardAdd = safe(function()
    local ip = trimStr(dialog.guardIPEdit and dialog.guardIPEdit.Content or "")
    if not parseIP(ip) then
        if dialog.guardAddStatus then
            dialog.guardAddStatus.Text = ip ~= "" and "Invalid IP." or "Enter an IP."
        end
        return
    end
    for _, existing in ipairs(guardIPs) do
        if existing == ip then
            if dialog.guardAddStatus then dialog.guardAddStatus.Text = ip .. " already monitored." end
            return
        end
    end
    local name = trimStr(dialog.guardNameEdit and dialog.guardNameEdit.Content or "")
    local interval = tonumber(dialog.guardIntEdit and dialog.guardIntEdit.Content) or guardInterval
    guardInterval = math.max(10, interval)
    table.insert(guardIPs, ip); guardStatus[ip] = nil; guardNames[ip] = name
    saveGuardConfig({entries=buildGuardEntries(), interval=guardInterval})
    openTool(fct.buildGuardWin)
end)

for i = 1, MAX_GD do
    local idx = i
    signalTable["GuardMore_" .. idx] = safe(function()
        local ip = guardIPs[idx]; if not ip then return end
        local name = guardNames[ip] or ""
        local r = MessageBox({
            title   = ip,
            message = "Name: " .. (name ~= "" and name or "(unnamed)"),
            commands = {
                {value=1, name="Back"},
                {value=2, name="Rename"},
                {value=3, name="Remove"},
            }
        })
        if not r then return end
        if r.result == 2 then
            local newName = TextInput("Rename " .. ip, name)
            if newName == nil then return end
            guardNames[ip] = trimStr(newName)
            saveGuardConfig({entries=buildGuardEntries(), interval=guardInterval})
            local c = guardWin and guardWin.guardCells and guardWin.guardCells[idx]
            if c then c.name.Text = guardNames[ip] end
        elseif r.result == 3 then
            table.remove(guardIPs, idx); guardStatus[ip] = nil; guardNames[ip] = nil
            saveGuardConfig({entries=buildGuardEntries(), interval=guardInterval})
            openTool(fct.buildGuardWin)
        end
    end)
end

signalTable.GuardToggle = safe(function()
    if guardRunning then
        stopGuard()
        if dialog.guardToggle then dialog.guardToggle.Text = "Start Guard"; dialog.guardToggle.BackColor = C_RED end
        if dialog.guardStLbl  then dialog.guardStLbl.Text = "Stopped" end
    else
        if #guardIPs == 0 then
            if dialog.guardAddStatus then dialog.guardAddStatus.Text = "Add at least one IP first." end
            return
        end
        startGuard()
        if dialog.guardToggle then dialog.guardToggle.Text = "Stop Guard"; dialog.guardToggle.BackColor = C_GREEN end
        if dialog.guardStLbl  then dialog.guardStLbl.Text = "Running — every " .. guardInterval .. "s" end
    end
end)

signalTable.GuardAlertClose = safe(function()
    if guardAlertWin then
        pcall(function() Obj.Delete(guardAlertWin.overlay, Obj.Index(guardAlertWin.win)) end)
        guardAlertWin = nil
    end
end)

--------------------------------------------------------------------------------
-- ── DISPLAY + FULLSCREEN ──────────────────────────────────────────────────────
--------------------------------------------------------------------------------
local DISP_GRID = {
    {5, "External 5",  0, 0},
    {4, "External 4",  0, 2},
    {3, "Internal 3",  1, 0},
    {2, "Internal 2",  1, 1},
    {1, "Internal 1",  1, 2},
    {7, "Small 7",     2, 1},
    {6, "Small 6",     2, 2},
}

function fct.buildDisplayPicker()
    if displayPicker then
        local alive = false
        pcall(function()
            local idx = Obj.Index(displayPicker.win)
            alive = (idx ~= nil and idx > 0)
        end)
        if alive then return end
        displayPicker = nil
    end

    local BTN_H = 110
    local WIN_W = 410
    local WIN_H = 60 + 3 * BTN_H

    local overlay, _ = getOverlay()
    local win = overlay:Append("BaseInput")
    win.Name = "Select Display"; win.W = WIN_W; win.H = WIN_H
    win.Rows = 2; win.Columns = 1
    win[1][1].SizePolicy = "Fixed"; win[1][1].Size = "60"
    win[1][2].SizePolicy = "Stretch"
    win.AutoClose = "Yes"; win.CloseOnEscape = "Yes"

    local tb = win:Append("TitleBar")
    tb.Columns = 2; tb.Rows = 1; tb.Anchors = "0,0"; tb.Texture = "corner2"
    tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "50"
    local ttl = tb:Append("TitleButton")
    ttl.Text = "Select Display"; ttl.Texture = "corner1"
    ttl.Anchors = "0,0"; ttl.Icon = "display"
    local clsBtn = tb:Append("CloseButton")
    clsBtn.Anchors = "1,0"; clsBtn.Texture = "corner2"

    local fr = win:Append("DialogFrame")
    fr.H = "100%"; fr.W = "100%"; fr.Anchors = "0,1"
    fr.Columns = 1; fr.Rows = 3
    fr[1][1].SizePolicy = "Fixed"; fr[1][1].Size = BTN_H
    fr[1][2].SizePolicy = "Fixed"; fr[1][2].Size = BTN_H
    fr[1][3].SizePolicy = "Fixed"; fr[1][3].Size = BTN_H

    local rowGrids = {}
    for r = 0, 2 do
        local g = fr:Append("UILayoutGrid")
        g.Anchors = "0," .. r; g.Columns = 3; g.Rows = 1
        rowGrids[r] = g
    end

    local occupied = {}
    for _, d in ipairs(DISP_GRID) do
        local idx, label, row, col = d[1], d[2], d[3], d[4]
        local btn = rowGrids[row]:Append("Button")
        btn.Anchors = col .. ",0"; btn.Text = label
        btn.Font = "Medium20"; btn.Textshadow = 1; btn.HasHover = "Yes"
        btn.TextalignmentH = "Centre"
        btn.BackColor = (idx == currentDisplayIdx) and C_ORANGE or C_DIM
        btn.Margin = "8,8,8,8"
        btn.PluginComponent = my_handle; btn.Clicked = "SelDisp_" .. idx
        occupied[row * 3 + col] = true
    end
    for r = 0, 2 do
        for c = 0, 2 do
            if not occupied[r * 3 + c] then
                local e = rowGrids[r]:Append("UIObject")
                e.Anchors = c .. ",0"; e.HasHover = "No"
                e.BackColor = C_CLEAR
            end
        end
    end

    local resizer = win:Append("ResizeCorner")
    resizer.Anchors = "0,1"
    resizer.AlignmentH = "Right"
    resizer.AlignmentV = "Bottom"

    displayPicker = {win = win, overlay = overlay}
end

signalTable.CycleDisplay = safe(function() fct.buildDisplayPicker() end)

for i = 1, 9 do
    local idx = i
    signalTable["SelDisp_" .. idx] = safe(function()
        if displayPicker then
            Obj.Delete(displayPicker.overlay, Obj.Index(displayPicker.win))
            displayPicker = nil
        end
        currentDisplayIdx = idx
        local wasGuard = (dialog == guardWin)
        Obj.Delete(dialog.overlay, Obj.Index(dialog.win))
        if wasGuard then guardWin = nil end
        dialog = (currentBuilderFn or fct.buildLauncher)()
    end)
end

signalTable.ToggleFullscreen = safe(function()
    if not (dialog and dialog.win) then return end
    local win  = dialog.win
    local name = win.Name
    if winNormalSizes[name] then
        local prev = winNormalSizes[name]
        pcall(function() win.W = prev.w; win.H = prev.h end)
        winNormalSizes[name] = nil
    else
        winNormalSizes[name] = {w = win.W, h = win.H}
        pcall(function()
            local d = GetDisplayByIndex(currentDisplayIdx)
            win.W = d.W or 1920
            win.H = d.H or 1080
        end)
    end
end)

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
