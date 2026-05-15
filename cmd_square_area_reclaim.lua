function widget:GetInfo()
    return {
        name    = "Square Area Reclaim",
        desc    = "Right-click-drag (with Reclaim cursor active) to reclaim an area shaped as a square or a freely-drawn rectangle. Pick the gesture in the in-game settings panel or via /squarereclaim_mode <square|draw|both>. SHIFT queues, ALT restricts by hovered unit-type, CTRL includes non-autoreclaimable.",
        author  = "Zack Cheang",
        date    = "2026-05-15",
        license = "GNU GPL v2 or later",
        layer   = 0,
        enabled = true,
    }
end

local CMD_RECLAIM    = CMD.RECLAIM
local GRID           = 16
local mapSizeX       = Game.mapSizeX
local mapSizeZ       = Game.mapSizeZ
local maxUnits       = Game.maxUnits
local KEY_R          = (KEYSYMS and KEYSYMS.r) or 114
local R_HOLD_SECONDS = 0.2  -- press shorter than this is a "tap" and ignored

-- Widget modes:
--   "square" -- right-click-drag = centered square (no R needed)
--   "draw"   -- right-click-drag = corner-anchored rectangle (no R needed)
--   "both"   -- right-click-drag = square; hold R then right-click-drag = rectangle
-- (To turn the gesture off entirely, disable the widget in the F11 panel.)
local CONFIG_KEY    = "squarereclaim_mode"
local DEFAULT_MODE  = "both"
local MODE_LIST     = { "square", "draw", "both" }
local MODE_INDEX    = {}
for i, m in ipairs(MODE_LIST) do MODE_INDEX[m] = i end
local VALID_MODES   = {}
for _, m in ipairs(MODE_LIST) do VALID_MODES[m] = true end
local widgetMode    = DEFAULT_MODE  -- loaded from config in Initialize

local DEBUG = true   -- Spring.Echo trace; set to false once verified working

local spGetActiveCommand       = Spring.GetActiveCommand
local spSetActiveCommand       = Spring.SetActiveCommand
local spTraceScreenRay         = Spring.TraceScreenRay
local spGetSelectedUnits       = Spring.GetSelectedUnits
local spGetFeaturesInRectangle = Spring.GetFeaturesInRectangle
local spGetUnitsInRectangle    = Spring.GetUnitsInRectangle
local spGetGroundHeight        = Spring.GetGroundHeight
local spGetModKeyState         = Spring.GetModKeyState
local spGiveOrderToUnit        = Spring.GiveOrderToUnit
local spGetUnitDefID           = Spring.GetUnitDefID
local spGetUnitPosition        = Spring.GetUnitPosition
local spGetFeatureDefID        = Spring.GetFeatureDefID
local spGetFeaturePosition     = Spring.GetFeaturePosition
local spEcho                   = Spring.Echo

local function dbg(...)
    if DEBUG then spEcho("[SquareReclaim]", ...) end
end

-- Drag state. mode is one of: nil, "square", "rect".
local mode             = nil
local anchorX, anchorZ = 0, 0   -- click point: square center, or rect first corner
local farX, farZ       = 0, 0   -- rect mode: opposite corner (current cursor)
local halfWidth        = 0      -- square mode: half side length, snapped to grid
local hoveredUnitDefID = nil    -- captured at MousePress for ALT filter

-- Cached because the engine may clear the active command on right-mouse-down
-- before widget:MousePress runs.
local reclaimCursorActive = false
-- R-key hold detection. A press shorter than R_HOLD_SECONDS is treated as a
-- tap and discarded; only a sustained hold flips rKeyDown to arm rect mode.
local rPressTime          = nil
local rKeyDown            = false

local function snap(v)
    return math.floor(v / GRID + 0.5) * GRID
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function groundFromMouse(mx, my)
    local _, pos = spTraceScreenRay(mx, my, true)
    if not pos then return nil end
    return pos[1], pos[3]
end

local function unitDefUnderCursor(mx, my)
    local desc, value = spTraceScreenRay(mx, my, false)
    if desc == "unit" and value then
        return spGetUnitDefID(value)
    end
    return nil
end

-- Returns x1, z1, x2, z2 of the current drag area, clamped to map.
local function bounds()
    if mode == "square" then
        local x1 = clamp(anchorX - halfWidth, 0, mapSizeX)
        local z1 = clamp(anchorZ - halfWidth, 0, mapSizeZ)
        local x2 = clamp(anchorX + halfWidth, 0, mapSizeX)
        local z2 = clamp(anchorZ + halfWidth, 0, mapSizeZ)
        return x1, z1, x2, z2
    else
        -- Rect: anchor stays at exact click; farX/farZ are already grid-snapped
        -- relative to anchor by MouseMove, so just normalize and clamp.
        local x1 = clamp(math.min(anchorX, farX), 0, mapSizeX)
        local x2 = clamp(math.max(anchorX, farX), 0, mapSizeX)
        local z1 = clamp(math.min(anchorZ, farZ), 0, mapSizeZ)
        local z2 = clamp(math.max(anchorZ, farZ), 0, mapSizeZ)
        return x1, z1, x2, z2
    end
end

local function tooSmall(x1, z1, x2, z2)
    return (x2 - x1) < GRID or (z2 - z1) < GRID
end

local function collectFeatures(rawFeatures, ctrlHeld)
    local out = {}
    for _, fID in ipairs(rawFeatures) do
        local fdefID = spGetFeatureDefID(fID)
        local fdef   = fdefID and FeatureDefs[fdefID]
        if fdef and fdef.reclaimable ~= false then
            local autoOK = fdef.autoreclaimable ~= false
            if ctrlHeld or autoOK then
                out[#out + 1] = fID
            end
        end
    end
    return out
end

local function isImmobileBuilder(defID)
    local def = defID and UnitDefs[defID]
    if not def then return false end
    if (def.buildSpeed or 0) <= 0 then return false end
    if def.canMove == false then return true end
    if (def.speed or 0) == 0 then return true end
    return false
end

-- Collect units in the rect; optional defFilter restricts to one unitDefID.
-- Selected units are NOT excluded here -- the per-builder order loop is
-- responsible for skipping self (so a group of builders can eat each other).
local function collectUnits(rawUnits, defFilter)
    local out = {}
    if defFilter then
        for _, uID in ipairs(rawUnits) do
            if spGetUnitDefID(uID) == defFilter then
                out[#out + 1] = uID
            end
        end
    else
        for _, uID in ipairs(rawUnits) do
            out[#out + 1] = uID
        end
    end
    return out
end

local function setMode(newMode, silent)
    if not VALID_MODES[newMode] then
        spEcho("[SquareReclaim] usage: /" .. CONFIG_KEY ..
               " <square|draw|both>  (current: " .. widgetMode .. ")")
        return
    end
    widgetMode = newMode
    Spring.SetConfigString(CONFIG_KEY, newMode)
    if not silent then
        spEcho("[SquareReclaim] mode = " .. newMode)
    end
end

local function modeAction(_, _, params)
    setMode(params and params[1])
end

-- BAR settings-panel integration. The gui_options widget exposes a global
-- registry at WG['options']; we hand it our OPTION_SPECS so the mode appears
-- as a dropdown in the in-game settings menu alongside other widgets' options.
-- Per gui_options.lua: select-type values are NUMERIC INDICES into `options`,
-- and `category` + `group` are required for the option to render.
local OPTION_SPECS = {
    {
        configVariable = "widgetMode",
        name           = "Square Area Reclaim: gesture",
        description    = "Square = centered square on right-drag. Draw = corner-anchored rectangle. Both = square; hold R first for rectangle.",
        type           = "select",
        options        = MODE_LIST,
        category       = 1,        -- 1 = basic tier (always visible)
        group          = "control",
    },
}

local function getOptionId(spec)
    return "SquareReclaim__" .. (spec.configVariable or spec.name)
end

local function getOptionValue(spec)
    if spec.configVariable == "widgetMode" then
        return MODE_INDEX[widgetMode] or MODE_INDEX[DEFAULT_MODE]
    end
end

local function setOptionValue(spec, value)
    if spec.configVariable == "widgetMode" then
        local newMode = MODE_LIST[tonumber(value)]
        if newMode then setMode(newMode, true) end
    end
end

local function createOptionFromSpec(spec)
    local option = table.copy(spec)
    option.id         = getOptionId(spec)
    option.widgetname = widget:GetInfo().name
    option.value      = getOptionValue(spec)
    option.onchange   = function(_, value) setOptionValue(spec, value) end
    return option
end

function widget:Initialize()
    local saved = Spring.GetConfigString(CONFIG_KEY, DEFAULT_MODE)
    if VALID_MODES[saved] then widgetMode = saved end
    widgetHandler:AddAction(CONFIG_KEY, modeAction, nil, "p")
    if WG['options'] and WG['options'].addOptions then
        WG['options'].addOptions(table.map(OPTION_SPECS, createOptionFromSpec))
    end
    dbg("loaded, mode=" .. widgetMode)
end

function widget:Shutdown()
    widgetHandler:RemoveAction(CONFIG_KEY)
    if WG['options'] and WG['options'].removeOptions then
        WG['options'].removeOptions(table.map(OPTION_SPECS, getOptionId))
    end
end

function widget:Update()
    local _, cmdID = spGetActiveCommand()
    reclaimCursorActive = (cmdID == CMD_RECLAIM)

    -- R-hold detection only matters in "both" mode. In other modes the right
    -- click alone picks the gesture, and R is left to the engine (Repair).
    if widgetMode ~= "both" then
        if rPressTime or rKeyDown then
            rPressTime = nil
            rKeyDown   = false
        end
        return
    end

    -- Promote a sustained R press into "hold" once it crosses the threshold.
    if rPressTime and not rKeyDown then
        if Spring.DiffTimers(Spring.GetTimer(), rPressTime) >= R_HOLD_SECONDS then
            rKeyDown = true
        end
    end

    -- If the Reclaim cursor went away, drop any in-flight R state.
    if not reclaimCursorActive and (rPressTime or rKeyDown) then
        rPressTime = nil
        rKeyDown   = false
    end
end

function widget:KeyPress(key, mods, isRepeat)
    -- Only the "both" mode needs to intercept R. Other modes leave it alone.
    if widgetMode ~= "both" then return false end
    if key == KEY_R and not isRepeat then
        -- Only intercept R while the Reclaim cursor is up. A short press is a
        -- "tap" and stays harmless (we just swallow it so it doesn't kick the
        -- active command over to Repair); a long press promotes to rect mode
        -- via Update(). Outside of Reclaim, leave R alone for normal Repair.
        if reclaimCursorActive then
            rPressTime = Spring.GetTimer()
            return true
        end
    end
    return false
end

function widget:KeyRelease(key, mods)
    if widgetMode ~= "both" then return false end
    if key == KEY_R then
        rPressTime = nil
        rKeyDown   = false
    end
    return false
end

function widget:MousePress(mx, my, button)
    if button ~= 3 then return false end
    if not reclaimCursorActive then return false end
    local x, z = groundFromMouse(mx, my)
    if not x then return false end

    anchorX, anchorZ = x, z
    hoveredUnitDefID = unitDefUnderCursor(mx, my)

    -- Pick gesture by widget mode.
    local useRect
    if widgetMode == "square" then
        useRect = false
    elseif widgetMode == "draw" then
        useRect = true
    else  -- "both"
        useRect = rKeyDown
    end

    if useRect then
        mode = "rect"
        farX, farZ = x, z
    else
        mode = "square"
        halfWidth = 0
    end
    dbg("MousePress: mode=" .. mode .. " (widgetMode=" .. widgetMode .. ") at "
        .. math.floor(x) .. "," .. math.floor(z) .. " hoveredDef=" .. tostring(hoveredUnitDefID))
    return true
end

function widget:MouseMove(mx, my, dx, dy, button)
    if not mode then return end
    local x, z = groundFromMouse(mx, my)
    if not x then return end
    if mode == "square" then
        local dist = math.max(math.abs(x - anchorX), math.abs(z - anchorZ))
        halfWidth = snap(dist)
    else
        -- Snap each axis to the grid relative to the anchor as the cursor
        -- moves, so the rectangle visibly grows/shrinks in 16-elmo steps.
        local ddx = x - anchorX
        local ddz = z - anchorZ
        local sx  = snap(math.abs(ddx)) * (ddx >= 0 and 1 or -1)
        local sz  = snap(math.abs(ddz)) * (ddz >= 0 and 1 or -1)
        farX = anchorX + sx
        farZ = anchorZ + sz
    end
end

function widget:MouseRelease(mx, my, button)
    if not mode then return false end
    if button ~= 3 then return false end

    local x1, z1, x2, z2 = bounds()
    local thisMode = mode
    mode = nil

    if tooSmall(x1, z1, x2, z2) then
        dbg("MouseRelease(" .. thisMode .. "): below grid, canceling cursor")
        if spSetActiveCommand then spSetActiveCommand(-1) end
        return true
    end

    local selected = spGetSelectedUnits()
    if not selected or #selected == 0 then
        dbg("MouseRelease: no selected units")
        if spSetActiveCommand then spSetActiveCommand(-1) end
        return true
    end

    local alt, ctrl, _, shift = spGetModKeyState()

    local rawFeatures = spGetFeaturesInRectangle(x1, z1, x2, z2) or {}
    local rawUnits    = spGetUnitsInRectangle(x1, z1, x2, z2) or {}

    local selectedSet = {}
    for _, uID in ipairs(selected) do selectedSet[uID] = true end

    -- Target policy:
    --   default (no mods)            -> features + ONLY currently-selected units in the rect
    --                                   (lets a group of builders eat each other when
    --                                   explicitly selected; non-selected buildings ignored)
    --   ALT + hovered unit           -> only units of that defID (no features)
    --   ALT (no hovered unit)        -> features + ALL units in the rect
    --   CTRL                         -> features (incl. non-autoreclaimable) + ALL units
    --   ALT + CTRL (no hovered unit) -> same as CTRL alone
    local features, targetUnits
    if alt and hoveredUnitDefID then
        targetUnits = collectUnits(rawUnits, hoveredUnitDefID)
        features    = {}
    elseif alt or ctrl then
        features    = collectFeatures(rawFeatures, ctrl)
        targetUnits = collectUnits(rawUnits, nil)
    else
        features    = collectFeatures(rawFeatures, ctrl)
        targetUnits = {}
        for _, uID in ipairs(rawUnits) do
            if selectedSet[uID] then
                targetUnits[#targetUnits + 1] = uID
            end
        end
    end

    -- Sort origin is the click point (anchorX, anchorZ) so reclaim starts from
    -- where the cursor first went down. For square mode that's the center; for
    -- rect mode that's the anchor corner.
    local originX, originZ = anchorX, anchorZ

    dbg(string.format(
        "MouseRelease(%s): area %d,%d -> %d,%d | mods alt=%s ctrl=%s shift=%s | %d features, %d units",
        thisMode,
        math.floor(x1), math.floor(z1), math.floor(x2), math.floor(z2),
        tostring(alt), tostring(ctrl), tostring(shift),
        #features, #targetUnits))

    if #features == 0 and #targetUnits == 0 then
        if spSetActiveCommand then spSetActiveCommand(-1) end
        return true
    end

    -- Combine features + units into one list, sorted by distance from the click point.
    local targets = {}
    for _, fID in ipairs(features) do
        local fx, _, fz = spGetFeaturePosition(fID)
        if fx then
            local dx, dz = fx - originX, fz - originZ
            targets[#targets + 1] = { param = fID + maxUnits, wx = fx, wz = fz, d2 = dx * dx + dz * dz }
        end
    end
    for _, tID in ipairs(targetUnits) do
        local ux, _, uz = spGetUnitPosition(tID)
        if ux then
            local dx, dz = ux - originX, uz - originZ
            targets[#targets + 1] = { param = tID, wx = ux, wz = uz, d2 = dx * dx + dz * dz }
        end
    end
    table.sort(targets, function(a, b) return a.d2 < b.d2 end)

    local allImmobile = true
    for _, uID in ipairs(selected) do
        if not isImmobileBuilder(spGetUnitDefID(uID)) then
            allImmobile = false
            break
        end
    end

    -- A builder can never reclaim itself; t.param == uID for unit targets means
    -- the target IS this builder. Features use fID + maxUnits as their param so
    -- they never collide with a unitID and always pass this check.
    local orderCount = 0
    if allImmobile then
        for _, uID in ipairs(selected) do
            local defID = spGetUnitDefID(uID)
            local range = (UnitDefs[defID] and UnitDefs[defID].buildDistance) or 0
            local rangeSq = range * range
            local ux, _, uz = spGetUnitPosition(uID)
            if ux and range > 0 then
                local first = true
                for _, t in ipairs(targets) do
                    if t.param ~= uID then
                        local dx, dz = t.wx - ux, t.wz - uz
                        if dx * dx + dz * dz <= rangeSq then
                            local addQueue = shift or not first
                            local opts = addQueue and { "shift" } or 0
                            spGiveOrderToUnit(uID, CMD_RECLAIM, { t.param }, opts)
                            first = false
                            orderCount = orderCount + 1
                        end
                    end
                end
            end
        end
        dbg("MouseRelease: issued " .. orderCount .. " orders to " .. #selected .. " immobile builders (per-unit range filtered)")
    else
        for _, uID in ipairs(selected) do
            local first = true
            for _, t in ipairs(targets) do
                if t.param ~= uID then
                    local addQueue = shift or not first
                    local opts = addQueue and { "shift" } or 0
                    spGiveOrderToUnit(uID, CMD_RECLAIM, { t.param }, opts)
                    first = false
                    orderCount = orderCount + 1
                end
            end
        end
        dbg("MouseRelease: issued " .. orderCount .. " orders to " .. #selected .. " builders (mixed/mobile, no range filter)")
    end

    if not shift and spSetActiveCommand then
        spSetActiveCommand(-1)
    end
    return true
end

local function drawOutline(x1, z1, x2, z2)
    local steps = 24
    local function edge(ax, az, bx, bz, includeFirst)
        local from = includeFirst and 0 or 1
        for i = from, steps do
            local t = i / steps
            local x = ax + (bx - ax) * t
            local z = az + (bz - az) * t
            gl.Vertex(x, spGetGroundHeight(x, z) + 4, z)
        end
    end
    edge(x1, z1, x2, z1, true)
    edge(x2, z1, x2, z2, false)
    edge(x2, z2, x1, z2, false)
    edge(x1, z2, x1, z1, false)
end

function widget:DrawWorld()
    if not mode then return end
    local x1, z1, x2, z2 = bounds()
    if (x2 - x1) <= 0 or (z2 - z1) <= 0 then return end

    -- Modifier tints take priority over the mode's default color.
    local alt, ctrl = spGetModKeyState()
    local r, g, b
    if alt and hoveredUnitDefID then
        r, g, b = 1.0, 0.6, 0.2   -- orange = unit-type filter
    elseif ctrl then
        r, g, b = 0.4, 0.7, 1.0   -- blue   = include non-autoreclaimable
    elseif mode == "rect" then
        r, g, b = 0.3, 0.9, 0.9   -- cyan   = rectangle default
    else
        r, g, b = 0.3, 1.0, 0.3   -- green  = square default
    end

    gl.DepthTest(false)

    gl.Color(r, g, b, 0.18)
    gl.DrawGroundQuad(x1, z1, x2, z2)

    gl.LineWidth(2.0)
    gl.Color(r, g, b, 0.9)
    gl.BeginEnd(GL.LINE_LOOP, drawOutline, x1, z1, x2, z2)

    gl.Color(1, 1, 1, 1)
    gl.LineWidth(1.0)
    gl.DepthTest(true)
end
