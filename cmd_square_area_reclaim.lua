function widget:GetInfo()
    return {
        name    = "Square Area Reclaim",
        desc    = "While the Reclaim cursor is active (E), right-click-drag to reclaim in a grid-snapped square. Modifiers: SHIFT queues, ALT (while hovering a unit on press) restricts to that unit-type, CTRL includes non-autoreclaimable features and prioritizes metal first.",
        author  = "Zack Cheang",
        date    = "2026-05-15",
        license = "GNU GPL v2 or later",
        layer   = 0,
        enabled = true,
    }
end

local CMD_RECLAIM = CMD.RECLAIM
local GRID        = 16
local mapSizeX    = Game.mapSizeX
local mapSizeZ    = Game.mapSizeZ
local maxUnits    = Game.maxUnits

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
local spGetFeatureResources    = Spring.GetFeatureResources
local spEcho                   = Spring.Echo

local function dbg(...)
    if DEBUG then spEcho("[SquareReclaim]", ...) end
end

local dragging       = false
local startX, startZ = 0, 0
local halfWidth      = 0
-- Captured at MousePress, used at MouseRelease for ALT unit-type filter.
local hoveredUnitDefID = nil
-- Cached because the engine may clear the active command on right-mouse-down
-- before widget:MousePress runs. We refresh this every frame in widget:Update.
local reclaimCursorActive = false

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

local function squareBounds()
    local x1 = clamp(startX - halfWidth, 0, mapSizeX)
    local z1 = clamp(startZ - halfWidth, 0, mapSizeZ)
    local x2 = clamp(startX + halfWidth, 0, mapSizeX)
    local z2 = clamp(startZ + halfWidth, 0, mapSizeZ)
    return x1, z1, x2, z2
end

function widget:Initialize()
    dbg("loaded")
end

function widget:Update()
    local _, cmdID = spGetActiveCommand()
    reclaimCursorActive = (cmdID == CMD_RECLAIM)
end

function widget:MousePress(mx, my, button)
    dbg("MousePress button=" .. tostring(button) .. " reclaimActive=" .. tostring(reclaimCursorActive))
    if button ~= 3 then return false end
    if not reclaimCursorActive then return false end
    local x, z = groundFromMouse(mx, my)
    if not x then
        dbg("MousePress: no ground hit")
        return false
    end
    startX, startZ = x, z
    halfWidth = 0
    hoveredUnitDefID = unitDefUnderCursor(mx, my)
    dragging = true
    dbg("MousePress: drag started at " .. math.floor(x) .. "," .. math.floor(z)
        .. " hoveredDef=" .. tostring(hoveredUnitDefID))
    return true
end

function widget:MouseMove(mx, my, dx, dy, button)
    if not dragging then return end
    local x, z = groundFromMouse(mx, my)
    if not x then return end
    local dist = math.max(math.abs(x - startX), math.abs(z - startZ))
    halfWidth = snap(dist)
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

local function collectUnits(rawUnits, selectedSet, altHeld, defFilter)
    local out = {}
    for _, uID in ipairs(rawUnits) do
        if not selectedSet[uID] then
            if altHeld and defFilter then
                if spGetUnitDefID(uID) == defFilter then
                    out[#out + 1] = uID
                end
            else
                out[#out + 1] = uID
            end
        end
    end
    return out
end

function widget:MouseRelease(mx, my, button)
    if not dragging then return false end
    if button ~= 3 then return false end
    dragging = false
    dbg("MouseRelease: halfWidth=" .. halfWidth)

    if halfWidth < GRID then
        dbg("MouseRelease: below grid, canceling cursor")
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

    local x1, z1, x2, z2 = squareBounds()
    local rawFeatures = spGetFeaturesInRectangle(x1, z1, x2, z2) or {}
    local rawUnits    = spGetUnitsInRectangle(x1, z1, x2, z2) or {}

    local selectedSet = {}
    for _, uID in ipairs(selected) do selectedSet[uID] = true end

    local features, targetUnits

    if alt and hoveredUnitDefID then
        -- ALT + hovered unit: restrict to that unit-type, ignore features entirely
        -- (matches BAR's "reclaim only this unit-type in area" behavior).
        targetUnits = collectUnits(rawUnits, selectedSet, true, hoveredUnitDefID)
        features    = {}
    else
        features    = collectFeatures(rawFeatures, ctrl)
        targetUnits = collectUnits(rawUnits, selectedSet, false, nil)
    end

    dbg(string.format(
        "MouseRelease: square %d,%d -> %d,%d | mods alt=%s ctrl=%s shift=%s | %d features, %d units",
        math.floor(x1), math.floor(z1), math.floor(x2), math.floor(z2),
        tostring(alt), tostring(ctrl), tostring(shift),
        #features, #targetUnits))

    if #features == 0 and #targetUnits == 0 then
        if spSetActiveCommand then spSetActiveCommand(-1) end
        return true
    end

    -- Combine features + units into one list, sorted by distance from square center
    -- (startX, startZ is the click point, which is also the square's center).
    -- World coords (wx, wz) are kept so per-turret range filtering can reuse them.
    local targets = {}
    for _, fID in ipairs(features) do
        local fx, _, fz = spGetFeaturePosition(fID)
        if fx then
            local dx, dz = fx - startX, fz - startZ
            targets[#targets + 1] = { param = fID + maxUnits, wx = fx, wz = fz, d2 = dx * dx + dz * dz }
        end
    end
    for _, tID in ipairs(targetUnits) do
        local ux, _, uz = spGetUnitPosition(tID)
        if ux then
            local dx, dz = ux - startX, uz - startZ
            targets[#targets + 1] = { param = tID, wx = ux, wz = uz, d2 = dx * dx + dz * dz }
        end
    end
    table.sort(targets, function(a, b) return a.d2 < b.d2 end)

    -- If every selected unit is an immobile builder (nano turrets, factories),
    -- give each one only the targets within its own buildDistance.
    -- Mixed selection (any mobile unit present) uses the original behavior.
    local allImmobile = true
    for _, uID in ipairs(selected) do
        if not isImmobileBuilder(spGetUnitDefID(uID)) then
            allImmobile = false
            break
        end
    end

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
        dbg("MouseRelease: issued " .. orderCount .. " orders to " .. #selected .. " immobile builders (per-unit range filtered)")
    else
        for _, uID in ipairs(selected) do
            local first = true
            for _, t in ipairs(targets) do
                local addQueue = shift or not first
                local opts = addQueue and { "shift" } or 0
                spGiveOrderToUnit(uID, CMD_RECLAIM, { t.param }, opts)
                first = false
                orderCount = orderCount + 1
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
    if not dragging or halfWidth <= 0 then return end
    local x1, z1, x2, z2 = squareBounds()

    -- Tint by modifier so it's visually obvious which mode you're in.
    local alt, ctrl = spGetModKeyState()
    local r, g, b
    if alt and hoveredUnitDefID then
        r, g, b = 1.0, 0.6, 0.2   -- orange = unit-type filter
    elseif ctrl then
        r, g, b = 0.4, 0.7, 1.0   -- blue  = force/metal-first
    else
        r, g, b = 0.3, 1.0, 0.3   -- green = standard
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
