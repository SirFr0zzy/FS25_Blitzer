-- Placeable specialization: stationary speed camera ("Blitzer").
--  * Detection runs on the server: every vehicle inside a 90 degree cone in front of the column
--    (and within range) that is faster than the configured limit triggers a flash.
--  * The speed limit is changed at the column (interact near the panel, +10 km/h per press).

source(Utils.getFilename("scripts/BlitzerEvents.lua", g_currentModDirectory))

PlaceableBlitzer = {}

PlaceableBlitzer.LIMIT_STEP = 10
PlaceableBlitzer.FLASH_DURATION = 250      -- ms the flash light stays on
PlaceableBlitzer.VEHICLE_COOLDOWN = 4000   -- ms before the same vehicle can be flashed again
PlaceableBlitzer.INTERACT_DISTANCE = 3.0   -- m to the panel

function PlaceableBlitzer.prerequisitesPresent(specializations)
    return true
end

function PlaceableBlitzer.registerXMLPaths(schema)
    schema:setXMLSpecializationType("Blitzer")
    schema:register(XMLValueType.NODE_INDEX, "placeable.blitzer#sensorNode", "Node at the lens, +Z is the viewing direction")
    schema:register(XMLValueType.NODE_INDEX, "placeable.blitzer#panelNode", "Node of the operating panel on the column")
    schema:register(XMLValueType.NODE_INDEX, "placeable.blitzer#flashNode", "Flash light node (visibility toggled)")
    schema:register(XMLValueType.FLOAT, "placeable.blitzer#angle", "Detection cone angle in degrees", 90)
    schema:register(XMLValueType.FLOAT, "placeable.blitzer#range", "Detection range in meters", 60)
    schema:register(XMLValueType.INT, "placeable.blitzer#minLimit", "Lowest selectable limit (km/h)", 20)
    schema:register(XMLValueType.INT, "placeable.blitzer#maxLimit", "Highest selectable limit (km/h)", 150)
    schema:register(XMLValueType.INT, "placeable.blitzer#defaultLimit", "Default limit (km/h)", 50)
    schema:setXMLSpecializationType()
end

function PlaceableBlitzer.registerSavegameXMLPaths(schema, basePath)
    schema:setXMLSpecializationType("Blitzer")
    schema:register(XMLValueType.INT, basePath .. "#speedLimit", "Configured speed limit (km/h)")
    schema:setXMLSpecializationType()
end

function PlaceableBlitzer.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "setBlitzerLimit", PlaceableBlitzer.setBlitzerLimit)
    SpecializationUtil.registerFunction(placeableType, "onBlitzerFlash", PlaceableBlitzer.onBlitzerFlash)
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
    self.placeable:setBlitzerLimit(limit)
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
    spec.range = xmlFile:getValue("placeable.blitzer#range", 60)
    spec.minLimit = xmlFile:getValue("placeable.blitzer#minLimit", 20)
    spec.maxLimit = xmlFile:getValue("placeable.blitzer#maxLimit", 150)
    spec.speedLimit = xmlFile:getValue("placeable.blitzer#defaultLimit", 50)

    spec.flashTimer = 0
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
    self:raiseActive()
end

function PlaceableBlitzer:onDelete()
    local spec = self.spec_blitzer
    if spec.activatableAdded and g_currentMission ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
    end
    spec.activatableAdded = false
end

function PlaceableBlitzer:setBlitzerLimit(limit, noEventSend)
    local spec = self.spec_blitzer
    limit = math.clamp(limit, spec.minLimit, spec.maxLimit)
    if limit == spec.speedLimit then
        return
    end
    BlitzerSetLimitEvent.sendEvent(self, limit, noEventSend)
    spec.speedLimit = limit
    spec.activatable:updateText()
end

function PlaceableBlitzer:onBlitzerFlash(vehicle, speed)
    local spec = self.spec_blitzer
    spec.flashTimer = PlaceableBlitzer.FLASH_DURATION
    if spec.flashNode ~= nil then
        setVisibility(spec.flashNode, true)
    end
    self:raiseActive()

    -- tell the driver (only on the machine that controls the vehicle)
    if vehicle ~= nil and vehicle.getIsControlled ~= nil and vehicle:getIsControlled()
        and g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        local text = string.format(g_i18n:getText("blitzer_flashed"), g_i18n:getSpeed(speed),
            g_i18n:getSpeedMeasuringUnit(), g_i18n:getSpeed(spec.speedLimit), g_i18n:getSpeedMeasuringUnit())
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, text)
    end
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
            if speed > spec.speedLimit then
                local wx, wy, wz = getWorldTranslation(vehicle.rootNode)
                local lx, _, lz = worldToLocal(spec.sensorNode, wx, wy, wz)
                -- in front of the lens, inside the cone (|x| <= z * tan(half angle)), inside range
                if lz > 0.5 and math.abs(lx) <= lz * halfAngleTan and (lx * lx + lz * lz) <= spec.range * spec.range then
                    spec.cooldowns[vehicle] = PlaceableBlitzer.VEHICLE_COOLDOWN
                    g_server:broadcastEvent(BlitzerFlashEvent.new(self, vehicle, math.floor(speed + 0.5)), true)
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

    -- offer the interaction while the local player stands near the panel
    if self.isClient and g_localPlayer ~= nil and spec.panelNode ~= nil then
        local x, y, z = getWorldTranslation(g_localPlayer.rootNode)
        local near = spec.activatable:getDistance(x, y, z) <= PlaceableBlitzer.INTERACT_DISTANCE
        if near and not spec.activatableAdded then
            g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
            spec.activatableAdded = true
        elseif not near and spec.activatableAdded then
            g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
            spec.activatableAdded = false
        end
    end
end

function PlaceableBlitzer:onWriteStream(streamId, connection)
    streamWriteUInt8(streamId, self.spec_blitzer.speedLimit)
end

function PlaceableBlitzer:onReadStream(streamId, connection)
    local spec = self.spec_blitzer
    spec.speedLimit = streamReadUInt8(streamId)
    spec.activatable:updateText()
end

function PlaceableBlitzer:saveToXMLFile(xmlFile, key, usedModNames)
    xmlFile:setValue(key .. "#speedLimit", self.spec_blitzer.speedLimit)
end

function PlaceableBlitzer:loadFromXMLFile(xmlFile, key)
    local spec = self.spec_blitzer
    local limit = xmlFile:getValue(key .. "#speedLimit")
    if limit ~= nil then
        spec.speedLimit = math.clamp(limit, spec.minLimit, spec.maxLimit)
        spec.activatable:updateText()
    end
end
