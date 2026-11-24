local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local LobbyController = {}

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local ACCENT = Color3.fromRGB(46, 224, 154)
local INK = Color3.fromRGB(8, 12, 18)
local WHITE = Color3.fromRGB(238, 245, 249)
local MUTED = Color3.fromRGB(150, 166, 178)

local function label(parent, name, text, size, position, font, color)
	local object = Instance.new("TextLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.Size = size
	object.Position = position
	object.Text = text
	object.TextColor3 = color
	object.TextSize = 14
	object.TextScaled = true
	object.Font = font
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.Parent = parent
	return object
end

local function frame(parent, name, size, position, background)
	local object = Instance.new("Frame")
	object.Name = name
	object.BackgroundColor3 = background
	object.BorderSizePixel = 0
	object.Size = size
	object.Position = position
	object.Parent = parent
	return object
end

local function corner(parent, radius)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius)
	object.Parent = parent
	return object
end

local function stroke(parent, color, transparency, thickness)
	local object = Instance.new("UIStroke")
	object.Color = color
	object.Transparency = transparency
	object.Thickness = thickness
	object.Parent = parent
	return object
end

local function createInterface()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ProjectLastHouseLobby"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local compact = camera.ViewportSize.X < 700
	local cinematic = frame(gui, "CinematicBars", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), Color3.new(0, 0, 0))
	cinematic.BackgroundTransparency = 1

	local barHeight = compact and 64 or 90
	local topBar = frame(cinematic, "TopBar", UDim2.new(1, 0, 0, barHeight), UDim2.fromScale(0, 0), Color3.new(0, 0, 0))
	local bottomBar = frame(cinematic, "BottomBar", UDim2.new(1, 0, 0, barHeight), UDim2.new(0, 0, 1, -barHeight), Color3.new(0, 0, 0))
	topBar.Position = UDim2.new(0, 0, 0, -barHeight)
	bottomBar.Position = UDim2.fromScale(0, 1)

	local welcomeWidth = compact and math.max(280, camera.ViewportSize.X - 40) or 440
	local welcomeX = compact and 20 or 54
	local welcome = frame(cinematic, "Welcome", UDim2.fromOffset(welcomeWidth, 150), UDim2.new(0, welcomeX, 1, -190), INK)
	welcome.BackgroundTransparency = 0.12
	corner(welcome, 8)
	stroke(welcome, ACCENT, 0.3, 1)

	local accentLine = frame(welcome, "Accent", UDim2.new(0, 5, 1, -30), UDim2.fromOffset(15, 15), ACCENT)
	corner(accentLine, 2)

	label(welcome, "Eyebrow", "BLACK SITE  •  NORTHERN FRONT", UDim2.new(1, -70, 0, 22), UDim2.fromOffset(36, 20), Enum.Font.GothamBold, ACCENT)
	label(welcome, "Title", "PROJECT LAST HOUSE", UDim2.new(1, -55, 0, 38), UDim2.fromOffset(36, 46), Enum.Font.GothamBlack, WHITE)
	label(welcome, "Subtitle", "The perimeter holds. Assemble your squad.", UDim2.new(1, -55, 0, 22), UDim2.fromOffset(36, 88), Enum.Font.GothamMedium, MUTED)

	local enter = Instance.new("TextButton")
	enter.Name = "Enter"
	enter.AutoButtonColor = false
	enter.BackgroundColor3 = ACCENT
	enter.BorderSizePixel = 0
	enter.Size = UDim2.new(0, 150, 0, 30)
	enter.Position = UDim2.fromOffset(36, 116)
	enter.Text = "ENTER LOBBY"
	enter.TextColor3 = INK
	enter.TextSize = 13
	enter.Font = Enum.Font.GothamBold
	enter.Parent = welcome
	corner(enter, 4)

	local statusWidth = compact and math.min(280, camera.ViewportSize.X - 32) or 300
	local status = frame(gui, "Status", UDim2.fromOffset(statusWidth, 48), UDim2.new(0.5, -statusWidth / 2, 0, 18), INK)
	status.BackgroundTransparency = 0.2
	corner(status, 24)
	stroke(status, ACCENT, 0.6, 1)

	local pulse = frame(status, "Pulse", UDim2.fromOffset(8, 8), UDim2.fromOffset(18, 20), ACCENT)
	corner(pulse, 4)
	local statusText = label(status, "StatusText", "HQ ONLINE  /  " .. #Players:GetPlayers() .. " SURVIVORS", UDim2.new(1, -45, 1, 0), UDim2.fromOffset(36, 0), Enum.Font.GothamBold, WHITE)
	statusText.TextXAlignment = Enum.TextXAlignment.Center

	local stationWidth = compact and math.max(280, camera.ViewportSize.X - 40) or 360
	local stationX = compact and 20 or -400
	local stationCard = frame(gui, "StationCard", UDim2.fromOffset(stationWidth, 92), UDim2.new(compact and 0 or 1, stationX, 1, -112), INK)
	stationCard.BackgroundTransparency = 0.12
	stationCard.Visible = false
	corner(stationCard, 8)
	stroke(stationCard, ACCENT, 0.35, 1)
	frame(stationCard, "StationAccent", UDim2.new(0, 4, 1, -24), UDim2.fromOffset(12, 12), ACCENT)
	label(stationCard, "StationKind", "FACILITY", UDim2.new(1, -48, 0, 16), UDim2.fromOffset(30, 14), Enum.Font.GothamBold, ACCENT)
	local stationTitle = label(stationCard, "StationTitle", "", UDim2.new(1, -48, 0, 30), UDim2.fromOffset(30, 34), Enum.Font.GothamBlack, WHITE)
	stationTitle.TextSize = 22
	label(stationCard, "StationHint", "Move closer to explore this sector", UDim2.new(1, -48, 0, 18), UDim2.fromOffset(30, 66), Enum.Font.GothamMedium, MUTED)

	local function updatePlayerCount()
		statusText.Text = "HQ ONLINE  /  " .. #Players:GetPlayers() .. " SURVIVORS"
	end
	Players.PlayerAdded:Connect(updatePlayerCount)
	Players.PlayerRemoving:Connect(updatePlayerCount)

	task.spawn(function()
		while gui.Parent do
			TweenService:Create(pulse, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				BackgroundTransparency = 0.55,
			}):Play()
			task.wait(0.65)
			TweenService:Create(pulse, TweenInfo.new(0.65, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
				BackgroundTransparency = 0,
			}):Play()
			task.wait(0.65)
		end
	end)

	return gui, topBar, bottomBar, welcome, enter, stationCard, stationTitle, barHeight, welcomeX
end

local STATION_DETAILS = {
	MatchBay1 = "LOBBY BAY 01",
	MatchBay2 = "LOBBY BAY 02",
	MatchBay3 = "LOBBY BAY 03",
	MatchBay4 = "LOBBY BAY 04",
	SummoningStation = "SUMMON TURRETS",
	ShopStation = "SHOP & REWARDS",
}

local function monitorStations(lobby, stationCard, stationTitle)
	local stations = {}
	for stationId in pairs(STATION_DETAILS) do
		local station = lobby:WaitForChild(stationId, 5)
		if station then
			stations[#stations + 1] = station
		end
	end

	task.spawn(function()
		local currentStation
		while stationCard.Parent do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local closest
			local closestDistance = 28

			if root then
				for _, station in ipairs(stations) do
					local distance = (root.Position - station:GetPivot().Position).Magnitude
					if distance < closestDistance then
						closest = station
						closestDistance = distance
					end
				end
			end

			if closest ~= currentStation then
				currentStation = closest
				stationCard.Visible = closest ~= nil
				stationTitle.Text = closest and STATION_DETAILS[closest.Name] or ""
			end
			task.wait(0.2)
		end
	end)
end

function LobbyController.Initialize()
	local lobby = Workspace:WaitForChild("GeneratedLobby", 15)
	if not lobby then
		warn("Lobby interface could not find GeneratedLobby")
		return
	end

	local gui, topBar, bottomBar, welcome, enter, stationCard, stationTitle, barHeight, welcomeX = createInterface()
	monitorStations(lobby, stationCard, stationTitle)

	local blur = Lighting:FindFirstChild("LobbyIntroBlur")
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Name = "LobbyIntroBlur"
		blur.Size = 10
		blur.Parent = Lighting
	end

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")
	local startFov = camera.FieldOfView
	local oldType = camera.CameraType
	local oldSubject = camera.CameraSubject
	local flightTween = TweenService:Create(camera, TweenInfo.new(4.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		CFrame = CFrame.lookAt(Vector3.new(24, 20, 40), Vector3.new(0, 14, 0)),
		FieldOfView = 55,
	})

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(Vector3.new(56, 34, 72), Vector3.new(0, 13, 0))
	camera.FieldOfView = 48
	welcome.Position = UDim2.new(0, welcomeX, 1, -170)

	TweenService:Create(topBar, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(0, 0),
	}):Play()
	TweenService:Create(bottomBar, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 1, -barHeight),
	}):Play()
	TweenService:Create(welcome, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out, 0, false, 0.15), {
		Position = UDim2.new(0, welcomeX, 1, -190),
	}):Play()

	local finished = false
	local function finishIntro()
		if finished then
			return
		end
		finished = true
		flightTween:Cancel()

		local target = CFrame.lookAt(root.Position + Vector3.new(0, 8, 18), root.Position + Vector3.new(0, 3, 0))
		TweenService:Create(camera, TweenInfo.new(1.15, Enum.EasingStyle.Cubic, Enum.EasingDirection.InOut), {
			CFrame = target,
			FieldOfView = startFov,
		}):Play()
		TweenService:Create(blur, TweenInfo.new(0.7), { Size = 0 }):Play()
		TweenService:Create(topBar, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Position = UDim2.new(0, 0, 0, -barHeight),
		}):Play()
		TweenService:Create(bottomBar, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
			Position = UDim2.fromScale(0, 1),
		}):Play()
		TweenService:Create(welcome, TweenInfo.new(0.45), {
			Position = UDim2.new(0, welcomeX, 1, 30),
		}):Play()

		task.delay(1.2, function()
			camera.CameraType = oldType
			camera.CameraSubject = oldSubject or humanoid
			camera.FieldOfView = startFov
			blur:Destroy()
		end)
	end

	enter.Activated:Connect(finishIntro)
	flightTween:Play()
	task.delay(5, finishIntro)
end

return LobbyController
