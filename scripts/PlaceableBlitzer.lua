-- Placeable specialization: stationary speed camera ("Blitzer").
--  * Detection runs on the server: every vehicle inside a 90 degree cone in front of the column
--    (and within range) that is faster than the configured limit triggers a flash.
--  * The speed limit is changed at the column (interact near the panel, +10 km/h per press).

PlaceableBlitzer = {}

PlaceableBlitzer.LIMIT_STEP = 10
PlaceableBlitzer.FLASH_DURATION = 250      -- ms the flash light stays on
PlaceableBlitzer.TOLERANCE = 3            -- km/h above the limit before a vehicle is flashed
PlaceableBlitzer.VEHICLE_COOLDOWN = 4000   -- ms before the same vehicle can be flashed again
PlaceableBlitzer.INTERACT_DISTANCE = 3.0   -- m to the panel
PlaceableBlitzer.RANGE_SHOW_TIME = 8000    -- ms the range outline stays visible
PlaceableBlitzer.RANGE_MIN, PlaceableBlitzer.RANGE_MAX, PlaceableBlitzer.RANGE_STEP = 10, 60, 5      -- m
PlaceableBlitzer.ANGLE_MIN, PlaceableBlitzer.ANGLE_MAX, PlaceableBlitzer.ANGLE_STEP = 30, 120, 15   -- degrees

function PlaceableBlitzer.prerequisitesPresent(specializations)
    return true
end

function PlaceableBlitzer.registerXMLPaths(schema)
    schema:setXMLSpecializationType("Blitzer")
    schema:register(XMLValueType.NODE_INDEX, "placeable.blitzer#sensorNode", "Node at the lens, +Z is the viewing direction")
    schema:register(XMLValueType.NODE_INDEX, "placeable.blitzer#panelNode", "Node of the operating panel on the column")
    schema:register(XMLValueType.NODE_INDEX, "placeable.blitzer#flashNode", "Flash light node (visibility toggled)")
    schema:register(XMLValueType.FLOAT, "placeable.blitzer#angle", "Detection cone angle in degrees", 90)
    schema:register(XMLValueType.FLOAT, "placeable.blitzer#range", "Detection range in meters", 30)
    schema:register(XMLValueType.INT, "placeable.blitzer#minLimit", "Lowest selectable limit (km/h)", 20)
    schema:register(XMLValueType.INT, "placeable.blitzer#maxLimit", "Highest selectable limit (km/h)", 150)
    schema:register(XMLValueType.INT, "placeable.blitzer#defaultLimit", "Default limit (km/h)", 50)
    schema:setXMLSpecializationType()
end

function PlaceableBlitzer.registerSavegameXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("Blitzer")
    schema:register(XMLValueType.INT, basePath .. "#speedLimit", "Configured speed limit (km/h)")
    schema:register(XMLValueType.INT, basePath .. "#range", "Configured detection range (m)")
    schema:register(XMLValueType.INT, basePath .. "#angle", "Configured detection angle (degrees)")
    schema:setXMLSpecializationType()
end

function PlaceableBlitzer.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "setBlitzerSettings", PlaceableBlitzer.setBlitzerSettings)
    SpecializationUtil.registerFunction(placeableType, "showBlitzerRange", PlaceableBlitzer.showBlitzerRange)
    SpecializationUtil.registerFunction(placeableType, "onBlitzerFlash", PlaceableBlitzer.onBlitzerFlash)
    SpecializationUtil.registerFunction(placeableType, "registerRangeAction", PlaceableBlitzer.registerRangeAction)
    SpecializationUtil.registerFunction(placeableType, "removeRangeAction", PlaceableBlitzer.removeRangeAction)
    SpecializationUtil.registerFunction(placeableType, "checkBlitzerVehicles", PlaceableBlitzer.checkBlitzerVehicles)
end

function PlaceableBlitzer.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onPreLoad", PlaceableBlitzer)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", PlaceableBlitzer)
    SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", PlaceableBlitzer)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", PlaceableBlitzer)
    SpecializationUtil.registerEventListener(placeableType, "onUpdate", PlaceableBlitzer)
    SpecializationUtil.registerEventListener(placeableType, "onReadStream", PlaceableBlitzer)
    SpecializationUtil.registerEventListener(placeableType, "onWriteStream", PlaceableBlitzer)
end

---------------------------------------------------------------------------
-- Activatable (interaction at the panel)
---------------------------------------------------------------------------

BlitzerActivatable = {}
local BlitzerActivatable_mt = Class(BlitzerActivatable)

function BlitzerActivatable.new(placeable)
    local self = setmetatable({}, BlitzerActivatable_mt)
    self.placeable = placeable
    self.activateText = ""
    self:updateText()
    return self
end

function BlitzerActivatable:updateText()
    local spec = self.placeable.spec_blitzer
    self.activateText = string.format(g_i18n:getText("blitzer_setlimit"),
        g_i18n:getSpeed(spec.speedLimit), g_i18n:getSpeedMeasuringUnit())
end

function BlitzerActivatable:getIsActivatable()
    return self.placeable.spec_blitzer.panelNode ~= nil
end

function BlitzerActivatable:getDistance(x, y, z)
    local node = self.placeable.spec_blitzer.panelNode
    if node == nil then
        return math.huge
    end
    local px, py, pz = getWorldTranslation(node)
    return MathUtil.vector3Length(x - px, y - py, z - pz)
end

function BlitzerActivatable:run()
    local spec = self.placeable.spec_blitzer
    local limit = spec.speedLimit + PlaceableBlitzer.LIMIT_STEP
    if limit > spec.maxLimit then
        limit = spec.minLimit
    end
    self.placeable:setBlitzerSettings(limit, spec.range, spec.angle)
end

---------------------------------------------------------------------------

function PlaceableBlitzer:onPreLoad(savegame)
    self.spec_blitzer = {}
end

function PlaceableBlitzer:onLoad(savegame)
    local spec = self.spec_blitzer
    local xmlFile = self.xmlFile

    spec.sensorNode = xmlFile:getValue("placeable.blitzer#sensorNode", nil, self.components, self.i3dMappings)
    spec.panelNode = xmlFile:getValue("placeable.blitzer#panelNode", nil, self.components, self.i3dMappings)
    spec.flashNode = xmlFile:getValue("placeable.blitzer#flashNode", nil, self.components, self.i3dMappings)
    spec.angle = xmlFile:getValue("placeable.blitzer#angle", 90)
    spec.range = xmlFile:getValue("placeable.blitzer#range", 30)
    spec.minLimit = xmlFile:getValue("placeable.blitzer#minLimit", 20)
    spec.maxLimit = xmlFile:getValue("placeable.blitzer#maxLimit", 150)
    spec.speedLimit = xmlFile:getValue("placeable.blitzer#defaultLimit", 50)

    spec.flashTimer = 0
    spec.rangeTimer = 0
    spec.cooldowns = {}
    spec.finalized = false
    spec.activatable = BlitzerActivatable.new(self)
    spec.activatableAdded = false

    if spec.flashNode ~= nil then
        setVisibility(spec.flashNode, false)
    end
end

function PlaceableBlitzer:onFinalizePlacement()
    local spec = self.spec_blitzer
    spec.finalized = true
    BlitzerManager.registerPlaceable(self)
    self:raiseActive()
end

function PlaceableBlitzer:onDelete()
    local spec = self.spec_blitzer
    BlitzerManager.unregisterPlaceable(self)
    if spec.activatableAdded and g_currentMission ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
        self:removeRangeAction()
    end
    spec.activatableAdded = false
end

function PlaceableBlitzer:setBlitzerSettings(limit, range, angle, noEventSend)
    local spec = self.spec_blitzer
    limit = math.clamp(limit, spec.minLimit, spec.maxLimit)
    range = math.clamp(range, PlaceableBlitzer.RANGE_MIN, PlaceableBlitzer.RANGE_MAX)
    angle = math.clamp(angle, PlaceableBlitzer.ANGLE_MIN, PlaceableBlitzer.ANGLE_MAX)
    if limit == spec.speedLimit and range == spec.range and angle == spec.angle then
        return
    end
    BlitzerSetLimitEvent.sendEvent(self, limit, range, angle, noEventSend)
    spec.speedLimit = limit
    spec.range = range
    spec.angle = angle
    spec.activatable:updateText()
    self:showBlitzerRange()
end

function PlaceableBlitzer:showBlitzerRange()
    self.spec_blitzer.rangeTimer = PlaceableBlitzer.RANGE_SHOW_TIME
    self:raiseActive()
end

function PlaceableBlitzer:onBlitzerFlash()
    local spec = self.spec_blitzer
    spec.flashTimer = PlaceableBlitzer.FLASH_DURATION
    if spec.flashNode ~= nil then
        setVisibility(spec.flashNode, true)
    end
    self:raiseActive()
end

-- Server only: flash every vehicle inside the cone that is too fast.
function PlaceableBlitzer:checkBlitzerVehicles(dt)
    local spec = self.spec_blitzer
    if spec.sensorNode == nil then
        return
    end

    for vehicle, t in pairs(spec.cooldowns) do
        if t - dt <= 0 then
            spec.cooldowns[vehicle] = nil
        else
            spec.cooldowns[vehicle] = t - dt
        end
    end

    local halfAngleTan = math.tan(math.rad(spec.angle * 0.5))
    local vehicles = g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles or {}
    for _, vehicle in ipairs(vehicles) do
        if vehicle.getLastSpeed ~= nil and vehicle.rootNode ~= nil and vehicle.rootVehicle == vehicle
            and spec.cooldowns[vehicle] == nil then
            local speed = math.abs(vehicle:getLastSpeed() or 0)
            if speed >= spec.speedLimit + PlaceableBlitzer.TOLERANCE then
                local wx, wy, wz = getWorldTranslation(vehicle.rootNode)
                local lx, _, lz = worldToLocal(spec.sensorNode, wx, wy, wz)
                -- in front of the lens, inside the cone (|x| <= z * tan(half angle)), inside range
                if lz > 0.5 and math.abs(lx) <= lz * halfAngleTan and (lx * lx + lz * lz) <= spec.range * spec.range then
                    spec.cooldowns[vehicle] = PlaceableBlitzer.VEHICLE_COOLDOWN
                    -- everybody only sees the flash itself; speed/plate go to the admin log only
                    g_server:broadcastEvent(BlitzerFlashEvent.new(self), true)
                    BlitzerManager.addEntry(self, vehicle, math.floor(speed + 0.5))
                end
            end
        end
    end
end

function PlaceableBlitzer:onUpdate(dt)
    local spec = self.spec_blitzer
    if not spec.finalized then
        return
    end
    self:raiseActive()

    if self.isServer then
        self:checkBlitzerVehicles(dt)
    end

    if spec.flashTimer > 0 then
        spec.flashTimer = spec.flashTimer - dt
        if spec.flashTimer <= 0 and spec.flashNode ~= nil then
            setVisibility(spec.flashNode, false)
        end
    end

    if spec.rangeTimer > 0 then
        spec.rangeTimer = spec.rangeTimer - dt
    end

    -- offer the interaction while the local player stands near the panel
    if self.isClient and g_localPlayer ~= nil and spec.panelNode ~= nil then
        local x, y, z = getWorldTranslation(g_localPlayer.rootNode)
        local near = spec.activatable:getDistance(x, y, z) <= PlaceableBlitzer.INTERACT_DISTANCE
        if near and not spec.activatableAdded then
            g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
            spec.activatableAdded = true
            self:registerRangeAction()
        elseif not near and spec.activatableAdded then
            g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
            spec.activatableAdded = false
            self:removeRangeAction()
        end
    end
end

function PlaceableBlitzer:onWriteStream(streamId, connection)
    local spec = self.spec_blitzer
    streamWriteUInt8(streamId, spec.speedLimit)
    streamWriteUInt8(streamId, spec.range)
    streamWriteUInt8(streamId, spec.angle)
end

function PlaceableBlitzer:onReadStream(streamId, connection)
    local spec = self.spec_blitzer
    spec.speedLimit = streamReadUInt8(streamId)
    spec.range = streamReadUInt8(streamId)
    spec.angle = streamReadUInt8(streamId)
    spec.activatable:updateText()
end

function PlaceableBlitzer:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_blitzer
    xmlFile:setValue(key .. "#speedLimit", spec.speedLimit)
    xmlFile:setValue(key .. "#range", spec.range)
    xmlFile:setValue(key .. "#angle", spec.angle)
end

function PlaceableBlitzer:loadFromXMLFile(xmlFile, key)
    local spec = self.spec_blitzer
    local limit = xmlFile:getValue(key .. "#speedLimit")
    if limit ~= nil then
        spec.speedLimit = math.clamp(limit, spec.minLimit, spec.maxLimit)
    end
    local range = xmlFile:getValue(key .. "#range")
    if range ~= nil then
        spec.range = math.clamp(range, PlaceableBlitzer.RANGE_MIN, PlaceableBlitzer.RANGE_MAX)
    end
    local angle = xmlFile:getValue(key .. "#angle")
    if angle ~= nil then
        spec.angle = math.clamp(angle, PlaceableBlitzer.ANGLE_MIN, PlaceableBlitzer.ANGLE_MAX)
    end
    spec.activatable:updateText()
end

---------------------------------------------------------------------------
-- Range outline (temporary)
---------------------------------------------------------------------------

-- keys while standing at the panel: show area, change range, change angle
function PlaceableBlitzer:registerRangeAction()
    local spec = self.spec_blitzer
    spec.actionEventIds = {}
    g_inputBinding:beginActionEventsModification()
    local defs = {
        { InputAction.BLITZER_SHOW_RANGE, PlaceableBlitzer.onShowRangeAction, "blitzer_showrange" },
        { InputAction.BLITZER_CHANGE_RANGE, PlaceableBlitzer.onChangeRangeAction, "blitzer_changerange" },
        { InputAction.BLITZER_CHANGE_ANGLE, PlaceableBlitzer.onChangeAngleAction, "blitzer_changeangle" },
    }
    for _, def in ipairs(defs) do
        if def[1] ~= nil then
            local _, eventId = g_inputBinding:registerActionEvent(def[1], self, def[2], false, true, false, true)
            if eventId ~= nil then
                g_inputBinding:setActionEventText(eventId, g_i18n:getText(def[3]))
                g_inputBinding:setActionEventTextVisibility(eventId, true)
                g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_NORMAL)
                table.insert(spec.actionEventIds, eventId)
            end
        end
    end
    g_inputBinding:endActionEventsModification()
end

function PlaceableBlitzer:removeRangeAction()
    local spec = self.spec_blitzer
    if spec.actionEventIds ~= nil then
        for _, eventId in ipairs(spec.actionEventIds) do
            g_inputBinding:removeActionEvent(eventId)
        end
        spec.actionEventIds = nil
    end
end

function PlaceableBlitzer:onShowRangeAction()
    self:showBlitzerRange()
end

local function cycle(value, step, min, max)
    value = value + step
    if value > max then
        value = min
    end
    return value
end

function PlaceableBlitzer:onChangeRangeAction()
    local spec = self.spec_blitzer
    self:setBlitzerSettings(spec.speedLimit,
        cycle(spec.range, PlaceableBlitzer.RANGE_STEP, PlaceableBlitzer.RANGE_MIN, PlaceableBlitzer.RANGE_MAX), spec.angle)
end

function PlaceableBlitzer:onChangeAngleAction()
    local spec = self.spec_blitzer
    self:setBlitzerSettings(spec.speedLimit, spec.range,
        cycle(spec.angle, PlaceableBlitzer.ANGLE_STEP, PlaceableBlitzer.ANGLE_MIN, PlaceableBlitzer.ANGLE_MAX))
end

-- called every frame by BlitzerManager:draw()
function PlaceableBlitzer.drawRange(placeable)
    local spec = placeable.spec_blitzer
    if spec == nil or spec.rangeTimer <= 0 or spec.sensorNode == nil then
        return
    end

    local half = math.rad(spec.angle * 0.5)
    local steps = 16
    local function point(dist, a)
        -- local direction (sin a, 0, cos a): +Z is the viewing direction
        local wx, _, wz = localToWorld(spec.sensorNode, math.sin(a) * dist, 0, math.cos(a) * dist)
        return wx, getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, wx, 0, wz) + 0.25, wz
    end

    local ox, _, oz = localToWorld(spec.sensorNode, 0, 0, 0)
    local oy = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, ox, 0, oz) + 0.25
    local r, g, b = 1, 0.55, 0.05

    -- two side edges
    local lx, ly, lz = point(spec.range, -half)
    local rx, ry, rz = point(spec.range, half)
    drawDebugLine(ox, oy, oz, r, g, b, lx, ly, lz, r, g, b, false)
    drawDebugLine(ox, oy, oz, r, g, b, rx, ry, rz, r, g, b, false)

    -- outer arc plus an inner one at half range
    for _, dist in ipairs({ spec.range, spec.range * 0.5 }) do
        local px, py, pz = point(dist, -half)
        for i = 1, steps do
            local nx, ny, nz = point(dist, -half + (2 * half) * i / steps)
            drawDebugLine(px, py, pz, r, g, b, nx, ny, nz, r, g, b, false)
            px, py, pz = nx, ny, nz
        end
    end

    -- centre line
    local cx, cy, cz = point(spec.range, 0)
    drawDebugLine(ox, oy, oz, 1, 0.9, 0.3, cx, cy, cz, 1, 0.9, 0.3, false)
end
