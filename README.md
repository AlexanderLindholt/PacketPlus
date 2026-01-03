<div align="center">
<h1>Packet+</h1>
An improved version of the <a target="_blank" href="https://devforum.roblox.com/t/3573907">Packet</a> networking library.
</div>
<br>
​<br>
<br>

# ✨ It’s just better!
This modified version of Packet offers simplified packet definitions and packet safety (early packets are still received). Additionally, it brings minor improvements regarding error messages and optimization.

<br>

# 🛠️ Setup and use it!
First and foremost, [learn the original Packet library](https://www.youtube.com/watch?v=WoIElUdj64A&ab_channel=SuphiKaner).

<br>

Then, for Packet+, you need to setup a signal library.<br>
<a target="_blank" href="https://github.com/AlexanderLindholt/SignalPlus">Signal+</a> is recommended because it’s the best.<br>
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
Packet+ removes the name parameter, requiring packets to be defined in a shared module. The packet name is inferred from the table key, reducing repetition and keeping definitions centralized and efficient.
