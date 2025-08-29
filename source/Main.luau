--!strict
--!optimize 2

--[[
  _____           _        _         
 |  __ \         | |      | |    _   
 | |__) |_ _  ___| | _____| |_ _| |_ 
 |  ___/ _` |/ __| |/ / _ \ __|_   _|
 | |  | (_| | (__|   <  __/ |_  |_|  
 |_|   \__,_|\___|_|\_\___|\__|      

v1.2.0

An improved version of the Packet networking library.


GitHub: https://github.com/AlexanderLindholt/PacketPlus


--------------------------------------------------------------------------------
MIT License

Copyright (c) 2025 Alexander Lindholt

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--------------------------------------------------------------------------------


Based on Packet by Suphi Kaner, version 1.7.
https://devforum.roblox.com/t/3573907

]]--

-- Services.
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local PlayersService = game:GetService("Players")

-- Requires.
local Signal = CollectionService:GetTagged("Signal")[1]
if not Signal then error("Could not find a signal library.") end
Signal = require(Signal)
if type(Signal) == "table" and Signal.new then Signal = Signal.new end

local Task = require(script.Task)
local Types = require(script.Types)


-- Types.
export type Packet<A... = (), B... = ()> = {
	Id:						number,
	Name:					string,
	Reads:					{() -> any},
	Writes:					{(any) -> ()},
	ResponseTimeout:		number,
	ResponseTimeoutValue:	any,
	ResponseReads:			{() -> any},
	ResponseWrites:			{(any) -> ()},
	OnServerEvent:			Types.Signal<(Player, A...)>,
	OnClientEvent:			Types.Signal<A...>,
	OnServerInvoke:			nil | (player: Player, A...) -> B...,
	OnClientInvoke:			nil | (A...) -> B...,
	Response:				(self: Packet<A..., B...>, B...) -> Packet<A..., B...>,
	Fire:					(self: Packet<A..., B...>, A...) -> B...,
	FireClient:				(self: Packet<A..., B...>, player: Player, A...) -> B...,
	Serialize:				(self: Packet<A..., B...>, A...) -> (buffer, {Instance}?),
	Deserialize:			(self: Packet<A..., B...>, serializeBuffer: buffer, instances: {Instance}?) -> A...,
}


-- Variables.
local reads, writes, import, export, truncate, ended = Types.Reads, Types.Writes, Types.Import, Types.Export, Types.Truncate, Types.Ended
local readU8, writeU8, readU16, writeU16 = reads.NumberU8, writes.NumberU8, reads.NumberU16, writes.NumberU16

local packets = {} :: {[string | number]: Packet<...any, ...any>}
local playerCursors: {[Player]: Types.Cursor}
local playerThreads: {[Player]: {[number]: {Yielded: thread, Timeout: thread}, Index: number}}

local threads: {[number]: {Yielded: thread, Timeout: thread}, Index: number}
local remoteEvent: RemoteEvent

local cursor = {Buffer = buffer.create(128), BufferLength = 128, BufferOffset = 0, Instances = {}, InstancesOffset = 0}

local packetCounter: number = 0


-- Functions.
local function tableToFunctions(parameters: {any})
	if #parameters == 1 then
		local parameter = parameters[1]
		local readFunction, writeFunction
		if type(parameter) == "table" then
			readFunction, writeFunction = tableToFunctions(parameter)
		else
			readFunction, writeFunction = reads[parameter], writes[parameter]
		end
		local read = function()
			local length = readU16()
			local values = table.create(length)
			for index = 1, length do values[index] = readFunction() end
			return values
		end
		local write = function(values: {any})
			writeU16(#values)
			for index, value in values do writeFunction(value) end
		end
		return read, write
	else
		local keys = {} for key, value in parameters do table.insert(keys, key) end table.sort(keys)
		local readFunctions, writeFunctions = table.create(#keys), table.create(#keys)
		for index, key in keys do
			local parameter = parameters[key]
			if type(parameter) == "table" then 
				readFunctions[index], writeFunctions[index] = tableToFunctions(parameter)
			else
				readFunctions[index], writeFunctions[index] = reads[parameter], writes[parameter]
			end
		end
		local read = function()
			local values = {}
			for index, readFunction in readFunctions do values[keys[index]] = readFunction() end
			return values
		end
		local write = function(values: {[any]: any})
			for index, writeFunction in writeFunctions do writeFunction(values[keys[index]]) end
		end
		return read, write
	end
end

local function parametersToFunctions(parameters: {any})
	local readFunctions, writeFunctions = table.create(#parameters), table.create(#parameters)
	for index, parameter in parameters do
		if type(parameter) == "table" then
			readFunctions[index], writeFunctions[index] = tableToFunctions(parameter)
		else
			readFunctions[index], writeFunctions[index] = reads[parameter], writes[parameter]
		end
	end
	return readFunctions, writeFunctions
end

local function readParameters(reads: {() -> any})
	local values = table.create(#reads)
	for index, func in reads do values[index] = func() end
	return table.unpack(values)
end

local function writeParameters(writes: {(any) -> ()}, values: {any})
	for index, func in writes do func(values[index]) end
end

local function timeout(threads: {[number]: {Yielded: thread, Timeout: thread}, Index: number}, threadIndex: number, value: any)
	local responseThreads = threads[threadIndex]
	task.defer(responseThreads.Yielded, value)
	threads[threadIndex] = nil
end


-- Packet.
local Packet = {} :: Packet<...any, ...any>
Packet.__index = Packet

Packet.Response = function(packet, ...)
	packet.ResponseTimeout = packet.ResponseTimeout or 10
	packet.ResponseReads, packet.ResponseWrites = parametersToFunctions(table.pack(...))
	return packet
end

Packet.Fire = function(packet, ...)
	if packet.ResponseReads then
		if RunService:IsServer() then error("You must use FireClient(player)", 2) end
		local responseThread
		for _ = 1, 128, 1 do
			responseThread = threads[threads.Index]
			if responseThread then threads.Index = (threads.Index + 1)%128 else break end
		end
		if responseThread then error("Cannot have more than 128 yielded threads", 2) end
		import(cursor)
		writeU8(packet.Id)
		writeU8(threads.Index)
		threads[threads.Index] = {Yielded = coroutine.running(), Timeout = Task.Delay(packet.ResponseTimeout, timeout, threads, threads.Index, packet.ResponseTimeoutValue)}
		threads.Index = (threads.Index + 1)%128
		writeParameters(packet.Writes, {...})
		cursor = export()
		return coroutine.yield()
	else
		import(cursor)
		writeU8(packet.Id)
		writeParameters(packet.Writes, {...})
		cursor = export()
	end
end

Packet.FireClient = function(packet, player, ...)
	if not player.Parent then return end
	if packet.ResponseReads then
		local threads = playerThreads[player]
		if not threads then threads = {Index = 0} playerThreads[player] = threads end
		local responseThread
		for i = 1, 128 do
			responseThread = threads[threads.Index]
			if responseThread then threads.Index = (threads.Index + 1) % 128 else break end
		end
		if responseThread then error("Cannot have more than 128 yielded threads", 2) return end
		import(playerCursors[player] or {Buffer = buffer.create(128), BufferLength = 128, BufferOffset = 0, Instances = {}, InstancesOffset = 0})
		writeU8(packet.Id)
		writeU8(threads.Index)
		threads[threads.Index] = {Yielded = coroutine.running(), Timeout = Task.Delay(packet.ResponseTimeout, timeout, threads, threads.Index, packet.ResponseTimeoutValue)}
		threads.Index = (threads.Index + 1) % 128
		writeParameters(packet.Writes, {...})
		playerCursors[player] = export()
		return coroutine.yield()
	else
		import(playerCursors[player] or {Buffer = buffer.create(128), BufferLength = 128, BufferOffset = 0, Instances = {}, InstancesOffset = 0})
		writeU8(packet.Id)
		writeParameters(packet.Writes, {...})
		playerCursors[player] = export()
	end
end

Packet.Serialize = function(packet, ...)
	import({Buffer = buffer.create(128), BufferLength = 128, BufferOffset = 0, Instances = {}, InstancesOffset = 0})
	writeParameters(packet.Writes, {...})
	return truncate()
end

Packet.Deserialize = function(packet, serializeBuffer, instances)
	import({Buffer = serializeBuffer, BufferLength = buffer.len(serializeBuffer), BufferOffset = 0, Instances = instances or {}, InstancesOffset = 0})
	return readParameters(packet.Reads)
end


-- Initialize.
if RunService:IsServer() then
	playerCursors = {}
	playerThreads = {}
	remoteEvent = Instance.new("RemoteEvent", script)
	
	local playerBytes = {}
	
	local thread = task.spawn(function()
		while true do
			coroutine.yield()
			if cursor.BufferOffset > 0 then
				local truncatedBuffer = buffer.create(cursor.BufferOffset)
				buffer.copy(truncatedBuffer, 0, cursor.Buffer, 0, cursor.BufferOffset)
				if cursor.InstancesOffset == 0 then
					remoteEvent:FireAllClients(truncatedBuffer)
				else
					remoteEvent:FireAllClients(truncatedBuffer, cursor.Instances)
					cursor.InstancesOffset = 0
					table.clear(cursor.Instances)
				end
				cursor.BufferOffset = 0
			end
			for player, cursor in playerCursors do
				local truncatedBuffer = buffer.create(cursor.BufferOffset)
				buffer.copy(truncatedBuffer, 0, cursor.Buffer, 0, cursor.BufferOffset)
				if cursor.InstancesOffset == 0 then
					remoteEvent:FireClient(player, truncatedBuffer)
				else
					remoteEvent:FireClient(player, truncatedBuffer, cursor.Instances)
				end
			end
			table.clear(playerCursors)
			table.clear(playerBytes)
		end
	end)
	
	local respond = function(packet: Packet, player: Player, threadIndex: number, ...)
		if not packet.OnServerInvoke then if RunService:IsStudio() then warn("\nOnServerInvoke not found for packet "..packet.Id..".\nDiscarding event:\n", ...) end return end
		local values = {packet.OnServerInvoke(player, ...)}
		if not player.Parent then return end
		import(playerCursors[player] or {Buffer = buffer.create(128), BufferLength = 128, BufferOffset = 0, Instances = {}, InstancesOffset = 0})
		writeU8(packet.Id)
		writeU8(threadIndex + 128)
		writeParameters(packet.ResponseWrites, values)
		playerCursors[player] = export()
	end
	
	remoteEvent.OnServerEvent:Connect(function(player: Player, receivedBuffer: buffer, instances: {Instance}?)
		local bytes = (playerBytes[player] or 0) + math.max(buffer.len(receivedBuffer), 800)
		if bytes > 8_000 then if RunService:IsStudio() then error(player.Name.." is exceeding the data/rate limit.") end return end
		playerBytes[player] = bytes
		import({Buffer = receivedBuffer, BufferLength = buffer.len(receivedBuffer), BufferOffset = 0, Instances = instances or {}, InstancesOffset = 0})
		while ended() == false do
			local packet = packets[readU8()]
			if packet.ResponseReads then
				local threadIndex = readU8()
				if threadIndex < 128 then
					Task.Defer(respond, packet, player, threadIndex, readParameters(packet.Reads))
				else
					threadIndex -= 128
					local responseThreads = playerThreads[player][threadIndex]
					if responseThreads then
						task.cancel(responseThreads.Timeout)
						task.defer(responseThreads.Yielded, readParameters(packet.ResponseReads))
						playerThreads[player][threadIndex] = nil
					elseif RunService:IsStudio() then
						warn("\nResponse thread not found for packet "..packet.Id..".\nDiscarding response:\n"..readParameters(packet.ResponseReads))
						return
					else
						readParameters(packet.ResponseReads)
					end
				end
			else
				packet.OnServerEvent:Fire(player, readParameters(packet.Reads))
			end
		end
	end)
	
	PlayersService.PlayerRemoving:Connect(function(player)
		playerCursors[player] = nil
		playerThreads[player] = nil
		playerBytes[player] = nil
	end)
	
	RunService.Heartbeat:Connect(function(deltaTime) task.defer(thread) end)
else
	threads = {Index = 0}
	remoteEvent = script:WaitForChild("RemoteEvent", 5)
	if not remoteEvent then error("Server has not initalized.") end
	local totalTime = 0
	
	local thread = task.spawn(function()
		while true do
			coroutine.yield()
			if cursor.BufferOffset > 0 then
				local truncatedBuffer = buffer.create(cursor.BufferOffset)
				buffer.copy(truncatedBuffer, 0, cursor.Buffer, 0, cursor.BufferOffset)
				if cursor.InstancesOffset == 0 then
					remoteEvent:FireServer(truncatedBuffer)
				else
					remoteEvent:FireServer(truncatedBuffer, cursor.Instances)
					cursor.InstancesOffset = 0
					table.clear(cursor.Instances)
				end
				cursor.BufferOffset = 0
			end
		end
	end)
	
	local respond = function(packet: Packet, threadIndex: number, ...)
		if not packet.OnClientInvoke then warn("\nOnClientInvoke not found for packet: "..packet.Id..".\nDiscarding event:\n", ...) return end
		local values = {packet.OnClientInvoke(...)}
		import(cursor)
		writeU8(packet.Id)
		writeU8(threadIndex + 128)
		writeParameters(packet.ResponseWrites, values)
		cursor = export()
	end
	
	remoteEvent.OnClientEvent:Connect(function(receivedBuffer: buffer, instances: {Instance}?)
		import({Buffer = receivedBuffer, BufferLength = buffer.len(receivedBuffer), BufferOffset = 0, Instances = instances or {}, InstancesOffset = 0})
		while ended() == false do
			local packet = packets[readU8()]
			if packet.ResponseReads then
				local threadIndex = readU8()
				if threadIndex < 128 then
					Task.Defer(respond, packet, threadIndex, readParameters(packet.Reads))
				else
					threadIndex -= 128
					local responseThreads = threads[threadIndex]
					if responseThreads then
						task.cancel(responseThreads.Timeout)
						task.defer(responseThreads.Yielded, readParameters(packet.ResponseReads))
						threads[threadIndex] = nil
					else
						warn("\nResponse thread not found for packet: "..packet.Id.."\nDiscarding response:\n", readParameters(packet.ResponseReads))
						return
					end
				end
			else
				packet.OnClientEvent:Fire(readParameters(packet.Reads))
			end
		end
	end)
	
	RunService.Heartbeat:Connect(function(deltaTime)
		totalTime += deltaTime
		if totalTime > 0.016666666666666666 then
			totalTime %= 0.016666666666666666
			task.defer(thread)
		end
	end)
end


return setmetatable(Types.DataTypes, {
	__call = function<A..., B...>(_, ...: A...)
		local packet = (setmetatable({}, Packet) :: any) :: Packet<A..., B...>
		if RunService:IsServer() then
			packet.OnServerEvent = Signal() :: Types.Signal<(Player, A...)>
		else
			packet.OnClientEvent = Signal() :: Types.Signal<A...>
		end
		packet.Id = packetCounter
		packets[packetCounter] = packet
		packetCounter += 1
		packet.Reads, packet.Writes = parametersToFunctions(table.pack(...))
		return packet
	end
})