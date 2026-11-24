print("Zombie Tower Defense Server Started!")

local Services = script.Parent.Services

local LobbyBuilder = require(Services.LobbyBuilder)
local WaveService = require(Services.WaveService)
local MatchService = require(Services.MatchService)

LobbyBuilder.Build()
MatchService.Initialize()
WaveService.Initialize()