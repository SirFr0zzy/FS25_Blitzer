-- Hand tool specialization: radar speed gun.
-- Hold the trigger (ACTIVATE_HANDTOOL), aim at a vehicle, the HUD shows its speed.
-- Purely client-side: the local player raycasts and reads the vehicle's last speed.

SpeedGunHandTool = {}

SpeedGunHandTool.DEBUG = false -- on-screen debug line + log output while measuring

local SPEC_NAME = "spec_" .. g_currentModName .. ".speedGun"

local RAY_MASK = CollisionFlag.STATIC_OBJECT + CollisionFlag.DYNAMIC_OBJECT + CollisionFlag.VEHICLE
    + CollisionFlag.TERRAIN + CollisionFlag.TERRAIN_DELTA + CollisionFlag.BUILDING

local function getSpec(handTool)
    return handTool[SPEC_NAME]
end

local function isLocalOwner(handTool)
    local player = handTool:getCarryingPlayer()
    return player ~= nil and g_localPlayer ~= nil and player == g_localPlayer
end

function SpeedGunHandTool.prerequisitesPresent(specializations)
    return true
end

function SpeedGunHandTool.registerXMLPaths(xmlSchema)
    xmlSchema:setXMLSpecializationType("SpeedGunHandTool")
    xmlSchema:register(XMLValueType.FLOAT, "handTool.speedGun#maxDistance", "Maximum measuring distance in meters", 300)
    xmlSchema:register(XMLValueType.NODE_INDEX, "handTool.speedGun#raycastNode", "Muzzle node, start of the visible beam")
    xmlSchema:setXMLSpecializationType()
end

function SpeedGunHandTool.registerFunctions(handToolType)
    SpecializationUtil.registerFunction(handToolType, "measure", SpeedGunHandTool.measure)
    SpecializationUtil.registerFunction(handToolType, "onRaycast", SpeedGunHandTool.onRaycast)
end

function SpeedGunHandTool.registerEventListeners(handToolType)
    SpecializationUtil.registerEventListener(handToolType, "onLoad", SpeedGunHandTool)
    SpecializationUtil.registerEventListener(handToolType, "onUpdate", SpeedGunHandTool)
    SpecializationUtil.registerEventListener(handToolType, "onDraw", SpeedGunHandTool)
    SpecializationUtil.registerEventListener(handToolType, "onHeldStart", SpeedGunHandTool)
    SpecializationUtil.registerEventListener(handToolType, "onHeldEnd", SpeedGunHandTool)
    SpecializationUtil.registerEventListener(handToolType, "onRegisterActionEvents", SpeedGunHandTool)
end

local function resetTarget(spec)
    spec.targetSpeed = nil
    spec.targetDistance = nil
    spec.hitX, spec.hitY, spec.hitZ = nil, nil, nil
    spec.beamEndX, spec.beamEndY, spec.beamEndZ = nil, nil, nil
end

function SpeedGunHandTool:onLoad(xmlFile, baseDirectory)
    local spec = getSpec(self)
    spec.maxDistance = xmlFile:getValue("handTool.speedGun#maxDistance", 300)
    spec.raycastNode = xmlFile:getValue("handTool.speedGun#raycastNode", nil, self.components, self.i3dMappings)
    spec.isMeasuring = false
    spec.debugText = ""
    resetTarget(spec)
end

function SpeedGunHandTool:onHeldStart()
    local spec = getSpec(self)
    spec.isMeasuring = false
    resetTarget(spec)
end

function SpeedGunHandTool:onHeldEnd()
    local spec = getSpec(self)
    spec.isMeasuring = false
    resetTarget(spec)
end

function SpeedGunHandTool:onRegisterActionEvents()
    if not self:getIsActiveForInput(true) then
        return
    end

    local _, eventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, SpeedGunHandTool.onMeasureAction, true, true, false, true, nil)
    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(eventId, g_i18n:getText("speedgun_measure"))
        g_inputBinding:setActionEventActive(eventId, true)
    end
end

function SpeedGunHandTool:onMeasureAction(actionName, inputValue)
    local spec = getSpec(self)
    spec.isMeasuring = inputValue > 0
    if spec.isMeasuring then
        self:raiseActive()
    else
        resetTarget(spec)
    end
end

function SpeedGunHandTool:onUpdate(dt)
    local spec = getSpec(self)
    if spec.isMeasuring then
        self:raiseActive()
    end
end

-- Casts the aiming ray from the camera and stores what it hits.
function SpeedGunHandTool:measure()
    local spec = getSpec(self)
    resetTarget(spec)

    local player = g_localPlayer
    local camera = player ~= nil and player.camera or nil
    if camera == nil or camera.cameraRootNode == nil then
        spec.debugText = "no camera"
        return
    end

    local x, y, z = camera:getCameraPosition()
    local dx, dy, dz = localDirectionToWorld(camera.cameraRootNode, 0, 0, -1)

    spec.rayHit = false
    raycastClosest(x, y, z, dx, dy, dz, spec.maxDistance, "onRaycast", self, RAY_MASK)

    -- end of the visible beam: the hit point, or 60 m ahead when nothing was hit
    if spec.hitX ~= nil then
        spec.beamEndX, spec.beamEndY, spec.beamEndZ = spec.hitX, spec.hitY, spec.hitZ
    else
        spec.beamEndX, spec.beamEndY, spec.beamEndZ = x + dx * 60, y + dy * 60, z + dz * 60
    end
end

function SpeedGunHandTool:onRaycast(hitObjectId, hx, hy, hz, distance)
    local spec = getSpec(self)
    if hitObjectId == nil or hitObjectId == 0 then
        return false
    end

    spec.hitX, spec.hitY, spec.hitZ = hx, hy, hz
    spec.targetDistance = distance

    -- The hit shape can be a child of the vehicle component, so walk up until a game object is found.
    local object = nil
    local node = hitObjectId
    for _ = 1, 12 do
        object = g_currentMission:getNodeObject(node)
        if object ~= nil or node == 0 then
            break
        end
        node = getParent(node)
    end

    local hasSpeed = object ~= nil and object.getLastSpeed ~= nil
    spec.debugText = string.format("hit '%s' %.1fm obj=%s", tostring(getName(hitObjectId)), distance or -1, tostring(object ~= nil and (object.typeName or "object") or "nil"))

    if SpeedGunHandTool.DEBUG and spec.lastDebugHit ~= hitObjectId then
        spec.lastDebugHit = hitObjectId
        Logging.info("[SpeedGun] %s hasSpeed=%s", spec.debugText, tostring(hasSpeed))
    end

    if hasSpeed then
        -- attached implements report the speed of their root vehicle
        local vehicle = object.rootVehicle or object
        spec.targetSpeed = math.abs(vehicle:getLastSpeed() or 0)
    end

    return false
end

function SpeedGunHandTool:onDraw()
    local spec = getSpec(self)
    if not spec.isMeasuring or not isLocalOwner(self) then
        return
    end

    self:measure()

    -- visible beam: from the muzzle to the hit point
    if spec.beamEndX ~= nil then
        local sx, sy, sz
        if spec.raycastNode ~= nil and entityExists(spec.raycastNode) then
            sx, sy, sz = getWorldTranslation(spec.raycastNode)
        else
            local camera = g_localPlayer.camera
            sx, sy, sz = camera:getCameraPosition()
            sy = sy - 0.15
        end
        drawDebugLine(sx, sy, sz, 1, 0, 0, spec.beamEndX, spec.beamEndY, spec.beamEndZ, 1, 0.2, 0.2, false)
        if spec.hitX ~= nil then
            drawDebugPoint(spec.hitX, spec.hitY, spec.hitZ, 0, 1, 0, 1, false)
        end
    end

    local text
    if spec.targetSpeed ~= nil then
        text = string.format("%.0f %s", g_i18n:getSpeed(spec.targetSpeed), g_i18n:getSpeedMeasuringUnit())
        if spec.targetDistance ~= nil then
            text = string.format("%s  (%.0f m)", text, spec.targetDistance)
        end
    else
        text = g_i18n:getText("speedgun_no_target")
    end

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(0.1, 1, 0.2, 1)
    renderText(0.5, 0.42, 0.04, text)
    setTextBold(false)

    if SpeedGunHandTool.DEBUG then
        setTextColor(1, 1, 0.3, 1)
        renderText(0.5, 0.38, 0.016, spec.debugText ~= "" and spec.debugText or "no hit")
    end

    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end
