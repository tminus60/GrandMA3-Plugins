--
--  _   _      _                      _
-- | \ | |    | |                    | |
-- |  \| | ___| |___      _____  _ __| | __
-- | . ` |/ _ \ __\ \ /\ / / _ \| '__| |/ /
-- | |\  |  __/ |_ \ V  V / (_) | |  |   <
-- |_| \_|\___|\__| \_/\_/ \___/|_|  |_|\_\
--
--  ____  _
-- |  _ \(_)_ __   __ _
-- | |_) | | '_ \ / _` |
-- |  __/| | | | | (_| |
-- |_|   |_|_| |_|\__, |
--                |___/
--
--[[---------------------------------------------------------------------------
  Network Ping
  Ping a single host or sweep an entire IP range to find active devices.
  Sweep runs all pings in parallel — a full /24 takes ~3 seconds.

  Author:   t-60
  Version:  2.2.0
  GMA3:     tested on 2.3.2.0
  GitHub:   https://github.com/tminus60/GrandMA3-Plugins
  License:  t-60 Plugin License (Non-Commercial) — see bottom of file
---------------------------------------------------------------------------]]

local pluginVersion = "2.2.0"

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local my_handle     = select(4, ...)

local fct   = {}
local dialog

-- Colours — assigned in main() because Root() is only valid at runtime
local colorOrange, colorBlue, colorPlease, colorClear, colorTransparent

--------------------------------------------------------------------------------
-- IP helpers
--------------------------------------------------------------------------------

-- Parses "192.168.1.1" into {192, 168, 1, 1} or returns nil on invalid input.
local function parseIP(str)
    local a, b, c, d = str:match("^%s*(%d+)%.(%d+)%.(%d+)%.(%d+)%s*$")
    a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
    if not (a and b and c and d) then return nil end
    if a > 255 or b > 255 or c > 255 or d > 255 then return nil end
    return {a, b, c, d}
end

--------------------------------------------------------------------------------
-- Shell helpers
--
-- Both functions write a script to a temp folder, run it in the background,
-- and signal completion via a "done" marker file.
-- The caller polls the done file instead of streaming output — simpler and
-- more reliable across different GMA3/OS environments.
--------------------------------------------------------------------------------
local function makeTmpDir(prefix)
    local dir = GetPath(Enums.PathType.Temp)
        .. "/" .. prefix .. tostring(os.clock()):gsub("%.", "")
    if HostOS() == "Windows" then
        os.execute('mkdir "' .. dir .. '"')
    else
        os.execute('mkdir -p "' .. dir .. '"')
    end
    return dir
end

local function startPing(host)
    local tmpDir   = makeTmpDir("fd_ping_")
    local outFile  = tmpDir .. "/output.txt"
    local doneFile = tmpDir .. "/done.txt"

    if HostOS() == "Windows" then
        local f = io.open(tmpDir .. "/run.bat", "w")
        f:write("@echo off\r\n")
        f:write('ping -n 4 ' .. host .. ' > "' .. outFile .. '" 2>&1\r\n')
        f:write('echo done > "' .. doneFile .. '"\r\n')
        f:close()
        os.execute('start /b cmd /c "' .. tmpDir .. '\\run.bat"')
    else
        local f = io.open(tmpDir .. "/run.sh", "w")
        f:write("#!/bin/bash\n")
        f:write('ping -c 4 ' .. host .. ' > "' .. outFile .. '" 2>&1\n')
        f:write('echo done > "' .. doneFile .. '"\n')
        f:close()
        os.execute('chmod +x "' .. tmpDir .. '/run.sh" && "' .. tmpDir .. '/run.sh" &')
    end

    return outFile, doneFile, tmpDir
end

-- Pings all IPs in range in parallel and blocks until all finish.
-- Runs synchronously so the caller can read results immediately after return.
-- GMA3's progress bar animation plays during the block without needing
-- intermediate SetProgressRange updates.
local function runSweepSync(base, startOct, endOct)
    local tmpDir  = makeTmpDir("fd_sweep_")
    local resFile = tmpDir .. "/results.txt"

    if HostOS() == "Windows" then
        local f = io.open(tmpDir .. "/sweep.bat", "w")
        f:write("@echo off\r\n")
        for i = startOct, endOct do
            f:write(string.format(
                'start /b cmd /c "ping -n 1 -w 1000 %s.%d > nul 2>&1'
                    .. ' && echo %s.%d >> \\"%s\\""\r\n',
                base, i, base, i, resFile))
        end
        -- wait ~3 s for all parallel pings (1 s timeout + 2 s buffer)
        f:write("ping -n 4 127.0.0.1 > nul\r\n")
        f:close()
        -- run synchronously so this call blocks until all pings are done
        os.execute('cmd /c "' .. tmpDir .. '\\sweep.bat"')
    else
        local f = io.open(tmpDir .. "/sweep.sh", "w")
        f:write("#!/bin/bash\n")
        for i = startOct, endOct do
            f:write(string.format(
                '(ping -c 1 -W 1 %s.%d > /dev/null 2>&1'
                    .. ' && echo "%s.%d" >> "%s") &\n',
                base, i, base, i, resFile))
        end
        f:write("wait\n")
        f:close()
        os.execute('bash "' .. tmpDir .. '/sweep.sh"')
    end

    return resFile, tmpDir
end

local function cleanup(tmpDir)
    if HostOS() == "Windows" then
        os.execute('rmdir /s /q "' .. tmpDir .. '"')
    else
        os.execute('rm -rf "' .. tmpDir .. '"')
    end
end

--------------------------------------------------------------------------------
-- Crash Handler + safe() wrapper
--------------------------------------------------------------------------------
local function crashHandler(err)
    local path = GetPath(Enums.PathType.Temp) .. "/" .. pluginName .. "_crash.log"
    local f = io.open(path, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ")
            .. "v" .. pluginVersion .. " | " .. tostring(err) .. "\n")
        f:close()
    end
    Printf("[ERROR] " .. pluginName .. " v" .. pluginVersion .. ": " .. tostring(err))
    MessageBox({
        title          = "Plugin Error — " .. pluginName,
        backColor      = "Global.Focus",
        icon           = "warning",
        titleTextColor = "Global.Text",
        message        = pluginName .. " v" .. pluginVersion
                         .. " encountered an error.\n\n" .. tostring(err)
                         .. "\n\nCrash log: " .. path,
        commands       = {{value = 0, name = "Close"}},
    })
end

local function safe(fn)
    return function(caller, ...)
        local ok, err = pcall(fn, caller, ...)
        if not ok then crashHandler(err) end
    end
end

-- Wraps a poll function so Lua exceptions are caught internally.
-- Without this, GMA3 shows "LUA engine caught an exception" for every Timer tick.
local function safePoll(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then Printf("[ERROR] poll: " .. tostring(err)) end
    end
end

--------------------------------------------------------------------------------
-- Shared UI helper — section header bar (matches Parameter Calculator style)
--------------------------------------------------------------------------------
local function buildSectionHeader(parent, anchor, text, color)
    local row = parent:Append("UILayoutGrid")
    row.Anchors = "0," .. anchor; row.Columns = 1; row.Rows = 1
    local lbl = row:Append("UIObject")
    lbl.Anchors = "0,0"; lbl.Text = text
    lbl.Font = "Medium20"; lbl.TextalignmentH = "Center"
    lbl.HasHover = "No"; lbl.BackColor = color
    return lbl
end

--------------------------------------------------------------------------------
-- Main — opens the launcher / tool selector
--------------------------------------------------------------------------------
local function main()
    colorOrange      = Root().ColorTheme.ColorGroups.Global.PartlySelected
    colorBlue        = Root().ColorTheme.ColorGroups.Assignment.Group
    colorPlease      = Root().ColorTheme.ColorGroups.Button.BackgroundPlease
    colorClear       = Root().ColorTheme.ColorGroups.Button.BackgroundClear
    colorTransparent = Root().ColorTheme.ColorGroups.Global.Transparent

    local shortcuts = CurrentProfile().KeyboardShortCuts
    shortcuts.KeyboardShortcutsActive = false
    dialog = fct.buildLauncherMenu()
end

--------------------------------------------------------------------------------
-- Launcher menu — tool selection
--------------------------------------------------------------------------------
function fct.buildLauncherMenu()
    local result = {}
    local display = GetDisplayByIndex(1)
    local overlay = display.ScreenOverlay
    result.display = display
    result.overlay = overlay

    local mainDialog = overlay:Append("BaseInput")
    mainDialog.Name          = "Network Tools"
    mainDialog.H             = 420
    mainDialog.W             = 750
    mainDialog.Rows          = 2
    mainDialog.Columns       = 1
    mainDialog[1][1].SizePolicy = "Fixed"; mainDialog[1][1].Size = "60"
    mainDialog[1][2].SizePolicy = "Stretch"
    mainDialog.AutoClose     = "No"
    mainDialog.CloseOnEscape = "Yes"
    result.dialog = mainDialog

    local titleBar = mainDialog:Append("TitleBar")
    titleBar.Columns = 2; titleBar.Rows = 1; titleBar.Anchors = "0,0"
    titleBar[2][2].SizePolicy = "Fixed"; titleBar[2][2].Size = "50"
    titleBar.Texture = "corner2"
    local titleBtn = titleBar:Append("TitleButton")
    titleBtn.Text = "Network Tools"; titleBtn.Texture = "corner1"
    titleBtn.Anchors = "0,0"; titleBtn.Icon = "object_appear"
    local closeBtn = titleBar:Append("CloseButton")
    closeBtn.Anchors = "1,0"; closeBtn.Texture = "corner2"

    local dlgFrame = mainDialog:Append("DialogFrame")
    dlgFrame.H = "100%"; dlgFrame.W = "100%"
    dlgFrame.Columns = 1; dlgFrame.Rows = 5
    dlgFrame[1][2].SizePolicy = "Stretch"
    dlgFrame[1][4].SizePolicy = "Stretch"

    -- Ping card
    buildSectionHeader(dlgFrame, 0, "Single Ping", colorOrange)

    local pingCard = dlgFrame:Append("UILayoutGrid")
    pingCard.Anchors = "0,1"; pingCard.Columns = 2; pingCard.Rows = 1
    pingCard[2][2].SizePolicy = "Fixed"; pingCard[2][2].Size = "120"

    local pingDesc = pingCard:Append("UIObject")
    pingDesc.Anchors = "0,0"
    pingDesc.Text = "Ping a host or IP address and display the result."
    pingDesc.Font = "Medium20"; pingDesc.TextalignmentH = "Left"
    pingDesc.TextalignmentV = "Center"; pingDesc.HasHover = "No"
    pingDesc.BackColor = colorTransparent; pingDesc.Margin = "8,2,2,2"

    local pingOpenBtn = pingCard:Append("Button")
    pingOpenBtn.Anchors = "1,0"; pingOpenBtn.Text = "Open"
    pingOpenBtn.Font = "Medium20"; pingOpenBtn.Textshadow = 1
    pingOpenBtn.HasHover = "Yes"; pingOpenBtn.TextalignmentH = "Centre"
    pingOpenBtn.PluginComponent = my_handle; pingOpenBtn.Clicked = "LauncherPingClicked"
    pingOpenBtn.BackColor = colorOrange

    -- Sweep card
    buildSectionHeader(dlgFrame, 2, "Ping Sweep", colorBlue)

    local sweepCard = dlgFrame:Append("UILayoutGrid")
    sweepCard.Anchors = "0,3"; sweepCard.Columns = 2; sweepCard.Rows = 1
    sweepCard[2][2].SizePolicy = "Fixed"; sweepCard[2][2].Size = "120"

    local sweepDesc = sweepCard:Append("UIObject")
    sweepDesc.Anchors = "0,0"
    sweepDesc.Text = "Scan an IP range for active devices. All pings run in parallel."
    sweepDesc.Font = "Medium20"; sweepDesc.TextalignmentH = "Left"
    sweepDesc.TextalignmentV = "Center"; sweepDesc.HasHover = "No"
    sweepDesc.BackColor = colorTransparent; sweepDesc.Margin = "8,2,2,2"

    local sweepOpenBtn = sweepCard:Append("Button")
    sweepOpenBtn.Anchors = "1,0"; sweepOpenBtn.Text = "Open"
    sweepOpenBtn.Font = "Medium20"; sweepOpenBtn.Textshadow = 1
    sweepOpenBtn.HasHover = "Yes"; sweepOpenBtn.TextalignmentH = "Centre"
    sweepOpenBtn.PluginComponent = my_handle; sweepOpenBtn.Clicked = "LauncherSweepClicked"
    sweepOpenBtn.BackColor = colorBlue

    -- Close
    local closeRow = dlgFrame:Append("UILayoutGrid")
    closeRow.Anchors = "0,4"; closeRow.Columns = 1; closeRow.Rows = 1
    local cancelBtn = closeRow:Append("Button")
    cancelBtn.Anchors = "0,0"; cancelBtn.Text = "Close"; cancelBtn.Font = "Medium20"
    cancelBtn.Textshadow = 1; cancelBtn.HasHover = "Yes"; cancelBtn.TextalignmentH = "Centre"
    cancelBtn.PluginComponent = my_handle; cancelBtn.Clicked = "CancelButtonClicked"

    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- Single Ping window
--------------------------------------------------------------------------------
function fct.buildPingMenu()
    local result = {}
    local display = GetDisplayByIndex(1)
    local overlay = display.ScreenOverlay
    result.display = display
    result.overlay = overlay

    local mainDialog = overlay:Append("BaseInput")
    mainDialog.Name = "Network Ping"
    mainDialog.H = 500; mainDialog.W = 700
    mainDialog.Rows = 2; mainDialog.Columns = 1
    mainDialog[1][1].SizePolicy = "Fixed"; mainDialog[1][1].Size = "60"
    mainDialog[1][2].SizePolicy = "Stretch"
    mainDialog.AutoClose = "No"; mainDialog.CloseOnEscape = "Yes"
    result.dialog = mainDialog

    local titleBar = mainDialog:Append("TitleBar")
    titleBar.Columns = 2; titleBar.Rows = 1; titleBar.Anchors = "0,0"
    titleBar[2][2].SizePolicy = "Fixed"; titleBar[2][2].Size = "50"
    titleBar.Texture = "corner2"
    local titleBtn = titleBar:Append("TitleButton")
    titleBtn.Text = "Single Ping"; titleBtn.Texture = "corner1"
    titleBtn.Anchors = "0,0"; titleBtn.Icon = "object_appear"
    local closeBtn = titleBar:Append("CloseButton")
    closeBtn.Anchors = "1,0"; closeBtn.Texture = "corner2"

    -- 4 rows: settings header | input+button | result header | result area
    local dlgFrame = mainDialog:Append("DialogFrame")
    dlgFrame.H = "100%"; dlgFrame.W = "100%"
    dlgFrame.Columns = 1; dlgFrame.Rows = 4
    dlgFrame[1][1].SizePolicy = "Fixed";   dlgFrame[1][1].Size = "42"
    dlgFrame[1][2].SizePolicy = "Fixed";   dlgFrame[1][2].Size = "60"
    dlgFrame[1][3].SizePolicy = "Fixed";   dlgFrame[1][3].Size = "42"
    dlgFrame[1][4].SizePolicy = "Stretch"

    buildSectionHeader(dlgFrame, 0, "Settings", colorOrange)

    -- Host/IP input + Ping button (no icon boxes)
    local inputRow = dlgFrame:Append("UILayoutGrid")
    inputRow.Anchors = "0,1"; inputRow.Columns = 3; inputRow.Rows = 1
    inputRow[2][1].SizePolicy = "Fixed";   inputRow[2][1].Size = "150"
    inputRow[2][2].SizePolicy = "Stretch"
    inputRow[2][3].SizePolicy = "Fixed";   inputRow[2][3].Size = "110"

    local lbl = inputRow:Append("UIObject")
    lbl.Anchors = "0,0"; lbl.Text = "Host / IP"
    lbl.Font = "Medium20"; lbl.TextalignmentH = "Left"
    lbl.HasHover = "No"; lbl.Margin = "0,0,0,0"

    local pingEdit = inputRow:Append("LineEdit")
    pingEdit.Anchors = "1,0"; pingEdit.Message = "192.168.1.1"
    pingEdit.Texture = "corner0"; pingEdit.Focus = "InitialFocus"
    pingEdit.TextChanged = "OnChangeAll"
    pingEdit.PluginComponent = my_handle; pingEdit.VKPluginName = "TextInput"
    pingEdit.ToolTip = "Enter hostname or IP address to ping."
    result.pingEdit = pingEdit

    local pingBtn = inputRow:Append("Button")
    pingBtn.Anchors = "2,0"; pingBtn.Text = "Ping"; pingBtn.Font = "Medium20"
    pingBtn.Textshadow = 1; pingBtn.HasHover = "Yes"; pingBtn.TextalignmentH = "Centre"
    pingBtn.PluginComponent = my_handle; pingBtn.Clicked = "PingButtonClicked"
    pingBtn.BackColor = colorClear; pingBtn.Enabled = "No"
    result.pingBtn = pingBtn

    buildSectionHeader(dlgFrame, 2, "Result", colorOrange)

    local resultRow = dlgFrame:Append("UILayoutGrid")
    resultRow.Anchors = "0,3"; resultRow.Columns = 1; resultRow.Rows = 1
    local pingResult = resultRow:Append("UIObject")
    pingResult.Anchors = "0,0"
    pingResult.Text = "Enter a host and press Ping."
    pingResult.Font = "Medium20"; pingResult.TextalignmentH = "Left"
    pingResult.TextalignmentV = "Top"; pingResult.HasHover = "No"
    pingResult.BackColor = colorTransparent; pingResult.Margin = "6,4,6,4"
    result.pingResult = pingResult

    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- Ping Sweep window
--------------------------------------------------------------------------------
function fct.buildSweepMenu()
    local result = {}
    local display = GetDisplayByIndex(1)
    local overlay = display.ScreenOverlay
    result.display = display
    result.overlay = overlay

    local mainDialog = overlay:Append("BaseInput")
    mainDialog.Name = "Ping Sweep"
    mainDialog.H = 680; mainDialog.W = 700
    mainDialog.Rows = 2; mainDialog.Columns = 1
    mainDialog[1][1].SizePolicy = "Fixed"; mainDialog[1][1].Size = "60"
    mainDialog[1][2].SizePolicy = "Stretch"
    mainDialog.AutoClose = "No"; mainDialog.CloseOnEscape = "Yes"
    result.dialog = mainDialog

    local titleBar = mainDialog:Append("TitleBar")
    titleBar.Columns = 2; titleBar.Rows = 1; titleBar.Anchors = "0,0"
    titleBar[2][2].SizePolicy = "Fixed"; titleBar[2][2].Size = "50"
    titleBar.Texture = "corner2"
    local titleBtn = titleBar:Append("TitleButton")
    titleBtn.Text = "Ping Sweep"; titleBtn.Texture = "corner1"
    titleBtn.Anchors = "0,0"; titleBtn.Icon = "object_appear"
    local closeBtn = titleBar:Append("CloseButton")
    closeBtn.Anchors = "1,0"; closeBtn.Texture = "corner2"

    -- 7 rows: settings header | start ip | end ip | status+btn | results header | results | close
    local dlgFrame = mainDialog:Append("DialogFrame")
    dlgFrame.H = "100%"; dlgFrame.W = "100%"
    dlgFrame.Columns = 1; dlgFrame.Rows = 7
    dlgFrame[1][1].SizePolicy = "Fixed";   dlgFrame[1][1].Size = "42"
    dlgFrame[1][2].SizePolicy = "Fixed";   dlgFrame[1][2].Size = "60"
    dlgFrame[1][3].SizePolicy = "Fixed";   dlgFrame[1][3].Size = "60"
    dlgFrame[1][4].SizePolicy = "Fixed";   dlgFrame[1][4].Size = "60"
    dlgFrame[1][5].SizePolicy = "Fixed";   dlgFrame[1][5].Size = "42"
    dlgFrame[1][6].SizePolicy = "Stretch"
    dlgFrame[1][7].SizePolicy = "Fixed";   dlgFrame[1][7].Size = "55"

    buildSectionHeader(dlgFrame, 0, "Settings", colorBlue)

    -- Shared IP input row builder (no icon boxes, matches Single Ping style)
    local function buildIPRow(anchor, label, placeholder, nameRef)
        local row = dlgFrame:Append("UILayoutGrid")
        row.Anchors = "0," .. anchor; row.Columns = 2; row.Rows = 1
        row[2][1].SizePolicy = "Fixed";   row[2][1].Size = "150"
        row[2][2].SizePolicy = "Stretch"

        local lbl = row:Append("UIObject")
        lbl.Anchors = "0,0"; lbl.Text = label
        lbl.Font = "Medium20"; lbl.TextalignmentH = "Left"
        lbl.HasHover = "No"; lbl.Margin = "0,0,0,0"

        local edit = row:Append("LineEdit")
        edit.Anchors = "1,0"; edit.Message = placeholder
        edit.Texture = "corner0"; edit.TextChanged = "OnChangeAll"
        edit.PluginComponent = my_handle; edit.VKPluginName = "TextInput"
        result[nameRef] = edit
    end

    buildIPRow(1, "Start IP", "192.168.1.1",   "startEdit")
    buildIPRow(2, "End IP",   "192.168.1.254",  "endEdit")

    -- Validation status + Sweep button
    local validRow = dlgFrame:Append("UILayoutGrid")
    validRow.Anchors = "0,3"; validRow.Columns = 2; validRow.Rows = 1
    validRow[2][2].SizePolicy = "Fixed"; validRow[2][2].Size = "110"

    local validStatus = validRow:Append("UIObject")
    validStatus.Anchors = "0,0"; validStatus.Text = ""
    validStatus.Font = "Medium20"; validStatus.TextalignmentH = "Left"
    validStatus.TextalignmentV = "Center"; validStatus.HasHover = "No"
    validStatus.BackColor = colorTransparent; validStatus.Margin = "8,0,0,0"
    result.sweepStatus = validStatus

    local sweepBtn = validRow:Append("Button")
    sweepBtn.Anchors = "1,0"; sweepBtn.Text = "Sweep"; sweepBtn.Font = "Medium20"
    sweepBtn.Textshadow = 1; sweepBtn.HasHover = "Yes"; sweepBtn.TextalignmentH = "Centre"
    sweepBtn.PluginComponent = my_handle; sweepBtn.Clicked = "SweepButtonClicked"
    sweepBtn.BackColor = colorClear; sweepBtn.Enabled = "No"
    result.sweepBtn = sweepBtn

    buildSectionHeader(dlgFrame, 4, "Active Hosts", colorBlue)

    local sweepResultRow = dlgFrame:Append("UILayoutGrid")
    sweepResultRow.Anchors = "0,5"; sweepResultRow.Columns = 1; sweepResultRow.Rows = 1
    local sweepResult = sweepResultRow:Append("UIObject")
    sweepResult.Anchors = "0,0"
    sweepResult.Text = "Enter a range and press Sweep."
    sweepResult.Font = "Medium20"; sweepResult.TextalignmentH = "Left"
    sweepResult.TextalignmentV = "Top"; sweepResult.HasHover = "No"
    sweepResult.BackColor = colorTransparent; sweepResult.Margin = "6,4,6,4"
    result.sweepResult = sweepResult

    local closeRow = dlgFrame:Append("UILayoutGrid")
    closeRow.Anchors = "0,6"; closeRow.Columns = 1; closeRow.Rows = 1
    local cancelBtn = closeRow:Append("Button")
    cancelBtn.Anchors = "0,0"; cancelBtn.Text = "Close"; cancelBtn.Font = "Medium20"
    cancelBtn.Textshadow = 1; cancelBtn.HasHover = "Yes"; cancelBtn.TextalignmentH = "Centre"
    cancelBtn.PluginComponent = my_handle; cancelBtn.Clicked = "CancelButtonClicked"

    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- Signal callbacks
--------------------------------------------------------------------------------
signalTable.CancelButtonClicked = safe(function(caller, ...)
    Obj.Delete(dialog.overlay, Obj.Index(dialog.dialog))
end)

signalTable.LauncherPingClicked = safe(function(caller, ...)
    Obj.Delete(dialog.overlay, Obj.Index(dialog.dialog))
    dialog = fct.buildPingMenu()
end)

signalTable.LauncherSweepClicked = safe(function(caller, ...)
    Obj.Delete(dialog.overlay, Obj.Index(dialog.dialog))
    dialog = fct.buildSweepMenu()
end)

signalTable.OnChangeAll = safe(function(caller, ...)
    -- Single Ping: enable button when field is not empty
    if dialog.pingEdit then
        local host     = dialog.pingEdit.Content or ""
        local ready    = (host ~= "")
        dialog.pingBtn.Enabled   = ready and "Yes" or "No"
        dialog.pingBtn.BackColor = ready and colorPlease or colorClear
    end

    -- Sweep: validate IP range
    if dialog.startEdit then
        local startIP = parseIP(dialog.startEdit.Content or "")
        local endIP   = parseIP(dialog.endEdit.Content   or "")
        local ready   = false
        local msg     = ""

        if startIP and endIP then
            if startIP[1] ~= endIP[1] or startIP[2] ~= endIP[2]
                or startIP[3] ~= endIP[3] then
                msg = "Start and End must be in the same /24 subnet."
            elseif endIP[4] <= startIP[4] then
                msg = "End IP must be greater than Start IP."
            else
                msg   = endIP[4] - startIP[4] + 1 .. " hosts in range"
                ready = true
            end
        elseif (dialog.startEdit.Content or "") ~= ""
            or (dialog.endEdit.Content   or "") ~= "" then
            msg = "Invalid IP address."
        end

        dialog.sweepBtn.Enabled   = ready and "Yes" or "No"
        dialog.sweepBtn.BackColor = ready and colorPlease or colorClear
        dialog.sweepStatus.Text   = msg
    end
end)

signalTable.PingButtonClicked = safe(function(caller, ...)
    local host = dialog.pingEdit.Content or ""
    if host == "" then return end

    dialog.pingBtn.Enabled   = "No"
    dialog.pingBtn.BackColor = colorClear
    dialog.pingResult.Text   = "Pinging " .. host .. " ..."

    local outFile, doneFile, tmpDir = startPing(host)
    local done = false

    local function poll()
        if done then return end
        local f = io.open(doneFile, "r")
        if not f then return end
        f:close(); done = true

        local g = io.open(outFile, "r")
        local result = g and g:read("*a") or ""
        if g then g:close() end

        dialog.pingResult.Text   = (result ~= "") and result
                                   or ("No response from " .. host)
        dialog.pingBtn.Enabled   = "Yes"
        dialog.pingBtn.BackColor = colorPlease
        cleanup(tmpDir)
    end

    Timer(safePoll(poll), 0, 0.5)
end)

signalTable.SweepButtonClicked = safe(function(caller, ...)
    local startIP = parseIP(dialog.startEdit.Content or "")
    local endIP   = parseIP(dialog.endEdit.Content   or "")
    if not (startIP and endIP) then return end

    local base     = string.format("%d.%d.%d", startIP[1], startIP[2], startIP[3])
    local startOct = startIP[4]
    local endOct   = endIP[4]
    local count    = endOct - startOct + 1

    dialog.sweepBtn.Enabled   = "No"
    dialog.sweepBtn.BackColor = colorClear
    dialog.sweepResult.Text   = ""
    dialog.sweepStatus.Text   = string.format(
        "Sweeping %s.%d – %s.%d (%d hosts) ...",
        base, startOct, base, endOct, count)

    -- GMA3 cannot update SetProgressRange while os.execute blocks, so we skip
    -- the range entirely — StartProgress shows a loading animation on its own.
    local progressIdx = StartProgress(
        string.format("Sweeping %s.%d – %s.%d (%d hosts)",
            base, startOct, base, endOct, count))

    -- Run sweep synchronously — blocks for ~3 s while all parallel pings finish
    local resFile, tmpDir = runSweepSync(base, startOct, endOct)

    StopProgress(progressIdx)

    -- Read and sort results
    local g = io.open(resFile, "r")
    local content = g and g:read("*a") or ""
    if g then g:close() end

    local active = {}
    for ip in content:gmatch("(%d+%.%d+%.%d+%.%d+)") do
        table.insert(active, ip)
    end
    table.sort(active, function(a, b)
        return (tonumber(a:match("(%d+)$")) or 0)
             < (tonumber(b:match("(%d+)$")) or 0)
    end)

    dialog.sweepResult.Text = (#active > 0)
        and table.concat(active, "\n")
        or  "No active hosts found."
    dialog.sweepStatus.Text = string.format(
        "Done — %d active host(s) found out of %d.", #active, count)
    dialog.sweepBtn.Enabled   = "Yes"
    dialog.sweepBtn.BackColor = colorPlease
    cleanup(tmpDir)
end)

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

  Full license: https://github.com/tminus60/GrandMA3-Plugins/blob/main/LICENSE
================================================================================
--]]
