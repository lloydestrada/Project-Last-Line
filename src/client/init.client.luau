print("Zombie Tower Defense Client Started!")

local Controllers = script.Parent.Controllers
local LobbyController = require(Controllers.LobbyController)

LobbyController.Initialize()