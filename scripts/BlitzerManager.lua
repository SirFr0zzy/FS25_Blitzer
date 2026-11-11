-- Global bookkeeping for the Blitzer mod:
--  * registry of all placed Blitzer columns (every machine)
--  * flash log (server writes it, admins get it on request; saved with the savegame)
--  * the admin tab in the ESC menu

local modDirectory = g_currentModDirectory

source(Utils.getFilename("scripts/BlitzerEvents.lua", modDirectory))
source(Utils.getFilename("gui/BlitzerFrame.lua", modDirectory))

BlitzerManager = {}
BlitzerManager.dir = modDirectory
BlitzerManager.placeables = {}
BlitzerManager.log = {}        -- newest entry LAST
BlitzerManager.MAX_LOG = 500
BlitzerManager.LOG_FILE = "blitzerLog.xml"

---------------------------------------------------------------------------
-- Registry
---------------------------------------------------------------------------

function BlitzerManager.registerPlaceable(placeable)
    for _, p in ipairs(BlitzerManager.placeables) do
        if p == placeable then
            return
        end
    end
    table.insert(BlitzerManager.placeables, placeable)
end

function BlitzerManager.unregisterPlaceable(placeable)
    for i, p in ipairs(BlitzerManager.placeables) do
        if p == placeable then
            table.remove(BlitzerManager.placeables, i)
            return
        end
    end
end

---------------------------------------------------------------------------
-- Admin handling
---------------------------------------------------------------------------

function BlitzerManager.getIsAdmin()
    local mission = g_currentMission
    if mission == nil then
        return false
    end
    if mission.isMasterUser then
        return true
    end
    -- single player / local host
    return g_server ~= nil and (mission.missionDynamicInfo == nil or not mission.missionDynamicInfo.isMultiplayer)
end

-- server side: is this client connection an admin?
function BlitzerManager.isConnectionAdmin(connection)
    local ok, result = pcall(function()
        local user = g_currentMission.userManager:getUserByConnection(connection)
        return user ~= nil and user:getIsMasterUser()
    end)
    return ok and result == true
end

---------------------------------------------------------------------------
-- Log
---------------------------------------------------------------------------

local function getPlate(vehicle)
    local spec = vehicle.spec_licensePlates
    if spec ~= nil and spec.licensePlateData ~= nil and spec.licensePlateData.characters ~= nil then
        local text = table.concat(spec.licensePlateData.characters)
        if text ~= "" then
            return text
        end
    end
    if vehicle.getName ~= nil then
        return "- (" .. tostring(vehicle:getName()) .. ")"
    end
    return "-"
end

-- server only
function BlitzerManager.addEntry(placeable, vehicle, speed)
    local env = g_currentMission.environment
    local x, _, z = getWorldTranslation(placeable.rootNode)
    local entry = {
        x = math.floor(x + 0.5),
        z = math.floor(z + 0.5),
        plate = string.sub(getPlate(vehicle), 1, 40),
        speed = math.min(speed, 65000),
        limit = placeable.spec_blitzer.speedLimit,
        day = env.currentMonotonicDay or env.currentDay or 0,
        hour = env.currentHour or 0,
        minute = env.currentMinute or 0,
    }
    table.insert(BlitzerManager.log, entry)
    while #BlitzerManager.log > BlitzerManager.MAX_LOG do
        table.remove(BlitzerManager.log, 1)
    end
    if BlitzerManager.frame ~= nil then
        BlitzerManager.frame:onLogChanged()
    end
end

function BlitzerManager.setLog(log)
    BlitzerManager.log = log
    if BlitzerManager.frame ~= nil then
        BlitzerManager.frame:onLogChanged()
    end
end

function BlitzerManager.requestLog()
    if g_server == nil and g_client ~= nil then
        g_client:getServerConnection():sendEvent(BlitzerRequestLogEvent.new())
    end
end

local function getSavePath()
    local info = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if info == nil or info.savegameDirectory == nil then
        return nil
    end
    return info.savegameDirectory .. "/" .. BlitzerManager.LOG_FILE
end

function BlitzerManager.saveLog()
    local path = getSavePath()
    if path == nil or g_server == nil then
        return
    end
    local xml = createXMLFile("blitzerLog", path, "blitzerLog")
    if xml == nil or xml == 0 then
        return
    end
    for i, e in ipairs(BlitzerManager.log) do
        local key = string.format("blitzerLog.entry(%d)", i - 1)
        setXMLInt(xml, key .. "#x", e.x)
        setXMLInt(xml, key .. "#z", e.z)
        setXMLString(xml, key .. "#plate", e.plate)
        setXMLInt(xml, key .. "#speed", e.speed)
        setXMLInt(xml, key .. "#limit", e.limit)
        setXMLInt(xml, key .. "#day", e.day)
        setXMLInt(xml, key .. "#hour", e.hour)
        setXMLInt(xml, key .. "#minute", e.minute)
    end
    saveXMLFile(xml)
    delete(xml)
end

function BlitzerManager.loadLog()
    BlitzerManager.log = {}
    local path = getSavePath()
    if path == nil or g_server == nil or not fileExists(path) then
        return
    end
    local xml = loadXMLFile("blitzerLog", path)
    if xml == nil or xml == 0 then
        return
    end
    local i = 0
    while true do
        local key = string.format("blitzerLog.entry(%d)", i)
        if not hasXMLProperty(xml, key) then
            break
        end
        table.insert(BlitzerManager.log, {
            x = getXMLInt(xml, key .. "#x") or 0,
            z = getXMLInt(xml, key .. "#z") or 0,
            plate = getXMLString(xml, key .. "#plate") or "-",
            speed = getXMLInt(xml, key .. "#speed") or 0,
            limit = getXMLInt(xml, key .. "#limit") or 0,
            day = getXMLInt(xml, key .. "#day") or 0,
            hour = getXMLInt(xml, key .. "#hour") or 0,
            minute = getXMLInt(xml, key .. "#minute") or 0,
        })
        i = i + 1
    end
    delete(xml)
end

---------------------------------------------------------------------------
-- ESC menu page
---------------------------------------------------------------------------

local function moveToPosition(list, matchFn, insertPos)
    for i = 1, #list do
        if matchFn(list[i]) then
            local item = table.remove(list, i)
            table.insert(list, insertPos, item)
            break
        end
    end
end

function BlitzerManager.addMenuPage(frame, pageName, predicate)
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    inGameMenu.controlIDs[pageName] = nil

    local insertPos = 2
    for i = 1, #inGameMenu.pagingElement.elements do
        if inGameMenu.pagingElement.elements[i] == inGameMenu["pageStatistics"] then
            insertPos = i
            break
        end
    end

    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(inGameMenu[pageName])
    inGameMenu:exposeControlsAsFields(pageName)

    moveToPosition(inGameMenu.pagingElement.elements, function(e) return e == inGameMenu[pageName] end, insertPos)
    moveToPosition(inGameMenu.pagingElement.pages, function(p) return p.element == inGameMenu[pageName] end, insertPos)

    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()
    inGameMenu:registerPage(inGameMenu[pageName], insertPos, predicate)

    local iconFilename = Utils.getFilename("gui/menuIcon.dds", modDirectory)
    inGameMenu:addPageTab(inGameMenu[pageName], iconFilename, GuiUtils.getUVs({0, 0, 256, 256}))

    moveToPosition(inGameMenu.pageFrames, function(f) return f == inGameMenu[pageName] end, insertPos)
    inGameMenu:rebuildTabList()
end

function BlitzerManager:loadMap()
    BlitzerManager.loadLog()

    g_gui:loadProfiles(modDirectory .. "gui/guiProfiles.xml")
    BlitzerManager.frame = BlitzerFrame.new()
    g_gui:loadGui(modDirectory .. "gui/BlitzerFrame.xml", "blitzerAdminFrame", BlitzerManager.frame, true)
    BlitzerManager.addMenuPage(BlitzerManager.frame, "blitzerAdminFrame", BlitzerManager.getIsAdmin)
    BlitzerManager.frame:initialize()

    if g_server ~= nil and not BlitzerManager.saveHooked then
        BlitzerManager.saveHooked = true
        ItemSystem.save = Utils.prependedFunction(ItemSystem.save, function()
            if g_currentMission ~= nil then
                BlitzerManager.saveLog()
            end
        end)
    end
end

function BlitzerManager:draw()
    for _, placeable in ipairs(BlitzerManager.placeables) do
        PlaceableBlitzer.drawRange(placeable)
    end
end

function BlitzerManager:deleteMap()
    BlitzerManager.frame = nil
    BlitzerManager.placeables = {}
    BlitzerManager.log = {}
end

addModEventListener(BlitzerManager)
