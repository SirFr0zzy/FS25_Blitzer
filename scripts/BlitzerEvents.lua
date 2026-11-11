-- Network events for the stationary Blitzer.
--  BlitzerSetLimitEvent: client -> server (set speed limit), server -> all clients (broadcast)
--  BlitzerFlashEvent:    server -> all clients (flash + notify the driver)

BlitzerSetLimitEvent = {}
local BlitzerSetLimitEvent_mt = Class(BlitzerSetLimitEvent, Event)
InitEventClass(BlitzerSetLimitEvent, "BlitzerSetLimitEvent")

function BlitzerSetLimitEvent.emptyNew()
    return Event.new(BlitzerSetLimitEvent_mt)
end

function BlitzerSetLimitEvent.new(placeable, limit)
    local self = BlitzerSetLimitEvent.emptyNew()
    self.placeable = placeable
    self.limit = limit
    return self
end

function BlitzerSetLimitEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.limit = streamReadUInt8(streamId)
    self:run(connection)
end

function BlitzerSetLimitEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUInt8(streamId, self.limit)
end

function BlitzerSetLimitEvent:run(connection)
    if not connection:getIsServer() then
        g_server:broadcastEvent(self, false, connection, self.placeable)
    end
    if self.placeable ~= nil and self.placeable.setBlitzerLimit ~= nil then
        self.placeable:setBlitzerLimit(self.limit, true)
    end
end

function BlitzerSetLimitEvent.sendEvent(placeable, limit, noEventSend)
    if noEventSend == nil or noEventSend == false then
        if g_server ~= nil then
            g_server:broadcastEvent(BlitzerSetLimitEvent.new(placeable, limit), nil, nil, placeable)
        else
            g_client:getServerConnection():sendEvent(BlitzerSetLimitEvent.new(placeable, limit))
        end
    end
end

---------------------------------------------------------------------------

BlitzerFlashEvent = {}
local BlitzerFlashEvent_mt = Class(BlitzerFlashEvent, Event)
InitEventClass(BlitzerFlashEvent, "BlitzerFlashEvent")

function BlitzerFlashEvent.emptyNew()
    return Event.new(BlitzerFlashEvent_mt)
end

function BlitzerFlashEvent.new(placeable, vehicle, speed)
    local self = BlitzerFlashEvent.emptyNew()
    self.placeable = placeable
    self.vehicle = vehicle
    self.speed = speed
    return self
end

function BlitzerFlashEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.speed = streamReadUInt16(streamId)
    self:run(connection)
end

function BlitzerFlashEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteUInt16(streamId, self.speed)
end

function BlitzerFlashEvent:run(connection)
    if self.placeable ~= nil and self.placeable.onBlitzerFlash ~= nil then
        self.placeable:onBlitzerFlash(self.vehicle, self.speed)
    end
end
