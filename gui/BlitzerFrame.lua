-- ESC menu page for admins: tab 1 = all Blitzer columns, tab 2 = all flashes.

BlitzerFrame = {}
local BlitzerFrame_mt = Class(BlitzerFrame, TabbedMenuFrameElement)

BlitzerFrame.TAB_BLITZER = 1
BlitzerFrame.TAB_LOG = 2
BlitzerFrame.TAB_NAMES = { "blitzer_tab_blitzers", "blitzer_tab_flashes" }
BlitzerFrame.NUM_TABS = 2

function BlitzerFrame.new(target)
    local self = TabbedMenuFrameElement.new(target, BlitzerFrame_mt)
    self.currentTab = BlitzerFrame.TAB_BLITZER
    self.subCategoryTabs = {}
    self.blitzerRows = {}
    self.logRows = {}
    self.selectedBlitzer = nil
    self.selectedLog = nil
    self.mapButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        text = g_i18n:getText("blitzer_show_on_map"),
        callback = function() self:onClickShowOnMap() end,
        disabled = true,
    }
    self:setMenuButtonInfo({ { inputAction = InputAction.MENU_BACK }, self.mapButtonInfo })
    return self
end

function BlitzerFrame:onGuiSetupFinished()
    BlitzerFrame:superClass().onGuiSetupFinished(self)
    for _, list in ipairs({ self.blitzerTable, self.logTable }) do
        if list ~= nil then
            list:setDataSource(self)
            list:setDelegate(self)
            list.onSelectionChanged = function(l, section, index) self:onListSelectionChanged(l, section, index) end
        end
    end
end

function BlitzerFrame:initialize()
    self.selectorPrefab:unlinkElement()
    FocusManager:removeElement(self.selectorPrefab)
    for i = 1, BlitzerFrame.NUM_TABS do
        self.subCategoryPaging:addText(tostring(i))
        local tab = self.selectorPrefab:clone(self.subCategoryBox)
        self.subCategoryTabs[i] = tab
        FocusManager:loadElementFromCustomValues(tab)
        tab:setText(g_i18n:getText(BlitzerFrame.TAB_NAMES[i]))
        tab:getDescendantByName("background"):setSize(tab.size[1], tab.size[2])
        tab.onClickCallback = function() self:switchTab(i) end
    end
    self.subCategoryBox:invalidateLayout()
    self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)
end

function BlitzerFrame:onFrameOpen()
    BlitzerFrame:superClass().onFrameOpen(self)
    BlitzerManager.requestLog()
    self:collectData()
    self:switchTab(self.currentTab)
end

function BlitzerFrame:onFrameClose()
    BlitzerFrame:superClass().onFrameClose(self)
    self.blitzerRows = {}
    self.logRows = {}
end

function BlitzerFrame:onListSelectionChanged(list, section, index)
    if list == self.logTable then
        self.selectedLog = self.logRows[index]
        self:updatePhoto()
    else
        self.selectedBlitzer = self.blitzerRows[index]
    end
    self:updateButtons()
end

function BlitzerFrame:updateButtons()
    local row = self.selectedBlitzer
    self.mapButtonInfo.disabled = self.currentTab ~= BlitzerFrame.TAB_BLITZER or row == nil
    if row ~= nil and BlitzerManager.isMarked(row.x, row.z) then
        self.mapButtonInfo.text = g_i18n:getText("blitzer_hide_on_map")
    else
        self.mapButtonInfo.text = g_i18n:getText("blitzer_show_on_map")
    end
    self:setMenuButtonInfoDirty()
end

function BlitzerFrame:onClickShowOnMap()
    local row = self.selectedBlitzer
    if row == nil then
        return
    end
    BlitzerManager.toggleMapMarker(row.x, row.z)
    self:updateButtons()
end

-- "photo card" next to the flash list: store picture of the flashed vehicle plus its data
function BlitzerFrame:updatePhoto()
    local e = self.selectedLog
    local show = self.currentTab == BlitzerFrame.TAB_LOG and e ~= nil
    for _, id in ipairs({ "photoTitle", "photoVehicle", "photoPlate", "photoSpeed", "photoPlace", "photoTime" }) do
        if self[id] ~= nil then self[id]:setVisible(show) end
    end
    local imageFilename = nil
    if show then
        local item = e.xmlFilename ~= "" and g_storeManager:getItemByXMLFilename(e.xmlFilename) or nil
        imageFilename = item ~= nil and item.imageFilename or nil
        self.photoVehicle:setText(e.vehicleName ~= "" and e.vehicleName or "?")
        self.photoPlate:setText(e.plate)
        self.photoSpeed:setText(string.format("%d %s  (%s %d)", g_i18n:getSpeed(e.speed), g_i18n:getSpeedMeasuringUnit(),
            g_i18n:getText("blitzer_limit_short"), g_i18n:getSpeed(e.limit)))
        self.photoPlace:setText(string.format("X %d  Z %d", e.x, e.z))
        self.photoTime:setText(string.format("%s %d, %02d:%02d", g_i18n:getText("blitzer_day"), e.day, e.hour, e.minute))
    end
    if self.photoImage ~= nil then
        if imageFilename ~= nil then
            self.photoImage:setImageFilename(imageFilename)
        end
        self.photoImage:setVisible(imageFilename ~= nil)
    end
end

function BlitzerFrame:onClickTab(state)
    self:switchTab(state)
end

local function posKey(x, z)
    return string.format("%d|%d", x, z)
end

local function posText(x, z)
    return string.format("X %d  Z %d", x, z)
end

function BlitzerFrame:collectData()
    -- count flashes per column (matched by rounded position)
    local counts = {}
    for _, e in ipairs(BlitzerManager.log) do
        local k = posKey(e.x, e.z)
        counts[k] = (counts[k] or 0) + 1
    end

    local rows = {}
    for _, placeable in ipairs(BlitzerManager.placeables) do
        if placeable.rootNode ~= nil and placeable.spec_blitzer ~= nil then
            local x, _, z = getWorldTranslation(placeable.rootNode)
            x, z = math.floor(x + 0.5), math.floor(z + 0.5)
            local spec = placeable.spec_blitzer
            table.insert(rows, { x = x, z = z, limit = spec.speedLimit, range = spec.range, angle = spec.angle, count = counts[posKey(x, z)] or 0 })
        end
    end
    table.sort(rows, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.z < b.z
    end)
    self.blitzerRows = rows

    -- newest flash first
    local log = {}
    for i = #BlitzerManager.log, 1, -1 do
        table.insert(log, BlitzerManager.log[i])
    end
    self.logRows = log
end

function BlitzerFrame:onLogChanged()
    -- called when the server answered / a new flash was logged while the page is open
    if self.currentTab == nil or not self:getIsVisible() then
        return
    end
    self:collectData()
    self:reloadLists()
end

function BlitzerFrame:reloadLists()
    if self.blitzerTable ~= nil then self.blitzerTable:reloadData() end
    if self.logTable ~= nil then self.logTable:reloadData() end
    if self.blitzerEmptyText ~= nil then self.blitzerEmptyText:setVisible(#self.blitzerRows == 0) end
    if self.logEmptyText ~= nil then self.logEmptyText:setVisible(#self.logRows == 0) end
end

function BlitzerFrame:switchTab(tabIndex)
    self.currentTab = tabIndex
    if self.tabContainer1 ~= nil then self.tabContainer1:setVisible(tabIndex == 1) end
    if self.tabContainer2 ~= nil then self.tabContainer2:setVisible(tabIndex == 2) end
    for i = 1, BlitzerFrame.NUM_TABS do
        if self.subCategoryTabs[i] ~= nil then
            self.subCategoryTabs[i]:setSelected(i == tabIndex)
        end
    end
    self:reloadLists()
    self:updatePhoto()
    self:updateButtons()
    local list = tabIndex == 1 and self.blitzerTable or self.logTable
    if list ~= nil then
        FocusManager:setFocus(list)
    end
end

function BlitzerFrame:getNumberOfItemsInSection(list, section)
    if list == self.logTable then
        return #self.logRows
    end
    return #self.blitzerRows
end

local function formatTime(e)
    return string.format("%s %d, %02d:%02d", g_i18n:getText("blitzer_day"), e.day, e.hour, e.minute)
end

function BlitzerFrame:populateCellForItemInSection(list, section, index, cell)
    if list == self.logTable then
        local e = self.logRows[index]
        if e == nil then return end
        cell:getAttribute("colBlitzer"):setText(posText(e.x, e.z))
        cell:getAttribute("colVehicle"):setText(e.vehicleName ~= "" and e.vehicleName or "?")
        cell:getAttribute("colSpeed"):setText(string.format("%d %s  (%s %d)",
            g_i18n:getSpeed(e.speed), g_i18n:getSpeedMeasuringUnit(), g_i18n:getText("blitzer_limit_short"), g_i18n:getSpeed(e.limit)))
        cell:getAttribute("colPlate"):setText(e.plate)
        cell:getAttribute("colTime"):setText(formatTime(e))
    else
        local r = self.blitzerRows[index]
        if r == nil then return end
        cell:getAttribute("colNr"):setText(tostring(index))
        cell:getAttribute("colPosition"):setText(posText(r.x, r.z))
        cell:getAttribute("colLimit"):setText(string.format("%d %s", g_i18n:getSpeed(r.limit), g_i18n:getSpeedMeasuringUnit()))
        cell:getAttribute("colArea"):setText(string.format("%d m / %d°", r.range or 0, r.angle or 0))
        cell:getAttribute("colCount"):setText(tostring(r.count))
    end
end
