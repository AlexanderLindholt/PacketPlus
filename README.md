<div align="center">
<h1>Packet+</h1>
An improved version of the <a target="_blank" href="https://devforum.roblox.com/t/3573907">Packet</a> networking library.
</div>
<br>
​<br>
<br>

# ✨ It’s just better!
This modified version of Packet offers simplified packet definitions and minor optimizations.<br>
Additionally, it brings QoL changes, such as additional and improved error messages.

<br>

# 🛠️ Setup and use it!
First and foremost, [learn the original Packet library](https://www.youtube.com/watch?v=WoIElUdj64A&ab_channel=SuphiKaner).

<br>

Then, for Packet+, you need to setup a signal library.<br>
<a target="_blank" href="https://github.com/AlexanderLindholt/SignalPlus">Signal+</a> is recommended for performance.<br>
Make sure to tag the module `Signal`.

<br>

The API is mostly identical to the original library, but there is a key difference, seen below:

## ❌ Packet:
Use a shared module:
```lua
local Packet = require(path.to.Packet)

return {
	MyPacket = Packet("MyPacket", Packet.String),
	MyCoolPacket = Packet("MyCoolPacket", Packet.Number)
}
```
Or put definitions in every script that uses the packets:
```lua
local Packet = require(path.to.Packet)

local myPacket = Packet("MyPacket", Packet.String)
local myCoolPacket = Packet("MyCoolPacket", Packet.Number)
```

## ✅ Packet+:
Use a shared module:
```lua
local Packet = require(path.to.Packet)

return {
	MyPacket = Packet(Packet.String),
	MyCoolPacket = Packet(Packet.Number)
}
```
No support for putting definitions in every script, because that’s ugly anyways!
