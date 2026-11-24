local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchState = require(
    ReplicatedStorage.Modules.MatchState
)

local MatchConfig = require(
    ReplicatedStorage.Config.MatchConfig
)

local MatchService = {}

local currentState = MatchState.WAITING
local activePlayers = {}

local function countPlayers()
    local count = 0

    for _ in pairs(activePlayers) do
        count += 1
    end

    return count
end

local function updatePlayerList()
    print("Current Players:", countPlayers())
end

local function addPlayer(player)
    if activePlayers[player.UserId] then
        return
    end

    if countPlayers() >= MatchConfig.MAX_PLAYERS then
        warn(player.Name .. " cannot join. Match is full.")
        return
    end

    activePlayers[player.UserId] = player

    print(player.Name .. " joined the match!")

    updatePlayerList()
end

local function removePlayer(player)
    if not activePlayers[player.UserId] then
        return
    end

    activePlayers[player.UserId] = nil

    print(player.Name .. " left the match!")

    updatePlayerList()
end

function MatchService.Initialize()
    print("Match Service Initialized!")
    print("Match State:", currentState)

    Players.PlayerAdded:Connect(addPlayer)
    Players.PlayerRemoving:Connect(removePlayer)

    for _, player in Players:GetPlayers() do
        addPlayer(player)
    end

    print("Maximum Players:", MatchConfig.MAX_PLAYERS)
end

function MatchService.GetState()
    return currentState
end

function MatchService.GetPlayerCount()
    return countPlayers()
end

return MatchService