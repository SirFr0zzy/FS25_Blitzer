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

function BlitzerFlashEvent.new(placeable)
    local self = BlitzerFlashEvent.emptyNew()
    self.placeable = placeable
    return self
end

function BlitzerFlashEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

function BlitzerFlashEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
end

function BlitzerFlashEvent:run(connection)
    if self.placeable ~= nil and self.placeable.onBlitzerFlash ~= nil then
        self.placeable:onBlitzerFlash()
    end
end

---------------------------------------------------------------------------
-- Admin log: client asks, server answers (admins only)

BlitzerRequestLogEvent = {}
local BlitzerRequestLogEvent_mt = Class(BlitzerRequestLogEvent, Event)
InitEventClass(BlitzerRequestLogEvent, "BlitzerRequestLogEvent")

function BlitzerRequestLogEvent.emptyNew()
    return Event.new(BlitzerRequestLogEvent_mt)
end

function BlitzerRequestLogEvent.new()
    return BlitzerRequestLogEvent.emptyNew()
end

function BlitzerRequestLogEvent:readStream(streamId, connection)
    self:run(connection)
end

function BlitzerRequestLogEvent:writeStream(streamId, connection)
end

function BlitzerRequestLogEvent:run(connection)
    if g_server ~= nil and not connection:getIsServer() and BlitzerManager.isConnectionAdmin(connection) then
        connection:sendEvent(BlitzerLogEvent.new(BlitzerManager.log))
    end
end

BlitzerLogEvent = {}
local BlitzerLogEvent_mt = Class(BlitzerLogEvent, Event)
InitEventClass(BlitzerLogEvent, "BlitzerLogEvent")

function BlitzerLogEvent.emptyNew()
    return Event.new(BlitzerLogEvent_mt)
end

function BlitzerLogEvent.new(log)
    local self = BlitzerLogEvent.emptyNew()
    self.log = log
    return self
end

function BlitzerLogEvent:writeStream(streamId, connection)
    local count = math.min(#self.log, 65000)
    streamWriteUInt16(streamId, count)
    for i = 1, count do
        local e = self.log[i]
        streamWriteInt32(streamId, e.x)
        streamWriteInt32(streamId, e.z)
        streamWriteString(streamId, e.plate)
        streamWriteUInt16(streamId, e.speed)
        streamWriteUInt8(streamId, e.limit)
        streamWriteUInt32(streamId, e.day)
        streamWriteUInt8(streamId, e.hour)
        streamWriteUInt8(streamId, e.minute)
    end
end

function BlitzerLogEvent:readStream(streamId, connection)
    local log = {}
    local count = streamReadUInt16(streamId)
    for i = 1, count do
        local e = {}
        e.x = streamReadInt32(streamId)
        e.z = streamReadInt32(streamId)
        e.plate = streamReadString(streamId)
        e.speed = streamReadUInt16(streamId)
        e.limit = streamReadUInt8(streamId)
        e.day = streamReadUInt32(streamId)
        e.hour = streamReadUInt8(streamId)
        e.minute = streamReadUInt8(streamId)
        log[i] = e
    end
    self.log = log
    self:run(connection)
end

function BlitzerLogEvent:run(connection)
    BlitzerManager.setLog(self.log)
end
