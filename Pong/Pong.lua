--
--  ____
-- |  _ \ ___  _ __   __ _
-- | |_) / _ \| '_ \ / _` |
-- |  __/ (_) | | | | (_| |
-- |_|   \___/|_| |_|\__, |
--                   |___/
--
--[[---------------------------------------------------------------------------
  Pong
  A fully-featured Pong game for grandMA3.
  Control your paddle with a playback master fader.

  Rendering technique: layered UILayoutGrids anchored to the same cell.
  Each game element lives in its own 3×3 grid where the surrounding rows/
  columns act as spacers. Updating 4 Size properties per element per frame
  gives pixel-precise, smooth movement without a pixel grid.

  Author:   t-60
  Version:  1.3.0
  GMA3:     tested on 2.3.2.0
  GitHub:   https://github.com/tminus60/GrandMA3-Plugins
  License:  t-60 Plugin License (Non-Commercial) — see bottom of file
---------------------------------------------------------------------------]]

local pluginVersion = "1.3.0"

local pluginName  = select(1, ...)
local signalTable = select(3, ...)
local my_handle   = select(4, ...)

local fct        = {}
local dialog
local currentGen = 0        -- incremented each (re)start to invalidate old timers
local gameTimer  = nil      -- handle returned by Timer(), used to cancel it explicitly

--------------------------------------------------------------------------------
-- Field dimensions — must match the window layout below
--------------------------------------------------------------------------------
local FW = 960   -- game field width  (px)
local FH = 540   -- game field height (px)

local PW  = 14   -- paddle width
local PH  = 90   -- paddle height (updated from cfg on each start/restart)
local PAD = 18   -- distance from field edge to paddle
local BW  = 18   -- ball width
local BH  = 18   -- ball height

--------------------------------------------------------------------------------
-- Settings dialog dimensions
-- Win.H = 540  →  frame = 480
-- Frame rows: tabBar(50) + separator(2) + tab content + btnRow(50)
-- TAB_H = 480 - 50 - 2 - 50 = 378
--------------------------------------------------------------------------------
local SETTINGS_H = 540
local TAB_H      = 378

--------------------------------------------------------------------------------
-- Colours — assigned in main() after Root() is available
--------------------------------------------------------------------------------
local C_BG     -- background (dark)
local C_FG     -- ball / foreground (white)
local C_P1     -- Player 1 paddle (white — game field only, not used as BackColor)
local C_P2     -- Player 2 / CPU paddle (green)
local C_CL     -- centre line + obstacles
local C_HI     -- highlight / active (green)
local C_DIM    -- dimmed / inactive tab button
local C_ORANGE -- active tab + losing score (orange-red)

--------------------------------------------------------------------------------
-- Game state
--------------------------------------------------------------------------------
local state = {}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function resetBall(dir)
    local spd   = state.cfg.ballSpeed
    local angle = math.random(20, 50) * math.pi / 180
    state.ballX  = FW / 2 - BW / 2
    state.ballY  = FH / 2 - BH / 2
    state.ballVX = spd * (dir or 1) * math.cos(angle)
    state.ballVY = spd * (math.random(0,1)==0 and 1 or -1) * math.sin(angle)
end

local function initState()
    state = {
        ballX    = FW/2 - BW/2,
        ballY    = FH/2 - BH/2,
        ballVX   = 0,
        ballVY   = 0,
        cpuY     = FH/2,
        playerY  = FH/2,
        scoreL   = 0,
        scoreR   = 0,
        running  = false,
        paused   = false,
        gameOver = false,
        obstacles = {},
        cfg = {
            gameMode      = "cpu",   -- "cpu" or "2player"
            sequenceNum   = 1,       -- P1 sequence (right paddle)
            seq2Num       = 2,       -- P2 sequence (left paddle, 2P mode)
            datapool      = 1,
            ballSpeed     = 7,
            speedup       = 0.05,  -- velocity multiplier per paddle hit (0 = off)
            paddleHeight  = 90,
            cpuSpeed      = 3,
            cpuAccuracy   = 80,    -- 0 (always centre) … 100 (perfect tracking)
            winScore      = 10,
            player1Name   = "Player",
            player2Name   = "Player 2",
            obstaclesOn   = false,
            obstacleCount = 2,
        },
    }
end

local function initObstacles()
    state.obstacles = {}
    if not state.cfg.obstaclesOn then return end
    for _ = 1, state.cfg.obstacleCount do
        local h = math.random(60, 120)
        table.insert(state.obstacles, {
            x  = FW * 0.25 + math.random() * FW * 0.5,
            y  = math.random(20, FH - h - 20),
            w  = 14, h = h,
            vy = (math.random(0,1)==0 and 1 or -1) * 2,
        })
    end
end

--------------------------------------------------------------------------------
-- Fader reading — seq:GetFader({token='FaderMaster'}) returns 0..100
--------------------------------------------------------------------------------
local function readFader(seqNum)
    local v
    pcall(function()
        local dp  = Root().ShowData.DataPools[state.cfg.datapool]
        local seq = dp and dp.Sequences[seqNum]
        if seq then
            local fv = seq:GetFader({token = 'FaderMaster'})
            if type(fv) == "number" then v = clamp(fv / 100, 0, 1) end
        end
    end)
    return v
end

--------------------------------------------------------------------------------
-- Rendering — layered 3×3 spacer grids
--
-- GMA3 only allows [row][col] indexing DURING construction.
-- All 4 spacer cell refs are stored immediately so moveLayer can update
-- their .Size directly. All spacers are Fixed to prevent window resize.
--------------------------------------------------------------------------------
local function makeSpacerLayer(parent, x, y, w, h, color)
    local g = parent:Append("UILayoutGrid")
    g.Anchors = "0,0"; g.Columns = 3; g.Rows = 3

    local cx = math.max(0, math.min(FW - w, math.floor(x)))
    local cy = math.max(0, math.min(FH - h, math.floor(y)))

    local leftSpc = g[2][1]; leftSpc.SizePolicy = "Fixed"; leftSpc.Size = tostring(cx)
    local midCol  = g[2][2]; midCol.SizePolicy  = "Fixed"; midCol.Size  = tostring(w)
    local rgtSpc  = g[2][3]; rgtSpc.SizePolicy  = "Fixed"; rgtSpc.Size  = tostring(FW - cx - w)
    local topSpc  = g[1][1]; topSpc.SizePolicy  = "Fixed"; topSpc.Size  = tostring(cy)
    local midRow  = g[1][2]; midRow.SizePolicy  = "Fixed"; midRow.Size  = tostring(h)
    local botSpc  = g[1][3]; botSpc.SizePolicy  = "Fixed"; botSpc.Size  = tostring(FH - cy - h)

    local el = g:Append("UIObject")
    el.Anchors = "1,1"; el.BackColor = color; el.HasHover = "No"

    return el, topSpc, botSpc, leftSpc, rgtSpc
end

local function moveLayer(topSpc, botSpc, leftSpc, rgtSpc, x, y, w, h)
    local cx = math.max(0, math.min(FW - w, math.floor(x)))
    local cy = math.max(0, math.min(FH - h, math.floor(y)))
    leftSpc.Size = tostring(cx);      rgtSpc.Size = tostring(FW - cx - w)
    topSpc.Size  = tostring(cy);      botSpc.Size = tostring(FH - cy - h)
end

local layers = {}

local function buildGameLayers(field)
    layers = {}

    local bg = field:Append("UIObject")
    bg.Anchors = "0,0"; bg.BackColor = C_BG; bg.HasHover = "No"

    -- Dashed centre line: multiple short layers stacked at field centre
    do
        local dashH = 20
        local gapH  = 16
        local clX   = math.floor(FW / 2) - 1
        local clY   = math.floor(gapH / 2)
        while clY + dashH <= FH do
            makeSpacerLayer(field, clX, clY, 2, dashH, C_CL)
            clY = clY + dashH + gapH
        end
    end

    local _, ct, cb, cl, cr = makeSpacerLayer(field, PAD, FH/2 - PH/2, PW, PH, C_P2)
    layers.cpu = {t=ct, b=cb, l=cl, r=cr}

    local _, pt, pb, pl, pr = makeSpacerLayer(field, FW - PAD - PW, FH/2 - PH/2, PW, PH, C_P1)
    layers.plr = {t=pt, b=pb, l=pl, r=pr}

    local _, bt, bb, bl, br = makeSpacerLayer(field, FW/2 - BW/2, FH/2 - BH/2, BW, BH, C_FG)
    layers.ball = {t=bt, b=bb, l=bl, r=br}

    layers.obs = {}
end

local function addObstacleLayer(field, obs)
    local _, t, b, l, r = makeSpacerLayer(field, obs.x, obs.y, obs.w, obs.h, C_ORANGE)
    table.insert(layers.obs, {t=t, b=b, l=l, r=r})
end

local function renderFrame()
    if not layers.cpu then return end
    local c = layers.cpu;  moveLayer(c.t, c.b, c.l, c.r, PAD,            state.cpuY    - PH/2, PW, PH)
    local p = layers.plr;  moveLayer(p.t, p.b, p.l, p.r, FW - PAD - PW, state.playerY - PH/2, PW, PH)
    local b = layers.ball; moveLayer(b.t, b.b, b.l, b.r, state.ballX,    state.ballY,           BW, BH)
    for i, obs in ipairs(state.obstacles) do
        local lo = layers.obs[i]
        if lo then moveLayer(lo.t, lo.b, lo.l, lo.r, obs.x, obs.y, obs.w, obs.h) end
    end
    if dialog then
        dialog.scoreL.Text = tostring(state.scoreL)
        dialog.scoreR.Text = tostring(state.scoreR)
        if state.scoreL > state.scoreR then
            dialog.scoreL.BackColor = C_HI;     dialog.scoreR.BackColor = C_ORANGE
        elseif state.scoreR > state.scoreL then
            dialog.scoreL.BackColor = C_ORANGE; dialog.scoreR.BackColor = C_HI
        else
            dialog.scoreL.BackColor = C_P2;     dialog.scoreR.BackColor = C_P2
        end
    end
end

--------------------------------------------------------------------------------
-- Collision
--------------------------------------------------------------------------------
local function rectHit(ax, ay, aw, ah, bx, by, bw, bh)
    return ax < bx+bw and ax+aw > bx and ay < by+bh and ay+ah > by
end

--------------------------------------------------------------------------------
-- Game tick
--------------------------------------------------------------------------------
local function gameTick()
    if not state.running or state.paused or state.gameOver then return end

    local cfg = state.cfg

    -- Player 1 (right paddle)
    local fv1 = readFader(cfg.sequenceNum)
    if fv1 then
        state.playerY = clamp(PH/2 + (1 - fv1) * (FH - PH), PH/2, FH - PH/2)
    end

    -- Left paddle: CPU AI or Player 2
    if cfg.gameMode == "2player" then
        local fv2 = readFader(cfg.seq2Num)
        if fv2 then
            state.cpuY = clamp(PH/2 + (1 - fv2) * (FH - PH), PH/2, FH - PH/2)
        end
    else
        local acc     = clamp(cfg.cpuAccuracy / 100, 0, 1)
        -- Track ball when it moves toward CPU, drift to centre otherwise
        local targetY = state.ballVX < 0
            and (state.ballY + BH / 2)
            or  (FH / 2)
        -- Blend accurate target with field centre by accuracy
        local aimY = targetY * acc + (FH / 2) * (1 - acc)
        local diff = aimY - state.cpuY
        state.cpuY = clamp(state.cpuY + clamp(diff, -cfg.cpuSpeed, cfg.cpuSpeed),
                           PH / 2, FH - PH / 2)
    end

    -- Obstacles
    for _, obs in ipairs(state.obstacles) do
        obs.y = obs.y + obs.vy
        if obs.y < 0 or obs.y + obs.h > FH then obs.vy = -obs.vy end
    end

    -- Ball movement
    state.ballX = state.ballX + state.ballVX
    state.ballY = state.ballY + state.ballVY

    -- Top / bottom walls
    if state.ballY < 0 then
        state.ballY  = 0
        state.ballVY = math.abs(state.ballVY)
    elseif state.ballY + BH > FH then
        state.ballY  = FH - BH
        state.ballVY = -math.abs(state.ballVY)
    end

    -- Helper: apply per-hit speed increase, capped at 3× initial ball speed
    local function applySpeedup()
        if cfg.speedup <= 0 then return end
        local spd = math.sqrt(state.ballVX ^ 2 + state.ballVY ^ 2)
        if spd == 0 then return end
        local newSpd = math.min(spd * (1 + cfg.speedup), cfg.ballSpeed * 3)
        local scale  = newSpd / spd
        state.ballVX = state.ballVX * scale
        state.ballVY = state.ballVY * scale
    end

    -- Left paddle (CPU / P2) hit
    if rectHit(state.ballX, state.ballY, BW, BH,
               PAD, state.cpuY - PH/2, PW, PH) then
        state.ballX  = PAD + PW
        state.ballVX = math.abs(state.ballVX)
        local rel    = (state.ballY + BH/2 - state.cpuY) / (PH/2)
        state.ballVY = rel * cfg.ballSpeed * 0.75
        applySpeedup()
    end

    -- Right paddle (P1) hit
    local plrX = FW - PAD - PW
    if rectHit(state.ballX, state.ballY, BW, BH,
               plrX, state.playerY - PH/2, PW, PH) then
        state.ballX  = plrX - BW
        state.ballVX = -math.abs(state.ballVX)
        local rel    = (state.ballY + BH/2 - state.playerY) / (PH/2)
        state.ballVY = rel * cfg.ballSpeed * 0.75
        applySpeedup()
    end

    -- Obstacle hits — minimum-penetration-axis method to pick correct bounce face
    for _, obs in ipairs(state.obstacles) do
        if rectHit(state.ballX, state.ballY, BW, BH, obs.x, obs.y, obs.w, obs.h) then
            local ballCX  = state.ballX + BW / 2
            local ballCY  = state.ballY + BH / 2
            local obsCX   = obs.x + obs.w / 2
            local obsCY   = obs.y + obs.h / 2
            local overlapX = (BW + obs.w) / 2 - math.abs(ballCX - obsCX)
            local overlapY = (BH + obs.h) / 2 - math.abs(ballCY - obsCY)
            if overlapX < overlapY then
                state.ballVX = -state.ballVX
                state.ballX  = ballCX < obsCX and (obs.x - BW) or (obs.x + obs.w)
            else
                state.ballVY = -state.ballVY
                state.ballY  = ballCY < obsCY and (obs.y - BH) or (obs.y + obs.h)
            end
        end
    end

    -- Scoring — direction after each point is random
    local randDir = math.random(0, 1) == 0 and 1 or -1
    if state.ballX + BW < 0 then
        state.scoreR = state.scoreR + 1
        if state.scoreR >= cfg.winScore then
            state.gameOver = true; fct.onGameOver("player")
        else resetBall(randDir) end
    elseif state.ballX > FW then
        state.scoreL = state.scoreL + 1
        if state.scoreL >= cfg.winScore then
            state.gameOver = true; fct.onGameOver("cpu")
        else resetBall(randDir) end
    end

    renderFrame()
end

-- Forward declarations so fct.onGameOver can reference these before they are defined
local showOverlay, hideOverlay

function fct.onGameOver(winner)
    if not dialog then return end
    local cfg = state.cfg
    local winnerName
    if winner == "player" then
        winnerName = cfg.player1Name
    else
        winnerName = cfg.gameMode == "2player" and cfg.player2Name or "CPU"
    end
    showOverlay("Game Over!")
    dialog.statusLabel.Text = winnerName .. " Wins!"
    dialog.pauseBtn.Text = "Start"
end

--------------------------------------------------------------------------------
-- Crash handler + safe wrappers
--------------------------------------------------------------------------------
local function crashHandler(err)
    local path = GetPath(Enums.PathType.Temp) .. "/" .. pluginName .. "_crash.log"
    local f = io.open(path, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ")
            .. "v" .. pluginVersion .. " | " .. tostring(err) .. "\n")
        f:close()
    end
    Printf("[ERROR] Pong: " .. tostring(err))
    MessageBox({
        title = "Plugin Error — Pong", backColor = "Global.Focus",
        icon = "warning", titleTextColor = "Global.Text",
        message = "Pong v" .. pluginVersion .. " encountered an error.\n\n"
            .. tostring(err) .. "\n\nCrash log: " .. path,
        commands = {{value=0, name="Close"}},
    })
end

local function safe(fn)
    return function(caller, ...)
        local ok, err = pcall(fn, caller, ...)
        if not ok then crashHandler(err) end
    end
end

-- Each (re)start gets a new generation so stale timers self-expire.
-- Also checks each tick whether the game window is still alive — if the user
-- closed it via CloseButton or ESC, the pcall on .Name fails and we stop.
local function cancelTimer()
    if gameTimer then
        pcall(function() gameTimer:Cancel() end)
        gameTimer = nil
    end
end

local function safeTick(gen)
    return function()
        if gen ~= currentGen then return false end   -- stale timer: tell GMA3 to stop it
        local winAlive = false
        pcall(function()
            local _ = dialog.win.Name
            winAlive = true
        end)
        if not winAlive then
            currentGen = currentGen + 1
            state.running = false
            cancelTimer()
            return false                             -- window gone: stop timer
        end
        local ok, err = pcall(gameTick)
        if not ok then Printf("[PONG] tick error: " .. tostring(err)) end
    end
end

--------------------------------------------------------------------------------
-- Main
--------------------------------------------------------------------------------
local function main()
    C_BG  = Root().ColorTheme.ColorGroups.Global.Default
    C_FG  = Root().ColorTheme.ColorGroups.Global.Text
    C_P1  = Root().ColorTheme.ColorGroups.Global.Text              -- paddle: white
    C_P2  = Root().ColorTheme.ColorGroups.Button.BackgroundPlease  -- paddle: green
    C_CL  = Root().ColorTheme.ColorGroups.Global.Text              -- centre line: white
    C_HI  = Root().ColorTheme.ColorGroups.Button.BackgroundPlease  -- active / highlight
    C_DIM    = Root().ColorTheme.ColorGroups.Global.Focus             -- inactive tab
    C_ORANGE = Root().ColorTheme.ColorGroups.Button.BackgroundClear  -- active tab + losing score

    math.randomseed(os.time())
    initState()
    dialog = fct.buildGameWindow()
    currentGen = currentGen + 1
    gameTimer  = Timer(safeTick(currentGen), 0, 0.033)
end

--------------------------------------------------------------------------------
-- Field text overlay — centred message box (PRESS START / GAME OVER / PAUSED)
-- Hidden by setting the mid-row size to "0"; shown by restoring it.
--------------------------------------------------------------------------------
local OVERLAY_H = 90
local OVERLAY_W = 380

local function buildFieldOverlay(field)
    local topH = math.floor((FH - OVERLAY_H) / 2)
    local lefW = math.floor((FW - OVERLAY_W) / 2)
    local og = field:Append("UILayoutGrid")
    og.Anchors = "0,0"; og.Columns = 3; og.Rows = 3
    og[2][1].SizePolicy = "Fixed"; og[2][1].Size = tostring(lefW)
    og[2][2].SizePolicy = "Fixed"; og[2][2].Size = tostring(OVERLAY_W)
    og[2][3].SizePolicy = "Fixed"; og[2][3].Size = tostring(FW - lefW - OVERLAY_W)
    local oTop = og[1][1]; oTop.SizePolicy = "Fixed"; oTop.Size = tostring(topH)
    local oMid = og[1][2]; oMid.SizePolicy = "Fixed"; oMid.Size = tostring(OVERLAY_H)
    local oBod = og[1][3]; oBod.SizePolicy = "Fixed"; oBod.Size = tostring(FH - topH - OVERLAY_H)
    local el = og:Append("UIObject")
    el.Anchors = "1,1"; el.BackColor = C_HI; el.HasHover = "No"
    el.Font = "Medium20"; el.TextalignmentH = "Center"; el.Text = "Press Start"
    return {el=el, top=oTop, mid=oMid, bot=oBod}
end

showOverlay = function(msg)
    local ov = dialog and dialog.fieldText; if not ov then return end
    local topH = math.floor((FH - OVERLAY_H) / 2)
    ov.el.Text  = msg
    ov.top.Size = tostring(topH)
    ov.mid.Size = tostring(OVERLAY_H)
    ov.bot.Size = tostring(FH - topH - OVERLAY_H)
end

hideOverlay = function()
    local ov = dialog and dialog.fieldText; if not ov then return end
    ov.top.Size = tostring(FH)
    ov.mid.Size = "0"
    ov.bot.Size = "0"
end

--------------------------------------------------------------------------------
-- Build main game window
--
-- Win.H = TitleBar(60) + ScoreBar(50) + Field(FH=540) + Controls(50) = 700
--------------------------------------------------------------------------------
function fct.buildGameWindow()
    local result = {}
    local display = GetDisplayByIndex(1)
    local overlay = display.ScreenOverlay
    result.display = display; result.overlay = overlay

    local win = overlay:Append("BaseInput")
    win.Name    = "Pong"
    win.W       = FW
    win.H       = 60 + 50 + FH + 50
    win.Rows    = 2; win.Columns = 1
    win[1][1].SizePolicy = "Fixed"; win[1][1].Size = "60"
    win[1][2].SizePolicy = "Stretch"
    win.AutoClose = "No"; win.CloseOnEscape = "Yes"
    result.win = win

    -- TitleBar: [title stretch | settings 50 | close 50]
    local tb = win:Append("TitleBar")
    tb.Columns = 3; tb.Rows = 1; tb.Anchors = "0,0"
    tb[2][3].SizePolicy = "Fixed"; tb[2][3].Size = "50"
    tb[2][2].SizePolicy = "Fixed"; tb[2][2].Size = "50"
    tb.Texture = "corner2"

    local titleBtn = tb:Append("TitleButton")
    titleBtn.Text = "Pong"; titleBtn.Texture = "corner1"
    titleBtn.Anchors = "0,0"

    local settingsBtn = tb:Append("Button")
    settingsBtn.Anchors = "1,0"; settingsBtn.Icon = "settings"
    settingsBtn.HasHover = "Yes"; settingsBtn.Texture = "corner0"
    settingsBtn.PluginComponent = my_handle
    settingsBtn.Clicked = "OpenSettingsClicked"

    local closeBtn = tb:Append("CloseButton")
    closeBtn.Anchors = "2,0"; closeBtn.Texture = "corner2"

    -- Content rows: score bar(50) | field(FH) | controls(50)
    local content = win:Append("DialogFrame")
    content.Rows = 3; content.Columns = 1
    content[1][1].SizePolicy = "Fixed"; content[1][1].Size = "50"
    content[1][2].SizePolicy = "Fixed"; content[1][2].Size = tostring(FH)
    content[1][3].SizePolicy = "Fixed"; content[1][3].Size = "50"

    -- Score bar layout:
    --   col 0 (Fixed 160): left player name
    --   col 1 (Fixed  80): left score — green accent
    --   col 2 (Stretch)  : status / game message
    --   col 3 (Fixed  80): right score
    --   col 4 (Fixed 160): right player name
    local scoreBar = content:Append("UILayoutGrid")
    scoreBar.Anchors = "0,0"; scoreBar.Columns = 5; scoreBar.Rows = 1
    scoreBar[2][1].SizePolicy = "Fixed"; scoreBar[2][1].Size = "160"
    scoreBar[2][2].SizePolicy = "Fixed"; scoreBar[2][2].Size = "80"
    scoreBar[2][3].SizePolicy = "Stretch"
    scoreBar[2][4].SizePolicy = "Fixed"; scoreBar[2][4].Size = "80"
    scoreBar[2][5].SizePolicy = "Fixed"; scoreBar[2][5].Size = "160"

    local cfg0     = state.cfg
    local leftName = cfg0.gameMode == "2player" and cfg0.player2Name or "CPU"

    -- Left side: green accent (matches left paddle colour)
    local nameL = scoreBar:Append("UIObject")
    nameL.Anchors = "0,0"; nameL.Text = leftName
    nameL.Font = "Medium20"; nameL.TextalignmentH = "Center"
    nameL.HasHover = "No"
    result.nameL = nameL

    local scoreL = scoreBar:Append("UIObject")
    scoreL.Anchors = "1,0"; scoreL.Text = "0"
    scoreL.Font = "Medium20"; scoreL.TextalignmentH = "Center"
    scoreL.HasHover = "No"; scoreL.BackColor = C_P2
    result.scoreL = scoreL

    -- Centre status: no background, subtle text
    local statusLabel = scoreBar:Append("UIObject")
    statusLabel.Anchors = "2,0"
    statusLabel.Text = cfg0.gameMode == "2player" and "2 Player" or "vs CPU"
    statusLabel.Font = "Medium20"; statusLabel.TextalignmentH = "Center"
    statusLabel.HasHover = "No"
    result.statusLabel = statusLabel

    -- Right side: no special BackColor — default dark bg, white text is readable
    local scoreR = scoreBar:Append("UIObject")
    scoreR.Anchors = "3,0"; scoreR.Text = "0"
    scoreR.Font = "Medium20"; scoreR.TextalignmentH = "Center"
    scoreR.HasHover = "No"; scoreR.BackColor = C_P2
    result.scoreR = scoreR

    local nameR = scoreBar:Append("UIObject")
    nameR.Anchors = "4,0"; nameR.Text = cfg0.player1Name
    nameR.Font = "Medium20"; nameR.TextalignmentH = "Center"
    nameR.HasHover = "No"
    result.nameR = nameR

    -- Game field container
    local fieldContainer = content:Append("UILayoutGrid")
    fieldContainer.Anchors = "0,1"
    fieldContainer.Columns = 1
    fieldContainer.Rows    = 1
    buildGameLayers(fieldContainer)
    result.fieldText = buildFieldOverlay(fieldContainer)   -- must be last: renders on top
    result.fieldContainer = fieldContainer

    -- Controls: [Start/Pause | Restart | Close]
    local ctrl = content:Append("UILayoutGrid")
    ctrl.Anchors = "0,2"; ctrl.Columns = 3; ctrl.Rows = 1

    local pauseBtn = ctrl:Append("Button")
    pauseBtn.Anchors = "0,0"; pauseBtn.Text = "Start"
    pauseBtn.Font = "Medium20"; pauseBtn.HasHover = "Yes"; pauseBtn.Textshadow = 1
    pauseBtn.TextalignmentH = "Centre"; pauseBtn.BackColor = C_HI
    pauseBtn.PluginComponent = my_handle; pauseBtn.Clicked = "PauseClicked"
    result.pauseBtn = pauseBtn

    local restartBtn = ctrl:Append("Button")
    restartBtn.Anchors = "1,0"; restartBtn.Text = "Restart"
    restartBtn.Font = "Medium20"; restartBtn.HasHover = "Yes"; restartBtn.Textshadow = 1
    restartBtn.TextalignmentH = "Centre"
    restartBtn.PluginComponent = my_handle; restartBtn.Clicked = "RestartClicked"

    local closeBtn2 = ctrl:Append("Button")
    closeBtn2.Anchors = "2,0"; closeBtn2.Text = "Close"
    closeBtn2.Font = "Medium20"; closeBtn2.HasHover = "Yes"; closeBtn2.Textshadow = 1
    closeBtn2.TextalignmentH = "Centre"
    closeBtn2.PluginComponent = my_handle; closeBtn2.Clicked = "CloseGameClicked"

    dialog = result
    return result
end

--------------------------------------------------------------------------------
-- Settings dialog — tabbed layout
--
-- Tabs are simulated by toggling the Fixed Size of each tab's content row:
--   active   → Size = TAB_H
--   inactive → Size = "0"  (collapsed / invisible)
--
-- Tab 1: Control / Match  (12 rows × ~32px ≈ 390px)
-- Tab 2: CPU              (3 rows: header 40 + field 40 + spacer Stretch)
--------------------------------------------------------------------------------
function fct.buildSettingsDialog()
    if dialog.settingsWin then return end
    local display = GetDisplayByIndex(1)
    local overlay = display.ScreenOverlay
    local s = {}; s.display = display; s.overlay = overlay

    local win = overlay:Append("BaseInput")
    win.Name = "Pong — Settings"; win.W = 520; win.H = SETTINGS_H
    win.X = 180; win.Y = 60
    win.Rows = 2; win.Columns = 1
    win[1][1].SizePolicy = "Fixed"; win[1][1].Size = "60"
    win[1][2].SizePolicy = "Stretch"
    win.AutoClose = "No"; win.CloseOnEscape = "No"
    s.win = win

    local tb = win:Append("TitleBar")
    tb.Columns = 1; tb.Rows = 1; tb.Anchors = "0,0"
    tb.Texture = "corner2"
    local titleBtn = tb:Append("TitleButton")
    titleBtn.Text = "Settings"; titleBtn.Texture = "corner2"
    titleBtn.Anchors = "0,0"; titleBtn.Icon = "settings"

    -- Outer frame: tabBar(50) | separator(2) | tab1(TAB_H or 0) | tab2(0 or TAB_H) | btnRow(50)
    local frame = win:Append("DialogFrame")
    frame.Rows = 5; frame.Columns = 1
    frame[1][1].SizePolicy = "Fixed"; frame[1][1].Size = "50"
    frame[1][2].SizePolicy = "Fixed"; frame[1][2].Size = "2"
    local tab1Cell = frame[1][3]; tab1Cell.SizePolicy = "Fixed"; tab1Cell.Size = tostring(TAB_H)
    local tab2Cell = frame[1][4]; tab2Cell.SizePolicy = "Fixed"; tab2Cell.Size = "0"
    frame[1][5].SizePolicy = "Fixed"; frame[1][5].Size = "50"
    s.tab1Cell = tab1Cell; s.tab2Cell = tab2Cell

    -- Tab buttons row
    local tabBar = frame:Append("UILayoutGrid")
    tabBar.Anchors = "0,0"; tabBar.Columns = 2; tabBar.Rows = 1

    local tab1Btn = tabBar:Append("Button")
    tab1Btn.Anchors = "0,0"; tab1Btn.Text = "Control / Match"
    tab1Btn.Font = "Medium20"; tab1Btn.HasHover = "Yes"; tab1Btn.Textshadow = 1
    tab1Btn.TextalignmentH = "Centre"; tab1Btn.BackColor = C_ORANGE
    tab1Btn.PluginComponent = my_handle; tab1Btn.Clicked = "SettingsTab1Clicked"
    s.tab1Btn = tab1Btn

    local tab2Btn = tabBar:Append("Button")
    tab2Btn.Anchors = "1,0"; tab2Btn.Text = "CPU"
    tab2Btn.Font = "Medium20"; tab2Btn.HasHover = "Yes"; tab2Btn.Textshadow = 1
    tab2Btn.TextalignmentH = "Centre"; tab2Btn.BackColor = C_DIM
    tab2Btn.PluginComponent = my_handle; tab2Btn.Clicked = "SettingsTab2Clicked"
    s.tab2Btn = tab2Btn

    -- Separator line between tab buttons and content
    local sepLine = frame:Append("UIObject")
    sepLine.Anchors = "0,1"; sepLine.BackColor = C_HI; sepLine.HasHover = "No"

    -- Shared helper: label (col 0) + LineEdit (col 1) in a given grid at row r
    local function addRow(grid, r, label, key, vk, filter)
        local lbl = grid:Append("UIObject")
        lbl.Anchors = string.format("0,%d", r); lbl.Text = label
        lbl.Font = "Medium20"; lbl.TextalignmentH = "Left"
        lbl.HasHover = "No"
        local edit = grid:Append("LineEdit")
        edit.Anchors = string.format("1,%d", r); edit.Texture = "corner0"
        edit.Font = "Medium20"; edit.VKPluginName = vk or "TextInput"
        if filter then edit.Filter = filter end
        edit.Content = tostring(state.cfg[key])
        s[key] = edit
    end

    local function addToggle(grid, r, label, key, cb)
        local lbl = grid:Append("UIObject")
        lbl.Anchors = string.format("0,%d", r); lbl.Text = label
        lbl.Font = "Medium20"; lbl.TextalignmentH = "Left"
        lbl.HasHover = "No"
        local btn = grid:Append("IndicatorButton")
        btn.Anchors = string.format("1,%d", r)
        btn.PluginComponent = my_handle; btn.Clicked = cb
        local on = state.cfg[key]
        btn.State = on and 1 or 0
        btn.indicatoricon = on and "ButtonOffIcon" or "ButtonONIcon"
        btn.Text = on and "On" or "Off"
        s[key .. "Btn"] = btn
    end

    -- Section header spanning both columns
    local function sectionHeader(grid, r, label)
        local lbl = grid:Append("UIObject")
        lbl.Anchors = string.format("0,%d", r); lbl.Text = label
        lbl.Font = "Medium20"; lbl.TextalignmentH = "Center"
        lbl.HasHover = "No"; lbl.BackColor = C_HI
        local rgt = grid:Append("UIObject")
        rgt.Anchors = string.format("1,%d", r)
        rgt.HasHover = "No"; rgt.BackColor = C_HI
    end

    -- ── Tab 1: Control / Match  (12 rows) ───────────────────────────────────
    local t1 = frame:Append("UILayoutGrid")
    t1.Anchors = "0,2"; t1.Columns = 2; t1.Rows = 14
    t1[2][1].SizePolicy = "Fixed"; t1[2][1].Size = "180"
    t1[2][2].SizePolicy = "Stretch"

    sectionHeader(t1, 0, "Controls")

    -- Game Mode toggle
    local modeLbl = t1:Append("UIObject")
    modeLbl.Anchors = "0,1"; modeLbl.Text = "Game Mode"
    modeLbl.Font = "Medium20"; modeLbl.TextalignmentH = "Left"
    modeLbl.HasHover = "No"
    local modeBtn = t1:Append("IndicatorButton")
    modeBtn.Anchors = "1,1"
    modeBtn.PluginComponent = my_handle; modeBtn.Clicked = "SettingsModeClicked"
    local is2P = state.cfg.gameMode == "2player"
    modeBtn.State = is2P and 1 or 0
    modeBtn.indicatoricon = is2P and "ButtonOffIcon" or "ButtonONIcon"
    modeBtn.Text = is2P and "2 Player" or "vs CPU"
    s.modeBtn = modeBtn

    addRow(t1, 2,  "Datapool",     "datapool",    "TextInputNumOnly", "1234567890")
    addRow(t1, 3,  "P1 Name",      "player1Name", "TextInput")
    addRow(t1, 4,  "P1 Sequence",  "sequenceNum", "TextInputNumOnly", "1234567890")
    addRow(t1, 5,  "P2 Name",      "player2Name", "TextInput")
    addRow(t1, 6,  "P2 Sequence",  "seq2Num",     "TextInputNumOnly", "1234567890")

    sectionHeader(t1, 7, "Match")

    addRow(t1,    8,  "Winning Score",  "winScore",      "TextInputNumOnly", "1234567890")
    addRow(t1,    9,  "Ball Speed",     "ballSpeed",     "TextInputNumOnly", "1234567890")
    addRow(t1,    10, "Speed Increase", "speedup",       "TextInputNumOnly", "1234567890.")
    addRow(t1,    11, "Paddle Height",  "paddleHeight",  "TextInputNumOnly", "1234567890")
    addToggle(t1, 12, "Obstacles",      "obstaclesOn",   "SettingsObstacleClicked")
    addRow(t1,    13, "Obstacle Count", "obstacleCount", "TextInputNumOnly", "1234567890")

    -- ── Tab 2: CPU  (explicit row heights: header 40 | field 40 | spacer) ──
    local t2 = frame:Append("UILayoutGrid")
    t2.Anchors = "0,3"; t2.Columns = 2; t2.Rows = 4
    t2[2][1].SizePolicy = "Fixed"; t2[2][1].Size = "180"
    t2[2][2].SizePolicy = "Stretch"
    t2[1][1].SizePolicy = "Fixed"; t2[1][1].Size = "40"
    t2[1][2].SizePolicy = "Fixed"; t2[1][2].Size = "40"
    t2[1][3].SizePolicy = "Fixed"; t2[1][3].Size = "40"
    t2[1][4].SizePolicy = "Stretch"

    sectionHeader(t2, 0, "CPU")
    addRow(t2, 1, "CPU Speed",    "cpuSpeed",    "TextInputNumOnly", "1234567890")
    addRow(t2, 2, "CPU Accuracy", "cpuAccuracy", "TextInputNumOnly", "1234567890")

    -- ── Apply / Cancel ──────────────────────────────────────────────────────
    local btnRow = frame:Append("UILayoutGrid")
    btnRow.Anchors = "0,4"; btnRow.Columns = 2; btnRow.Rows = 1

    local applyBtn = btnRow:Append("Button")
    applyBtn.Anchors = "0,0"; applyBtn.Text = "Apply"
    applyBtn.Font = "Medium20"; applyBtn.HasHover = "Yes"; applyBtn.Textshadow = 1
    applyBtn.TextalignmentH = "Centre"; applyBtn.BackColor = C_HI
    applyBtn.PluginComponent = my_handle; applyBtn.Clicked = "SettingsApplyClicked"

    local cancelBtn = btnRow:Append("Button")
    cancelBtn.Anchors = "1,0"; cancelBtn.Text = "Cancel"
    cancelBtn.Font = "Medium20"; cancelBtn.HasHover = "Yes"; cancelBtn.Textshadow = 1
    cancelBtn.TextalignmentH = "Centre"
    cancelBtn.PluginComponent = my_handle; cancelBtn.Clicked = "SettingsCancelClicked"

    dialog.settingsWin = s
end

--------------------------------------------------------------------------------
-- Signal callbacks
--------------------------------------------------------------------------------
signalTable.PauseClicked = safe(function(caller, ...)
    if state.gameOver then
        signalTable.RestartClicked(caller)
        return
    end
    if not state.running then
        PH = state.cfg.paddleHeight   -- apply paddle size from settings
        state.running = true; state.paused = false
        initObstacles()
        if dialog and dialog.fieldContainer then
            for _, obs in ipairs(state.obstacles) do
                addObstacleLayer(dialog.fieldContainer, obs)
            end
        end
        resetBall(1)
        hideOverlay()
        dialog.pauseBtn.Text    = "Pause"
        dialog.statusLabel.Text = ""
    elseif state.paused then
        state.paused = false
        hideOverlay()
        dialog.pauseBtn.Text    = "Pause"
        dialog.statusLabel.Text = ""
    else
        state.paused = true
        showOverlay("Paused")
        dialog.pauseBtn.Text    = "Resume"
        dialog.statusLabel.Text = ""
    end
end)

signalTable.RestartClicked = safe(function(caller, ...)
    cancelTimer()
    currentGen = currentGen + 1
    state.running = false
    local savedCfg = state.cfg

    if dialog.settingsWin then
        Obj.Delete(dialog.settingsWin.overlay, Obj.Index(dialog.settingsWin.win))
    end
    Obj.Delete(dialog.overlay, Obj.Index(dialog.win))

    initState()
    state.cfg = savedCfg
    layers    = {}
    dialog    = fct.buildGameWindow()
    gameTimer  = Timer(safeTick(currentGen), 0, 0.033)
end)

signalTable.CloseGameClicked = safe(function(caller, ...)
    cancelTimer()
    currentGen = currentGen + 1
    state.running = false
    if dialog.settingsWin then
        Obj.Delete(dialog.settingsWin.overlay, Obj.Index(dialog.settingsWin.win))
    end
    Obj.Delete(dialog.overlay, Obj.Index(dialog.win))
end)

signalTable.OpenSettingsClicked = safe(function() fct.buildSettingsDialog() end)

local function toggleIndicator(caller)
    if caller.State == 1 then
        caller.State = 0; caller.indicatoricon = "ButtonONIcon"
    else
        caller.State = 1; caller.indicatoricon = "ButtonOffIcon"
    end
end

signalTable.SettingsObstacleClicked = safe(function(caller, ...)
    toggleIndicator(caller)
    caller.Text = (caller.State == 1) and "On" or "Off"
end)

signalTable.SettingsModeClicked = safe(function(caller, ...)
    toggleIndicator(caller)
    caller.Text = (caller.State == 1) and "2 Player" or "vs CPU"
end)

-- Tab switching: swap which content row is visible
local function switchTab(tabNum)
    local s = dialog.settingsWin; if not s then return end
    if tabNum == 1 then
        s.tab1Cell.Size = tostring(TAB_H); s.tab2Cell.Size = "0"
        s.tab1Btn.BackColor = C_ORANGE;    s.tab2Btn.BackColor = C_DIM
    else
        s.tab1Cell.Size = "0";             s.tab2Cell.Size = tostring(TAB_H)
        s.tab1Btn.BackColor = C_DIM;       s.tab2Btn.BackColor = C_ORANGE
    end
end

signalTable.SettingsTab1Clicked = safe(function() switchTab(1) end)
signalTable.SettingsTab2Clicked = safe(function() switchTab(2) end)

signalTable.SettingsApplyClicked = safe(function(caller, ...)
    local s = dialog.settingsWin; if not s then return end
    local cfg = state.cfg
    cfg.player1Name   = (s.player1Name and s.player1Name.Content ~= "") and s.player1Name.Content or cfg.player1Name
    cfg.player2Name   = (s.player2Name and s.player2Name.Content ~= "") and s.player2Name.Content or cfg.player2Name
    cfg.datapool      = tonumber(s.datapool.Content)      or cfg.datapool
    cfg.sequenceNum   = tonumber(s.sequenceNum.Content)   or cfg.sequenceNum
    cfg.seq2Num       = tonumber(s.seq2Num.Content)       or cfg.seq2Num
    cfg.winScore      = math.max(1,   tonumber(s.winScore.Content)      or cfg.winScore)
    cfg.ballSpeed     = math.max(1,   tonumber(s.ballSpeed.Content)     or cfg.ballSpeed)
    cfg.speedup       = math.max(0,   math.min(0.5, tonumber(s.speedup.Content)   or cfg.speedup))
    cfg.paddleHeight  = math.max(20,  math.min(FH - 20, tonumber(s.paddleHeight.Content) or cfg.paddleHeight))
    cfg.cpuSpeed      = math.max(1,   tonumber(s.cpuSpeed.Content)      or cfg.cpuSpeed)
    cfg.cpuAccuracy   = math.max(0,   math.min(100, tonumber(s.cpuAccuracy.Content) or cfg.cpuAccuracy))
    cfg.obstacleCount = math.max(1,   math.min(10, tonumber(s.obstacleCount.Content) or cfg.obstacleCount))
    PH = cfg.paddleHeight   -- apply paddle height immediately without restart
    cfg.obstaclesOn   = (s.obstaclesOnBtn and s.obstaclesOnBtn.State == 1)
    cfg.gameMode      = (s.modeBtn.State == 1) and "2player" or "cpu"

    -- Refresh score bar immediately
    if dialog then
        dialog.nameR.Text = cfg.player1Name
        dialog.nameL.Text = cfg.gameMode == "2player" and cfg.player2Name or "CPU"
        if not state.running then
            dialog.statusLabel.Text = cfg.gameMode == "2player" and "2 Player" or "vs CPU"
            showOverlay("Press Start")
        end
    end
    Obj.Delete(s.overlay, Obj.Index(s.win)); dialog.settingsWin = nil
end)

signalTable.SettingsCancelClicked = safe(function(caller, ...)
    local s = dialog.settingsWin
    if s then Obj.Delete(s.overlay, Obj.Index(s.win)) end
    dialog.settingsWin = nil
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

  Full license: https://github.com/tminus60/GrandMA3-Plugins/blob/master/LICENSE
================================================================================
--]]
