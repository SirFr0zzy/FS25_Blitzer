-- Registers the speedGun hand tool type and its specialization.
-- Runs once when the mod's extra source files are loaded.

local modDirectory = g_currentModDirectory
local modName = g_currentModName

local function registerHandTools()
    local xmlFile = XMLFile.loadIfExists("speedGunHandTools", modDirectory .. "xml/handTools.xml")
    if xmlFile == nil then
        Logging.error("[SpeedGun] xml/handTools.xml not found")
        return
    end

    xmlFile:iterate("handTools.specializations.specialization", function(_, key)
        local name = xmlFile:getString(key .. "#name")
        local className = xmlFile:getString(key .. "#className")
        local filename = xmlFile:getString(key .. "#filename")
        g_handToolSpecializationManager:addSpecialization(name, className, modDirectory .. filename)
    end)

    xmlFile:iterate("handTools.types.type", function(_, key)
        g_handToolTypeManager:loadTypeFromXML(xmlFile.handle, key, false, nil, modName)
    end)

    xmlFile:delete()
end

registerHandTools()
