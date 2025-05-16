<div align="center">
<h1>Packet+</h1>
An improved version of Suphi Kaner's <a target="_blank" href="https://devforum.roblox.com/t/3573907">Packet</a> networking library.
</div>
<br>
​<br>
<br>

# What you need to know
When using the library, most things are identical to the original, but there is a key difference in Packet definitions:<br>
You don't have to provide names for your packets, and it is instead required to have a shared packets module.

## Packet:
With shared module:
```lua
local Packet = require(path.to.Packet)

return table.freeze({
	MyPacket = Packet("MyPacket", Packet.String),
	MyCoolPacket = Packet("MyCoolPacket", Packet.Number)
})
```
Or put definitions in every script that uses the packets:
```lua
local Packet = require(path.to.Packet)

local myPacket = Packet("MyPacket", Packet.String)
local myCoolPacket = Packet("MyCoolPacket", Packet.Number)
```

## Packet+:
Shared module only:
```lua
local Packet = require(path.to.Packet)

return table.freeze({
	MyPacket = Packet(Packet.String),
	MyCoolPacket = Packet(Packet.Number)
})
```
