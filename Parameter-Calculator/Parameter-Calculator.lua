--
--  ____
-- |  _ \ __ _ _ __ __ _ _ __ ___
-- | |_) / _` | '__/ _` | '_ ` _ \
-- |  __/ (_| | | | (_| | | | | | |
-- |_|   \__,_|_|  \__,_|_| |_| |_|
--
--   ____      _            _       _
--  / ___|__ _| | ___ _   _| | __ _| |_ ___  _ __
-- | |   / _` | |/ __| | | | |/ _` | __/ _ \| '__|
-- | |__| (_| | | (__| |_| | | (_| | || (_) | |
--  \____\__,_|_|\___|\__,_|_|\__,_|\__\___/|_|
--
--[[---------------------------------------------------------------------------
  Parameter Calculator
  Counts real and virtual DMX parameters of all fixtures in the show,
  including multi-instance geometry handling. Also calculates how many
  grandMA3 Parameter Units (PU M/L/XL) are needed to cover the show.

  Author:   t-60
  Version:  3.0.0
  GMA3:     tested on 2.3.2.0
  GitHub:   https://github.com/tminus60/GrandMA3-Plugins
  License:  t-60 Plugin License (Non-Commercial) — see bottom of file
---------------------------------------------------------------------------]]

local pluginVersion = "3.0.0"

-- GMA3 passes these four values to every plugin on load.
-- pluginName:    the name as stored in the showfile
-- componentName: the component inside the plugin (usually the same)
-- signalTable:   table where UI callbacks are registered
-- my_handle:     reference to this plugin instance, needed for PluginComponent links
local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local my_handle     = select(4, ...)

local fct          = {}
local dialog
local _recalcTotal -- forward declaration, defined below fct.buildMenu

-- Colour handles — declared nil here so all functions below can close over them.
-- Assigned inside main() because Root() is only valid at plugin runtime,
-- not at module load time.
local colorred, colororange, colorblue, colorpurple

-- grandMA3 Parameter Unit sizes (number of parameters each unit provides).
-- Source: MA Lighting official parameter unit documentation.
local UNIT_M  = 4096
local UNIT_L  = 8192
local UNIT_XL = 16384

--------------------------------------------------------------------------------
-- Parameter counting
--------------------------------------------------------------------------------
local function CheckInstanceCount(modeGeometries, channelGeometry)
    local instances = 0
    for _, geometry in ipairs(modeGeometries) do
        if geometry:GetClass() == "GeometryReference" and geometry.geometrydirect == channelGeometry then
            instances = instances + 1
        end
        if #geometry:Children() > 0 then
            instances = instances + CheckInstanceCount(geometry:Children(), channelGeometry)
        end
    end
    return instances
end

local function countFixtureChannels(fix)
    local real, virtual = 0, 0
    local dmxChannels   = fix["modedirect"]["dmxchannels"]:Children()
    local modeGeoms     = fix["modedirect"]["geometrydirect"]:Children()
    for _, ch in ipairs(dmxChannels) do
        local instances = 0
        if fix.count ~= 0 then
            instances = CheckInstanceCount(modeGeoms, ch.geometry)
        end
        if instances == 0 then instances = 1 end
        if ch.coarse == "None" then
            virtual = virtual + instances
        else
            real = real + instances
        end
    end
    return real, virtual
end

local function CheckActualParameterCount()
    local realParameters             = 0
    -- GMA3 reserves 8 virtual parameters per stage for internal use.
    local virtualParameters          = Patch()["stages"].count * 8
    local unpatchedFixtures          = 0
    local unpatchedrealParameters    = 0
    local unpatchedvirtualParameters = 0

    local fixtures = ObjectList("Fixture 1 thru")
    for i = 1, #fixtures do
        local fix = fixtures[i]
        local r, v = countFixtureChannels(fix)
        if fix.patch == "" then
            unpatchedFixtures          = unpatchedFixtures + 1
            unpatchedrealParameters    = unpatchedrealParameters    + r
            unpatchedvirtualParameters = unpatchedvirtualParameters + v
        else
            realParameters    = realParameters    + r
            virtualParameters = virtualParameters + v
        end
    end
    return {
        realParameters             = realParameters,
        virtualParameters          = virtualParameters,
        unpatchedFixtures          = unpatchedFixtures,
        unpatchedrealParameters    = unpatchedrealParameters,
        unpatchedvirtualParameters = unpatchedvirtualParameters,
    }
end

local function updateUIFromStats(stats)
    if not dialog then return end
    dialog.realparamnotpatched:Set("Text",    tostring(stats.unpatchedrealParameters))
    dialog.realparampatched:Set("Text",       tostring(stats.realParameters))
    dialog.virtualparamnotpatched:Set("Text", tostring(stats.unpatchedvirtualParameters))
    dialog.virtualparampatched:Set("Text",    tostring(stats.virtualParameters))
    -- compute totals directly from stats — no UI round-trip needed
    dialog.totalparampatched:Set("Text",
        tostring(stats.realParameters + stats.virtualParameters))
    dialog.totalparamnotpatched:Set("Text",
        tostring(stats.unpatchedrealParameters + stats.unpatchedvirtualParameters))
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------
local function main()
    -- Root() colour references must be resolved here, not at module level
    colorred    = Root().ColorTheme.ColorGroups.Assignment.Macro
    colororange = Root().ColorTheme.ColorGroups.Global.PartlySelected
    colorblue   = Root().ColorTheme.ColorGroups.Assignment.Group
    colorpurple = Root().ColorTheme.ColorGroups.NumericInput.SoundValueBackground

    local shortcuts = CurrentProfile().KeyboardShortCuts
    shortcuts.KeyboardShortcutsActive = false
    dialog = fct.buildMenu(1100, 1100)
    local stats = CheckActualParameterCount()
    updateUIFromStats(stats)
    _recalcTotal()
end

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------
function fct.buildMenu(width, height)
    local result = {}
    local display = GetDisplayByIndex(1)
    local overlay = display.ScreenOverlay
    result.display = display
    result.overlay = overlay

    local mainDialog = overlay:Append("BaseInput")
    mainDialog.Name          = "Parameter Calculator"
    mainDialog.H             = height
    mainDialog.W             = width
    mainDialog.Rows          = 2
    mainDialog.Columns       = 1
    mainDialog[1][1].SizePolicy = "Fixed"
    mainDialog[1][1].Size       = "60"
    mainDialog[1][2].SizePolicy = "Stretch"
    mainDialog.AutoClose     = "No"
    mainDialog.CloseOnEscape = "Yes"
    result.dialog = mainDialog

    -- TitleBar: title | close
    local titleBar = mainDialog:Append("TitleBar")
    titleBar.Columns = 2
    titleBar.Rows    = 1
    titleBar.Anchors = "0,0"
    titleBar[2][2].SizePolicy = "Fixed"; titleBar[2][2].Size = "50"
    titleBar.Texture = "corner2"

    local titleBtn = titleBar:Append("TitleButton")
    titleBtn.Text    = "Parameter Calculator"
    titleBtn.Texture = "corner1"
    titleBtn.Anchors = "0,0"
    titleBtn.Icon    = "object_appear"

    local closeBtn = titleBar:Append("CloseButton")
    closeBtn.Anchors = "1,0"
    closeBtn.Texture = "corner2"

    local dlgFrame = mainDialog:Append("DialogFrame")
    dlgFrame.H       = "100%"
    dlgFrame.W       = "100%"
    dlgFrame.Columns = 1
    dlgFrame.Rows    = 12
    result.dlgFrame  = dlgFrame

    -----------------------------
    -- System Configuration
    -----------------------------
    local sysRow = dlgFrame:Append("UILayoutGrid")
    sysRow.Anchors = "0,0"; sysRow.Columns = 2; sysRow.Rows = 1
    sysRow[2][2].SizePolicy = "Stretch"; sysRow[2][2].Size = "100"
    sysRow[2][1].SizePolicy = "Stretch"; sysRow[2][1].Size = "1000"

    local sysLabel = sysRow:Append("UIObject")
    sysLabel.Anchors = "0,0"; sysLabel.Text = "System Configuration"
    sysLabel.Font = "Medium20"; sysLabel.TextalignmentH = "Center"
    sysLabel.Texture = "corner1"; sysLabel.HasHover = "No"
    sysLabel.Margin = "8,8,2,2"; sysLabel.BackColor = colororange

    local sysIcon = sysRow:Append("Button")
    sysIcon.Anchors = "1,0"; sysIcon.HasHover = "No"
    sysIcon.Texture = "corner2"; sysIcon.Icon = "settings"
    sysIcon.Margin = "2,8,8,2"; sysIcon.BackColor = colororange

    -----------------------------
    -- Biggest Station selector
    -----------------------------
    local stationRow = dlgFrame:Append("UILayoutGrid")
    stationRow.Anchors = "0,1"; stationRow.Columns = 3; stationRow.Rows = 1
    stationRow[2][3].SizePolicy = "Stretch"; stationRow[2][3].Size = "370"
    stationRow[2][2].SizePolicy = "Stretch"; stationRow[2][2].Size = "370"
    stationRow[2][1].SizePolicy = "Stretch"; stationRow[2][1].Size = "370"

    local stationLabel = stationRow:Append("UIObject")
    stationLabel.Anchors = "0,0"; stationLabel.Text = "Biggest Station"
    stationLabel.Font = "Medium20"; stationLabel.TextalignmentH = "Left"
    stationLabel.HasHover = "No"; stationLabel.Margin = "8,2,2,2"
    stationLabel.BackColor = colororange

    local sysItems = {"FullSize", "Light", "OnPc with Hardware"}
    local sysMap   = {["FullSize"] = "20480", ["Light"] = "16384", ["OnPc with Hardware"] = "4096"}

    local stationBtn = stationRow:Append("ToggleButton")
    stationBtn.Anchors = "1,0"; stationBtn.Name = "SystemConfigButton"
    stationBtn.Font = "Medium20"; stationBtn.TextalignmentH = "Center"
    stationBtn.Margin = "2,2,2,2"; stationBtn.HasHover = "Yes"
    stationBtn.PluginComponent = my_handle; stationBtn.Clicked = "SystemConfigButtonClicked"
    stationBtn.IndicatorIcon = "SwipeButtonIcon"
    stationBtn.BackColor = colororange; stationBtn.ColorIndicator = colororange
    if stationBtn.ClearList then stationBtn:ClearList() end
    for i, txt in ipairs(sysItems) do stationBtn:AddListNumericItem(txt, i) end
    stationBtn:SelectListItemByIndex(1)

    local stationOutput = stationRow:Append("UIObject")
    stationOutput.Anchors = "2,0"; stationOutput.Font = "Medium20"
    stationOutput.TextalignmentH = "Right"; stationOutput.HasHover = "No"
    stationOutput.Margin = "2,2,8,2"; stationOutput.BackColor = colororange
    stationOutput:Set("Text", sysMap[sysItems[1]] or "—")
    result.systemconfigoutput = stationOutput

    -----------------------------
    -- PU rows (M / L / XL) — built with a shared helper
    -----------------------------
    local function buildPuRow(anchor, label, minusEvent, plusEvent)
        local row = dlgFrame:Append("UILayoutGrid")
        row.Anchors = "0," .. anchor; row.Columns = 5; row.Rows = 1
        row[2][5].SizePolicy = "Stretch"; row[2][5].Size = "370"
        row[2][4].SizePolicy = "Stretch"; row[2][4].Size = "123"
        row[2][3].SizePolicy = "Stretch"; row[2][3].Size = "123"
        row[2][2].SizePolicy = "Stretch"; row[2][2].Size = "123"
        row[2][1].SizePolicy = "Stretch"; row[2][1].Size = "370"

        local lbl = row:Append("UIObject")
        lbl.Anchors = "0,0"; lbl.Text = label; lbl.Font = "Medium20"
        lbl.TextalignmentH = "Left"; lbl.HasHover = "No"
        lbl.Margin = "8,2,2,2"; lbl.BackColor = colororange

        local minus = row:Append("Button")
        minus.Anchors = "1,0"; minus.Text = "-"; minus.Font = "Medium20"
        minus.Textshadow = 1; minus.HasHover = "Yes"; minus.TextalignmentH = "Centre"
        minus.PluginComponent = my_handle; minus.Clicked = minusEvent
        minus.Margin = "2,2,2,2"; minus.BackColor = colororange

        local edit = row:Append("LineEdit")
        edit.Anchors = "2,0"; edit.Message = "0"; edit.Content = "0"
        edit.TextChanged = "OnChangeAll"; edit.PluginComponent = my_handle
        edit.VKPluginName = "TextInputNumOnly"; edit.Filter = "1234567890"
        edit.Margin = "2,2,2,2"; edit.BackColor = colororange

        local plus = row:Append("Button")
        plus.Anchors = "3,0"; plus.Text = "+"; plus.Font = "Medium20"
        plus.Textshadow = 1; plus.HasHover = "Yes"; plus.TextalignmentH = "Centre"
        plus.PluginComponent = my_handle; plus.Clicked = plusEvent
        plus.Margin = "2,2,2,2"; plus.BackColor = colororange

        local output = row:Append("UIObject")
        output.Anchors = "4,0"; output.Text = "0"; output.Font = "Medium20"
        output.TextalignmentH = "Right"; output.HasHover = "No"
        output.Margin = "2,2,8,2"; output.BackColor = colororange

        return edit, output
    end

    local puMedit,  puMoutput  = buildPuRow(2, "PU M",  "puMminusClicked",  "puMplusClicked")
    local puLedit,  puLoutput  = buildPuRow(3, "PU L",  "puLminusClicked",  "puLplusClicked")
    local puXLedit, puXLoutput = buildPuRow(4, "PU XL", "puXLminusClicked", "puXLplusClicked")
    result.puMedit  = puMedit;  result.puMoutput  = puMoutput
    result.puLedit  = puLedit;  result.puLoutput  = puLoutput
    result.puXLedit = puXLedit; result.puXLoutput = puXLoutput

    -----------------------------
    -- Total Available
    -----------------------------
    local totalAvailRow = dlgFrame:Append("UILayoutGrid")
    totalAvailRow.Anchors = "0,5"; totalAvailRow.Columns = 2; totalAvailRow.Rows = 1
    totalAvailRow[2][2].SizePolicy = "Stretch"; totalAvailRow[2][2].Size = "370"
    totalAvailRow[2][1].SizePolicy = "Stretch"; totalAvailRow[2][1].Size = "740"

    local totalAvailLabel = totalAvailRow:Append("UIObject")
    totalAvailLabel.Anchors = "0,0"; totalAvailLabel.Text = "Total Parameters Available"
    totalAvailLabel.Font = "Medium20"; totalAvailLabel.TextalignmentH = "Left"
    totalAvailLabel.HasHover = "No"; totalAvailLabel.Margin = "8,2,2,2"
    totalAvailLabel.Texture = "corner4"; totalAvailLabel.BackColor = colororange
    result.totalcountLabel = totalAvailLabel

    local totalAvailOutput = totalAvailRow:Append("UIObject")
    totalAvailOutput.Anchors = "1,0"; totalAvailOutput.Text = ""
    totalAvailOutput.Font = "Medium20"; totalAvailOutput.TextalignmentH = "Right"
    totalAvailOutput.HasHover = "No"; totalAvailOutput.Margin = "2,2,8,2"
    totalAvailOutput.Texture = "corner8"; totalAvailOutput.BackColor = colororange
    result.totalcountOutput = totalAvailOutput

    -----------------------------
    -- Column header (Not Patched / Patched)
    -----------------------------
    local colHeader = dlgFrame:Append("UILayoutGrid")
    colHeader.Anchors = "0,6"; colHeader.Columns = 3; colHeader.Rows = 1
    colHeader[2][3].SizePolicy = "Stretch"; colHeader[2][3].Size = "370"
    colHeader[2][2].SizePolicy = "Stretch"; colHeader[2][2].Size = "370"
    colHeader[2][1].SizePolicy = "Stretch"; colHeader[2][1].Size = "370"

    local colIcon = colHeader:Append("Button")
    colIcon.Anchors = "0,0"; colIcon.Icon = "calculator"
    colIcon.HasHover = "No"; colIcon.Texture = "corner1"
    colIcon.Margin = "8,8,2,2"; colIcon.BackColor = colorblue

    local colNotPatched = colHeader:Append("UIObject")
    colNotPatched.Anchors = "1,0"; colNotPatched.Text = "Not Patched"
    colNotPatched.Font = "Medium20"; colNotPatched.TextalignmentH = "Center"
    colNotPatched.HasHover = "No"; colNotPatched.Margin = "2,8,2,2"
    colNotPatched.BackColor = colorblue

    local colPatched = colHeader:Append("UIObject")
    colPatched.Anchors = "2,0"; colPatched.Text = "Patched"
    colPatched.Font = "Medium20"; colPatched.TextalignmentH = "Center"
    colPatched.HasHover = "No"; colPatched.Margin = "2,8,8,2"
    colPatched.Texture = "corner2"; colPatched.BackColor = colorblue

    -----------------------------
    -- Data rows — built with a shared helper
    -----------------------------
    local function buildDataRow(anchor, label)
        local row = dlgFrame:Append("UILayoutGrid")
        row.Anchors = "0," .. anchor; row.Columns = 3; row.Rows = 1
        row[2][3].SizePolicy = "Stretch"; row[2][3].Size = "370"
        row[2][2].SizePolicy = "Stretch"; row[2][2].Size = "370"
        row[2][1].SizePolicy = "Stretch"; row[2][1].Size = "370"

        local lbl = row:Append("UIObject")
        lbl.Anchors = "0,0"; lbl.Text = label; lbl.Font = "Medium20"
        lbl.TextalignmentH = "Left"; lbl.HasHover = "No"
        lbl.Margin = "8,2,2,2"; lbl.BackColor = colorblue

        local notPatchedVal = row:Append("UIObject")
        notPatchedVal.Anchors = "1,0"; notPatchedVal.Text = "0"; notPatchedVal.Font = "Medium20"
        notPatchedVal.TextalignmentH = "Right"; notPatchedVal.HasHover = "No"
        notPatchedVal.Margin = "2,2,2,2"; notPatchedVal.BackColor = colorblue

        local patchedVal = row:Append("UIObject")
        patchedVal.Anchors = "2,0"; patchedVal.Text = "0"; patchedVal.Font = "Medium20"
        patchedVal.TextalignmentH = "Right"; patchedVal.HasHover = "No"
        patchedVal.Margin = "2,2,8,2"; patchedVal.BackColor = colorblue

        return notPatchedVal, patchedVal
    end

    local realNP,  realP  = buildDataRow(7, "Real Parameters used")
    local virtNP,  virtP  = buildDataRow(8, "Virtual Parameters used")
    local totalNP, totalP = buildDataRow(9, "Total Parameters")
    result.realparamnotpatched    = realNP;  result.realparampatched    = realP
    result.virtualparamnotpatched = virtNP;  result.virtualparampatched = virtP
    result.totalparamnotpatched   = totalNP; result.totalparampatched   = totalP

    -----------------------------
    -- Missing Parameters
    -----------------------------
    local missingRow = dlgFrame:Append("UILayoutGrid")
    missingRow.Anchors = "0,10"; missingRow.Columns = 2; missingRow.Rows = 1
    missingRow[2][2].SizePolicy = "Stretch"; missingRow[2][2].Size = "370"
    missingRow[2][1].SizePolicy = "Stretch"; missingRow[2][1].Size = "740"

    local missingLabel = missingRow:Append("UIObject")
    missingLabel.Anchors = "0,0"; missingLabel.Text = "Missing Parameters"
    missingLabel.Font = "Medium20"; missingLabel.TextalignmentH = "Left"
    missingLabel.HasHover = "No"; missingLabel.Texture = "corner1"
    missingLabel.Margin = "8,8,2,2"; missingLabel.BackColor = colorpurple
    result.missingLabel = missingLabel

    local missingOutput = missingRow:Append("UIObject")
    missingOutput.Anchors = "1,0"; missingOutput.Text = ""
    missingOutput.Font = "Medium20"; missingOutput.TextalignmentH = "Right"
    missingOutput.HasHover = "No"; missingOutput.Texture = "corner2"
    missingOutput.Margin = "2,8,8,2"; missingOutput.BackColor = colorpurple
    result.missingoutput = missingOutput

    -----------------------------
    -- Recommendation output
    -----------------------------
    local infoRow = dlgFrame:Append("UILayoutGrid")
    infoRow.Anchors = "0,11"; infoRow.Columns = 1; infoRow.Rows = 1
    infoRow[2][1].SizePolicy = "Stretch"; infoRow[2][1].Size = "1100"

    local outputLabel = infoRow:Append("UIObject")
    outputLabel.Anchors = "0,0"; outputLabel.Text = ""
    outputLabel.Font = "Medium20"; outputLabel.TextalignmentH = "Center"
    outputLabel.HasHover = "No"; outputLabel.Texture = "corner12"
    outputLabel.Margin = "8,2,8,8"; outputLabel.BackColor = colorpurple
    result.outputLabel = outputLabel

    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- Recalculate totals and PU recommendation
--------------------------------------------------------------------------------
_recalcTotal = function()
    if not dialog or not dialog.totalcountOutput then return end

    local puM  = tonumber(dialog.puMoutput.Text)  or 0
    local puL  = tonumber(dialog.puLoutput.Text)  or 0
    local puXL = tonumber(dialog.puXLoutput.Text) or 0
    local sys  = tonumber(dialog.systemconfigoutput.Text) or 0
    local isOnPc    = (sys == 4096)
    local available = math.min(puM + puL + puXL + sys, 262144)

    if isOnPc then
        dialog.totalcountOutput:Set("Text", "4096 — Maximum reached")
        dialog.totalcountOutput.TextalignmentH = "Center"
        dialog.totalcountOutput.BackColor      = colorred
        dialog.totalcountLabel.BackColor       = colorred
    else
        dialog.totalcountOutput:Set("Text", tostring(available))
        dialog.totalcountOutput.TextalignmentH = "Right"
        dialog.totalcountOutput.BackColor      = colororange
        dialog.totalcountLabel.BackColor       = colororange
    end
    if available == 262144 then
        dialog.totalcountOutput.BackColor = colorred
        dialog.totalcountLabel.BackColor  = colorred
        dialog.totalcountOutput:Set("Text", "262144")
    end

    local used     = tonumber(dialog.totalparampatched.Text) or 0
    local baseline = (available > 0) and available or 4096
    local missing  = math.max(0, used - baseline)
    dialog.missingoutput:Set("Text", tostring(missing))

    if missing > 0 then
        dialog.missingoutput.BackColor = colorred
        dialog.missingLabel.BackColor  = colorred

        if missing > 262144 then
            dialog.outputLabel:Set("Text", "Too many missing parameters for one session!")
            dialog.outputLabel.BackColor = colorred
            return
        end

        if isOnPc then
            dialog.outputLabel:Set("Text", "Maximum reached with OnPc config")
        else
            -- Greedy bin-packing: convert missing params into PU M units first,
            -- then exchange groups of 4× M → 1× XL and 2× M → 1× L to minimise
            -- the total number of units while always covering the missing count.
            local units = math.ceil(missing / UNIT_M)
            local nXL   = math.floor(units / 4); units = units - 4 * nXL
            local nL    = math.floor(units / 2); units = units - 2 * nL
            local nM    = units
            local over  = (nXL * UNIT_XL + nL * UNIT_L + nM * UNIT_M) - missing

            local parts = {}
            if nXL > 0 then table.insert(parts, string.format("%d×PU XL", nXL)) end
            if nL  > 0 then table.insert(parts, string.format("%d×PU L",  nL))  end
            if nM  > 0 then table.insert(parts, string.format("%d×PU M",  nM))  end
            local packsStr = (#parts > 0) and table.concat(parts, " + ") or "0"
            local tail     = (over > 0) and string.format(" (+%d headroom)", over) or " (exact fit)"
            dialog.outputLabel:Set("Text", "Needed: " .. packsStr .. tail)
        end
        dialog.outputLabel.BackColor = colorred
    else
        dialog.missingoutput.BackColor = colorpurple
        dialog.missingLabel.BackColor  = colorpurple
        local extra = math.abs(baseline - used)
        dialog.outputLabel:Set("Text", "Extra parameters available: " .. tostring(extra))
        dialog.outputLabel.BackColor = colorpurple
    end
end

--------------------------------------------------------------------------------
-- PU setter — updates the count field, the computed total output, and recalcs
--------------------------------------------------------------------------------
local function _setPuCount(n, edit, output, unit)
    if not dialog then return end
    n = math.max(0, n)
    dialog._updating = true
    local ok, err = pcall(function()
        edit:Set("Content", tostring(n))
        output:Set("Text",  tostring(n * unit))
        _recalcTotal()
    end)
    dialog._updating = false
    if not ok then error(err, 2) end
end

--------------------------------------------------------------------------------
-- Crash Handler + safe() wrapper
--
-- crashHandler: writes a timestamped error to a log file in GMA3's temp
--   directory and shows a MessageBox — the user always sees what went wrong.
--
-- safe(fn): wraps any signal callback in pcall so errors triggered by button
--   clicks, text changes etc. are also caught, not just errors during startup.
--------------------------------------------------------------------------------
local function crashHandler(err)
    local crashLogPath = GetPath(Enums.PathType.Temp) .. "/" .. pluginName .. "_crash.log"
    local f = io.open(crashLogPath, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. "v" .. pluginVersion .. " | " .. tostring(err) .. "\n")
        f:close()
    end
    Printf("[ERROR] " .. pluginName .. " v" .. pluginVersion .. ": " .. tostring(err))
    MessageBox({
        title          = "Plugin Error — " .. pluginName,
        backColor      = "Global.Focus",
        icon           = "warning",
        titleTextColor = "Global.Text",
        message        = pluginName .. " v" .. pluginVersion .. " encountered an error.\n\n"
                         .. tostring(err) .. "\n\nCrash log saved to:\n"
                         .. GetPath(Enums.PathType.Temp) .. "/" .. pluginName .. "_crash.log",
        commands       = {{value = 0, name = "Close"}}
    })
end

local function safe(fn)
    return function(caller, ...)
        local ok, err = pcall(fn, caller, ...)
        if not ok then crashHandler(err) end
    end
end

--------------------------------------------------------------------------------
-- Signal callbacks
--------------------------------------------------------------------------------
signalTable.SystemConfigButtonClicked = safe(function(caller, ...)
    local idx = caller.GetListSelectedItemIndex and caller:GetListSelectedItemIndex() or 1
    local map = {"20480", "16384", "4096"}
    dialog.systemconfigoutput:Set("Text", map[idx] or "—")
    _recalcTotal()
end)

signalTable.puMplusClicked   = safe(function() _setPuCount((tonumber(dialog.puMedit.Content)  or 0) + 1, dialog.puMedit,  dialog.puMoutput,  UNIT_M)  end)
signalTable.puMminusClicked  = safe(function() _setPuCount((tonumber(dialog.puMedit.Content)  or 0) - 1, dialog.puMedit,  dialog.puMoutput,  UNIT_M)  end)
signalTable.puLplusClicked   = safe(function() _setPuCount((tonumber(dialog.puLedit.Content)  or 0) + 1, dialog.puLedit,  dialog.puLoutput,  UNIT_L)  end)
signalTable.puLminusClicked  = safe(function() _setPuCount((tonumber(dialog.puLedit.Content)  or 0) - 1, dialog.puLedit,  dialog.puLoutput,  UNIT_L)  end)
signalTable.puXLplusClicked  = safe(function() _setPuCount((tonumber(dialog.puXLedit.Content) or 0) + 1, dialog.puXLedit, dialog.puXLoutput, UNIT_XL) end)
signalTable.puXLminusClicked = safe(function() _setPuCount((tonumber(dialog.puXLedit.Content) or 0) - 1, dialog.puXLedit, dialog.puXLoutput, UNIT_XL) end)

signalTable.OnChangeAll = safe(function(caller, ...)
    if not dialog or dialog._updating then return end
    local puMap = {
        [dialog.puMedit]  = {output = dialog.puMoutput,  unit = UNIT_M},
        [dialog.puLedit]  = {output = dialog.puLoutput,  unit = UNIT_L},
        [dialog.puXLedit] = {output = dialog.puXLoutput, unit = UNIT_XL},
    }
    local entry = puMap[caller]
    if not entry then return end
    local n = math.max(0, tonumber(caller.Content) or 0)
    entry.output:Set("Text", tostring(n * entry.unit))
    _recalcTotal()
end)

--------------------------------------------------------------------------------
-- Plugin entry point
--
-- GMA3 calls the function returned here to start the plugin.
-- Wrapping main() in pcall ensures startup errors are caught by crashHandler
-- rather than crashing silently or showing GMA3's raw error output.
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
