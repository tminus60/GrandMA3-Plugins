--
--  ____  _                    _            _
-- / ___|| |__   _____      __| |    ___   ___| | _____ _ __
-- \___ \| '_ \ / _ \ \ /\ / /| |   / _ \ / __| |/ / _ \ '__|
--  ___) | | | | (_) \ V  V / | |__| (_) | (__|   <  __/ |
-- |____/|_| |_|\___/ \_/\_/  |_____\___/ \___|_|\_\___|_|
--
--[[---------------------------------------------------------------------------
  Show Locker
  Locks the grandMA3 show with a PIN code.
  
  Author:   t-60
  Version:  1.0.0
  GMA3:     tested on 2.3.2.0
  GitHub:   https://github.com/tminus60/GrandMA3-Plugins
  License:  t-60 Plugin License (Non-Commercial) — see bottom of file
---------------------------------------------------------------------------]]

local pluginVersion = "1.0.0"

-- ── t-60 Crash Reporter  ──
local _T60_WEBHOOK   = "https://discord.com/api/webhooks/1507368948876837085/FqeuJCUYmpebjQlDC9GlrjD3d5JjB3V_z98WUNHHUeyrP3e6bIDdAOi46Nu5-qWCNJSj"
local _T60_PLUGIN_ID = "showlocker"
-- ─────────────────────────────────────────────────────────────

-- ── t-60 Update Checker ── 
local _T60_UPDATE_URL = "https://raw.githubusercontent.com/tminus60/GrandMA3-Plugins/master/Showlocker/version.txt"
-- ─────────────────────────────────────────────────────────────

local pluginName = select(1, ...)

--------------------------------------------------------------------------------
-- Config — stored in GlobalVars, survives show reloads
--------------------------------------------------------------------------------
local VAR_PIN  = "t60_lock_pin"
local VAR_MSG  = "t60_lock_msg"
local SAVE_NAME = "Showlock"  -- show wird unter diesem Namen gespeichert bei falschem PIN

local function getCfg(key, default)
    local v = ""; pcall(function() v = GetVar(GlobalVars(), key) or "" end)
    return v ~= "" and v or default
end
local function setCfg(key, val)
    pcall(function() SetVar(GlobalVars(), key, tostring(val)) end)
end
local function getPin()     return getCfg(VAR_PIN, "1234")        end
local function getLockMsg() return getCfg(VAR_MSG, "Show Locked") end

--------------------------------------------------------------------------------
-- t-60 Crash Reporter  ·  copy-paste block (nicht ändern)
--------------------------------------------------------------------------------
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

local function sendCrashLog(err)
    local path = GetPath(Enums.PathType.Temp) .. "/" .. pluginName .. "_crash.log"
    local f = io.open(path, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. "v" .. pluginVersion .. " | " .. tostring(err) .. "\n")
        f:close()
    end
    Printf("[ERROR] " .. pluginName .. ": " .. tostring(err))
    _t60SendCrash(pluginVersion, err, path)
end

--------------------------------------------------------------------------------
-- Plugin — pure coroutine approach (same as original ShowLock)
--------------------------------------------------------------------------------
return function()
    local ok, err = pcall(function()

        -- ── Launcher: MessageBox until user locks or exits ──────────────────
        while true do
            coroutine.yield(0.1)

            local choice = MessageBox({
                title          = "Show Locker  v" .. pluginVersion,
                backColor      = "Global.Focus",
                titleTextColor = "Global.Text",
                message        = "Lock message:  \"" .. getLockMsg() .. "\"\n"
                              .. "PIN length:    " .. #getPin() .. " digits",
                commands = {
                    {value = 1, name = "Lock Show"},
                    {value = 2, name = "Change PIN"},
                    {value = 3, name = "Change Message"},
                    {value = 4, name = "Close"},
                }
            })

            if not choice or choice.result == 4 then
                return   -- user closed, plugin exits normally

            elseif choice.result == 2 then
                local newPin = TextInput("New PIN  (leave empty to keep current)", "")
                if newPin and newPin ~= "" then
                    setCfg(VAR_PIN, newPin)
                    Printf("[ShowLocker] PIN updated.")
                end

            elseif choice.result == 3 then
                local newMsg = TextInput("New lock message", getLockMsg())
                if newMsg and newMsg ~= "" then
                    setCfg(VAR_MSG, newMsg)
                    Printf("[ShowLocker] Message updated.")
                end

            elseif choice.result == 1 then
                break   -- proceed to lock
            end
        end

        -- ── Lock: blocking TextInput loop, nothing else possible ─────────────
        Printf("[ShowLocker] Show locked.")
        local attempts     = 0
        local MAX_ATTEMPTS = 3

        while true do
            coroutine.yield(0.1)

            local remaining = MAX_ATTEMPTS - attempts
            local prompt    = getLockMsg() .. "  —  Enter PIN"
            if attempts > 0 then
                prompt = prompt .. "  (" .. remaining .. " attempt" .. (remaining == 1 and "" or "s") .. " remaining)"
            end

            local input = TextInput(prompt, "")

            if input == nil then
                -- Cancel / ESC pressed → keep looping, cannot escape

            elseif tostring(input) == getPin() then
                Printf("[ShowLocker] Unlocked.")
                return   -- correct PIN: plugin exits, show stays

            else
                attempts = attempts + 1
                Printf("[ShowLocker] Wrong PIN (" .. attempts .. "/" .. MAX_ATTEMPTS .. ")")

                if attempts >= MAX_ATTEMPTS then
                    Printf("[ShowLocker] Max attempts reached — loading locked show.")
                    local result = CmdIndirectWait('LoadShow "' .. SAVE_NAME .. '" /nc')
                    if result ~= "OK" then
                        Cmd('NewShow /nc')
                        coroutine.yield(0.5)
                        CmdIndirectWait('SaveShow "' .. SAVE_NAME .. '" /nc')
                        coroutine.yield(0.5)
                        Cmd('LoadShow "' .. SAVE_NAME .. '" /nc')
                    end
                    return
                end
            end
        end

    end)

    if not ok then sendCrashLog(err) end
end
