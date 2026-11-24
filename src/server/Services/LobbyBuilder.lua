--[[
	PROJECT LAST HOUSE - LOBBY BUILDER (Upgraded)
	Usage is unchanged:  require(LobbyBuilder).Build()

	Config (set before calling Build):
		LobbyBuilder.Config.Animate   = true/false   -- spinning holograms, searchlights, pulsing lights
		LobbyBuilder.Config.Particles = true/false   -- floating sparkles
		LobbyBuilder.Config.Skyline   = true/false   -- ruined city backdrop outside the walls
		LobbyBuilder.Config.ArrivalGate = true/false -- illuminated welcome arch and arrival details

	Each station and matchmaking bay contains an invisible "<Name>_Trigger" part with the
	attribute "StationId" so you can hook up your lobby-creation / Summon / Shop logic.
]]

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local LobbyBuilder = {}

LobbyBuilder.Config = {
	Animate = true,
	Particles = true,
	Skyline = true,
	ArrivalGate = true,
}

local CONFIG = LobbyBuilder.Config

local COLORS = {
	Floor = Color3.fromRGB(43, 48, 55),
	Wall = Color3.fromRGB(61, 68, 75),
	Metal = Color3.fromRGB(83, 91, 99),
	Panel = Color3.fromRGB(50, 57, 65),
	Seam = Color3.fromRGB(30, 34, 40),
	Dark = Color3.fromRGB(22, 26, 32),
	Green = Color3.fromRGB(40, 190, 130),
	Blue = Color3.fromRGB(60, 145, 220),
	Purple = Color3.fromRGB(155, 100, 220),
	Gold = Color3.fromRGB(230, 175, 65),
	Red = Color3.fromRGB(210, 75, 75),
	White = Color3.fromRGB(235, 240, 245),
	Hazard = Color3.fromRGB(235, 190, 40),
	Warm = Color3.fromRGB(255, 225, 170),
	Cyan = Color3.fromRGB(60, 200, 230),
	Orange = Color3.fromRGB(240, 135, 55),
}

local NOFX = {
	CanCollide = false,
	CanQuery = false,
	CanTouch = false,
	CastShadow = false,
}

-- Module state (reset on every Build)
local animated = {}
local pulses = {}
local connection = nil
local rng = Random.new(2026)

--------------------------------------------------------------------------------
-- Core helpers
--------------------------------------------------------------------------------

local function part(parent, name, size, placement, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	if typeof(placement) == "Vector3" then
		p.CFrame = CFrame.new(placement)
	else
		p.CFrame = placement
	end
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	if props then
		for key, value in pairs(props) do
			p[key] = value
		end
	end
	p.Parent = parent
	return p
end

-- Cylinder with its axis along local X (raw)
local function cyl(parent, name, size, placement, color, material, props)
	local p = part(parent, name, size, placement, color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Upright disc (axis = up)
local function disc(parent, name, diameter, height, placement, color, material, props)
	if typeof(placement) == "Vector3" then
		placement = CFrame.new(placement)
	end
	return cyl(
		parent,
		name,
		Vector3.new(height, diameter, diameter),
		placement * CFrame.Angles(0, 0, math.pi / 2),
		color,
		material,
		props
	)
end

-- Rod / barrel (axis = local Z)
local function rod(parent, name, length, diameter, placement, color, material, props)
	return cyl(
		parent,
		name,
		Vector3.new(length, diameter, diameter),
		placement * CFrame.Angles(0, math.pi / 2, 0),
		color,
		material,
		props
	)
end

-- Hollow ring made out of segments (lies flat, centered on `placement`)
local function makeRing(parent, name, placement, radius, segments, thickness, color, material)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	local chord = 2 * radius * math.sin(math.pi / segments) + 0.06
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		local segCF = placement * CFrame.Angles(0, a, 0) * CFrame.new(radius, 0, 0)
		part(
			model,
			name .. "_Seg",
			Vector3.new(thickness, thickness, chord),
			segCF,
			color,
			material or Enum.Material.Neon,
			NOFX
		)
	end
	model.WorldPivot = placement
	return model
end

local function addLight(parent, color, brightness, range, flicker, speed)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = parent
	if flicker then
		table.insert(pulses, {
			light = light,
			base = brightness,
			amp = flicker,
			speed = speed or 2,
			phase = rng:NextNumber(0, 6),
		})
	end
	return light
end

local function animate(obj, spin, bob, bobSpeed)
	if not CONFIG.Animate then
		return
	end
	table.insert(animated, {
		obj = obj,
		base = obj:GetPivot(),
		spin = spin or 0,
		bob = bob,
		bobSpeed = bobSpeed or 1.5,
		phase = rng:NextNumber(0, 6),
	})
end

local function sparkles(parent, placement, size, color, rate, speed)
	if not CONFIG.Particles then
		return
	end
	local emitterPart = part(parent, "Emitter", size, placement, color, Enum.Material.SmoothPlastic, NOFX)
	emitterPart.Transparency = 1

	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(2, 4)
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.Rate = rate
	pe.SpreadAngle = Vector2.new(30, 30)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = emitterPart
end

local function addSmoke(parent, placement, size, color)
	if not CONFIG.Particles then
		return
	end

	local emitterPart = part(parent, "SmokeEmitter", size, placement, color, Enum.Material.SmoothPlastic, NOFX)
	emitterPart.Transparency = 1

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "LowSmoke"
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 0.05
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(1, 5),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.96),
		NumberSequenceKeypoint.new(0.3, 0.82),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(5, 9)
	pe.Speed = NumberRange.new(0.5, 1.2)
	pe.Rate = 2
	pe.RotSpeed = NumberRange.new(-10, 10)
	pe.Rotation = NumberRange.new(0, 360)
	pe.SpreadAngle = Vector2.new(55, 55)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = emitterPart
end

local function makeSign(parent, name, placement, size, title, subtitle, color)
	local sign = part(parent, name, size, placement, Color3.fromRGB(14, 20, 28), Enum.Material.Metal)

	for _, side in ipairs({ -1, 1 }) do
		part(
			parent,
			name .. "_Trim",
			Vector3.new(size.X + 0.3, 0.22, size.Z + 0.15),
			placement * CFrame.new(0, side * size.Y / 2, 0),
			color,
			Enum.Material.Neon,
			NOFX
		)
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignDisplay"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 0
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Name = "Title"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.94, subtitle and 0.6 or 0.8)
	label.Position = UDim2.fromScale(0.03, subtitle and 0.08 or 0.1)
	label.Text = title
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.6
	label.Parent = gui

	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.BackgroundTransparency = 1
		sub.Size = UDim2.fromScale(0.94, 0.2)
		sub.Position = UDim2.fromScale(0.03, 0.7)
		sub.Text = subtitle
		sub.TextColor3 = COLORS.White
		sub.TextTransparency = 0.15
		sub.TextScaled = true
		sub.Font = Enum.Font.GothamMedium
		sub.Parent = gui
	end

	return sign
end

-- Yellow / black warning stripes (strip runs along local X, faces local -Z)
local function hazard(parent, placement, length, height, segment)
	segment = segment or 2
	local count = math.floor(length / segment)
	for i = 0, count - 1 do
		local x = -length / 2 + (i + 0.5) * segment
		part(
			parent,
			"HazardStripe",
			Vector3.new(segment, height, 0.15),
			placement * CFrame.new(x, 0, 0),
			(i % 2 == 0) and COLORS.Hazard or COLORS.Dark,
			Enum.Material.Metal,
			NOFX
		)
	end
end

--------------------------------------------------------------------------------
-- Lighting / atmosphere
--------------------------------------------------------------------------------

local function setupLighting()
	for _, child in ipairs(Lighting:GetChildren()) do
		if string.find(child.Name, "^LobbyFX_") then
			child:Destroy()
		end
	end

	Lighting.ClockTime = 18.8
	Lighting.Brightness = 1.55
	Lighting.Ambient = Color3.fromRGB(58, 70, 92)
	Lighting.OutdoorAmbient = Color3.fromRGB(66, 78, 104)
	Lighting.ExposureCompensation = 0.05
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.FogColor = Color3.fromRGB(54, 68, 94)
	Lighting.FogStart = 150
	Lighting.FogEnd = 620

	local sky = Instance.new("Sky")
	sky.Name = "LobbyFX_Sky"
	sky.StarCount = 4000
	sky.CelestialBodiesShown = true
	sky.Parent = Lighting

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "LobbyFX_Atmosphere"
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(150, 165, 195)
	atmosphere.Decay = Color3.fromRGB(70, 80, 110)
	atmosphere.Glare = 0
	atmosphere.Haze = 1.5
	atmosphere.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "LobbyFX_Bloom"
	bloom.Intensity = 0.42
	bloom.Size = 22
	bloom.Threshold = 1.25
	bloom.Parent = Lighting

	local color = Instance.new("ColorCorrectionEffect")
	color.Name = "LobbyFX_Color"
	color.Contrast = 0.08
	color.Saturation = 0.14
	color.TintColor = Color3.fromRGB(238, 242, 250)
	color.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Name = "LobbyFX_Rays"
	rays.Intensity = 0.04
	rays.Spread = 0.5
	rays.Parent = Lighting
end

--------------------------------------------------------------------------------
-- Floor, lanes, walls
--------------------------------------------------------------------------------

local function buildFloor(lobby)
	-- panel seams
	for x = -80, 80, 20 do
		part(lobby, "SeamX", Vector3.new(0.25, 0.1, 140), Vector3.new(x, 0.05, 0), COLORS.Seam, Enum.Material.SmoothPlastic, NOFX)
	end
	for z = -60, 60, 20 do
		part(lobby, "SeamZ", Vector3.new(180, 0.1, 0.25), Vector3.new(0, 0.05, z), COLORS.Seam, Enum.Material.SmoothPlastic, NOFX)
	end
end

local function buildLane(parent, from, to, color)
	local dir = to - from
	local dist = dir.Magnitude
	if dist < 1 then
		return
	end
	local unit = dir.Unit
	local mid = from + dir / 2
	local y = Vector3.new(0, 0.1, 0)

	-- runway edges
	for _, side in ipairs({ -2.2, 2.2 }) do
		local offset = Vector3.new(-unit.Z, 0, unit.X) * side
		part(
			parent,
			"LaneEdge",
			Vector3.new(0.25, 0.06, dist),
			CFrame.lookAt(mid + offset + y, mid + offset + y + unit),
			color,
			Enum.Material.Neon,
			NOFX
		)
	end

	-- center dashes
	local n = math.floor(dist / 5)
	for i = 0, n - 1 do
		local pos = from + unit * (i * 5 + 2.5) + y
		part(parent, "LaneDash", Vector3.new(0.9, 0.06, 2.6), CFrame.lookAt(pos, pos + unit), color, Enum.Material.Neon, NOFX)
	end

	if dist >= 12 then
		local markerCount = math.max(1, math.floor(dist / 14))
		for i = 0, markerCount - 1 do
			local pos = from + unit * (i * 14 + 7) + Vector3.new(0, 0.08, 0)
			local markerCF = CFrame.lookAt(pos, pos + unit)
			for _, side in ipairs({ -1, 1 }) do
				part(
					parent,
					"LaneChevron",
					Vector3.new(1.6, 0.05, 0.18),
					markerCF * CFrame.new(side * 0.42, 0, 0) * CFrame.Angles(0, side * math.rad(34), 0),
					color,
					Enum.Material.Neon,
					NOFX
				)
			end
		end
	end
end

local function buildWall(lobby, name, placement, length, lightEvery)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = lobby

	part(m, name, Vector3.new(length, 18, 3), placement * CFrame.new(0, 9, 0), COLORS.Wall, Enum.Material.Concrete)
	part(m, "Cornice", Vector3.new(length + 1, 1.2, 4.2), placement * CFrame.new(0, 18.2, 0), COLORS.Metal, Enum.Material.Metal)
	part(m, "Plinth", Vector3.new(length, 1.5, 4), placement * CFrame.new(0, 0.75, -0.5), COLORS.Metal, Enum.Material.Metal)
	hazard(m, placement * CFrame.new(0, 0.75, -2.56), length - 6, 1.2, 2.5)

	-- neon band
	part(m, "WallBand", Vector3.new(length - 2, 0.3, 0.25), placement * CFrame.new(0, 15.2, -1.7), COLORS.Blue, Enum.Material.Neon, NOFX)

	-- recessed panels
	local count = math.floor((length - 12) / 24)
	for i = 0, count - 1 do
		local x = (i - (count - 1) / 2) * 24
		part(m, "WallPanel", Vector3.new(12, 9, 0.3), placement * CFrame.new(x, 9, -1.65), COLORS.Panel, Enum.Material.Metal)
		for _, s in ipairs({ -6, 6 }) do
			part(m, "PanelStrip", Vector3.new(0.25, 9, 0.2), placement * CFrame.new(x + s, 9, -1.75), COLORS.Blue, Enum.Material.Neon, { CanCollide = false, Transparency = 0.3 })
		end

		-- lamp fixtures in the gaps between panels
		if i < count - 1 then
			local lamp = part(m, "WallLight", Vector3.new(6, 0.6, 0.5), placement * CFrame.new(x + 12, 12.5, -1.9), COLORS.White, Enum.Material.Neon, NOFX)
			if i % lightEvery == 0 then
				addLight(lamp, COLORS.Blue, 1.4, 24, 0.08, 1.5)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Skyline, trusses, guard towers
--------------------------------------------------------------------------------

local function buildSkyline(lobby)
	local folder = Instance.new("Folder")
	folder.Name = "Skyline"
	folder.Parent = lobby

	local windowColors = { Color3.fromRGB(255, 200, 110), Color3.fromRGB(120, 200, 255) }
	local count = 36

	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber(-0.06, 0.06)
		local dist = rng:NextNumber(160, 240)
		local position = Vector3.new(math.cos(angle) * dist * 1.25, 0, math.sin(angle) * dist)
		local h = rng:NextNumber(45, 150)
		local w = rng:NextNumber(20, 42)
		local d = rng:NextNumber(20, 42)
		local tone = rng:NextInteger(20, 36)
		local tint = Color3.fromRGB(tone, tone + 4, tone + 10)

		local cf = CFrame.lookAt(position, Vector3.new(0, 0, 0))
			* CFrame.Angles(0, rng:NextNumber(-0.35, 0.35), 0)
			* CFrame.new(0, h / 2 - 3, 0)

		part(folder, "Ruin", Vector3.new(w, h, d), cf, tint, Enum.Material.Concrete)

		-- broken top
		part(
			folder,
			"RuinTop",
			Vector3.new(w * 0.55, 8, d * 0.8),
			cf * CFrame.new(rng:NextNumber(-w / 5, w / 5), h / 2 + 3, 0) * CFrame.Angles(0, 0, rng:NextNumber(-0.25, 0.25)),
			tint,
			Enum.Material.Concrete
		)

		-- a few lit windows
		for _ = 1, rng:NextInteger(3, 7) do
			local wx = rng:NextNumber(-w / 2 + 3, w / 2 - 3)
			local wy = rng:NextNumber(-h / 2 + 8, h / 2 - 4)
			part(
				folder,
				"Window",
				Vector3.new(2.6, 3, 0.3),
				cf * CFrame.new(wx, wy, -d / 2 - 0.1),
				windowColors[rng:NextInteger(1, #windowColors)],
				Enum.Material.Neon,
				{ CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.15 }
			)
		end
	end
end

local function buildTrusses(lobby)
	local m = Instance.new("Model")
	m.Name = "OverheadTrusses"
	m.Parent = lobby

	for _, z in ipairs({ -52, -20, 20, 52 }) do
		part(m, "TrussTop", Vector3.new(180, 1.2, 1.2), Vector3.new(0, 22.4, z), COLORS.Metal, Enum.Material.Metal)
		part(m, "TrussBottom", Vector3.new(180, 1.2, 1.2), Vector3.new(0, 19.4, z), COLORS.Metal, Enum.Material.Metal)
		for x = -84, 84, 12 do
			part(m, "TrussPost", Vector3.new(0.5, 3, 0.5), Vector3.new(x, 20.9, z), COLORS.Wall, Enum.Material.Metal)
		end

		-- hanging industrial lamps
		for _, x in ipairs({ -60, 0, 60 }) do
			part(m, "LampCable", Vector3.new(0.15, 2.2, 0.15), Vector3.new(x, 17.9, z), COLORS.Dark, Enum.Material.Metal, NOFX)
			disc(m, "LampShade", 5.2, 0.5, Vector3.new(x, 16.8, z), COLORS.Dark, Enum.Material.Metal)
			local lamp = disc(m, "LampBulb", 4.4, 0.2, Vector3.new(x, 16.45, z), COLORS.Warm, Enum.Material.Neon, NOFX)
			addLight(lamp, COLORS.Warm, 1, 42, 0.05, 1.5)
		end
	end
end

local function buildGuardTower(lobby, pos)
	local m = Instance.new("Model")
	m.Name = "GuardTower"
	m.Parent = lobby

	for _, dx in ipairs({ -4, 4 }) do
		for _, dz in ipairs({ -4, 4 }) do
			part(m, "Leg", Vector3.new(1.2, 17, 1.2), pos + Vector3.new(dx, 8.5, dz), COLORS.Metal, Enum.Material.Metal)
		end
	end
	part(m, "Deck", Vector3.new(12, 1, 12), pos + Vector3.new(0, 17.5, 0), COLORS.Wall, Enum.Material.Metal)
	part(m, "DeckGlow", Vector3.new(12.2, 0.25, 12.2), pos + Vector3.new(0, 17.0, 0), COLORS.Blue, Enum.Material.Neon, NOFX)

	-- railings
	for _, sx in ipairs({ -5.8, 5.8 }) do
		for _, sz in ipairs({ -5.8, 5.8 }) do
			part(m, "RailPost", Vector3.new(0.4, 1.8, 0.4), pos + Vector3.new(sx, 19.4, sz), COLORS.Metal, Enum.Material.Metal)
		end
		part(m, "RailX", Vector3.new(11.6, 0.35, 0.35), pos + Vector3.new(0, 20.1, sx), COLORS.Metal, Enum.Material.Metal)
		part(m, "RailZ", Vector3.new(0.35, 0.35, 11.6), pos + Vector3.new(sx, 20.1, 0), COLORS.Metal, Enum.Material.Metal)
	end

	-- sweeping searchlight
	local lampPos = pos + Vector3.new(0, 19.6, 0)
	local lamp = Instance.new("Model")
	lamp.Name = "Searchlight"
	lamp.Parent = m

	local casingCF = CFrame.new(lampPos) * CFrame.Angles(math.rad(-28), 0, 0)
	part(lamp, "Casing", Vector3.new(2.2, 2.2, 3.2), casingCF, COLORS.Dark, Enum.Material.Metal)
	local lens = part(lamp, "Lens", Vector3.new(1.8, 1.8, 0.2), casingCF * CFrame.new(0, 0, -1.65), COLORS.Warm, Enum.Material.Neon, NOFX)

	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Front
	spot.Angle = 55
	spot.Range = 85
	spot.Brightness = 4
	spot.Color = COLORS.Warm
	spot.Shadows = false
	spot.Parent = lens

	lamp.WorldPivot = CFrame.new(lampPos)
	animate(lamp, (pos.X * pos.Z > 0) and 0.35 or -0.35)
end

--------------------------------------------------------------------------------
-- Command hub
--------------------------------------------------------------------------------

local function buildHub(lobby)
	local hub = Instance.new("Model")
	hub.Name = "CommandHub"
	hub.Parent = lobby

	disc(hub, "CommandStep", 44, 0.5, Vector3.new(0, 0.25, 0), COLORS.Floor, Enum.Material.Metal)
	disc(hub, "CommandBase", 40, 0.5, Vector3.new(0, 0.75, 0), COLORS.Metal, Enum.Material.Metal)

	-- floor emblem
	makeRing(hub, "HubRingOuter", CFrame.new(0, 1.08, 0), 18.5, 48, 0.3, COLORS.Blue)
	makeRing(hub, "HubRingMid", CFrame.new(0, 1.08, 0), 14, 40, 0.2, COLORS.Blue)
	makeRing(hub, "HubRingInner", CFrame.new(0, 1.08, 0), 10, 32, 0.2, COLORS.White)
	for i = 0, 3 do
		local ang = i * math.pi / 2
		part(hub, "HubSpoke", Vector3.new(0.3, 0.08, 7), CFrame.Angles(0, ang, 0) * CFrame.new(0, 1.05, -12), COLORS.Blue, Enum.Material.Neon, NOFX)
	end

	-- tower
	disc(hub, "CommandTower", 14, 26, Vector3.new(0, 14, 0), COLORS.Wall, Enum.Material.Metal)
	for _, y in ipairs({ 4, 14, 24 }) do
		disc(hub, "TowerBand", 14.6, 0.5, Vector3.new(0, y, 0), COLORS.Blue, Enum.Material.Neon, NOFX)
	end
	for _, y in ipairs({ 9, 19.5 }) do
		for i = 0, 7 do
			local a = (i / 8) * math.pi * 2
			part(
				hub,
				"TowerWindow",
				Vector3.new(1.6, 5, 0.3),
				CFrame.Angles(0, a, 0) * CFrame.new(0, y, 7.05),
				COLORS.White,
				Enum.Material.Neon,
				{ CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.2 }
			)
		end
	end

	-- door
	part(hub, "TowerDoor", Vector3.new(4, 6, 0.4), Vector3.new(0, 4, 7.1), COLORS.Dark, Enum.Material.Metal)
	part(hub, "TowerDoorGlow", Vector3.new(4.4, 0.25, 0.5), Vector3.new(0, 7.1, 7.1), COLORS.Blue, Enum.Material.Neon, NOFX)

	-- cap + antenna
	disc(hub, "TowerCap", 15.6, 1, Vector3.new(0, 27.5, 0), COLORS.Metal, Enum.Material.Metal)
	local glow = disc(hub, "CommandGlow", 15, 0.3, Vector3.new(0, 28.15, 0), COLORS.Blue, Enum.Material.Neon, NOFX)
	addLight(glow, COLORS.Blue, 2, 40, 0.15, 1.2)
	disc(hub, "Antenna", 0.6, 8, Vector3.new(0, 32.5, 0), COLORS.Metal, Enum.Material.Metal)
	local beacon = part(hub, "Beacon", Vector3.new(1.6, 1.6, 1.6), Vector3.new(0, 37, 0), COLORS.Red, Enum.Material.Neon, NOFX)
	beacon.Shape = Enum.PartType.Ball
	addLight(beacon, COLORS.Red, 2, 30, 0.6, 3)

	-- spinning halos
	local halo1 = makeRing(hub, "HaloOuter", CFrame.new(0, 31, 0), 11, 32, 0.5, COLORS.Blue)
	animate(halo1, 0.5)
	local halo2 = makeRing(hub, "HaloInner", CFrame.new(0, 33, 0), 8, 28, 0.3, COLORS.White)
	animate(halo2, -0.9)

	-- structural crown: four armored buttresses make the hub read as a landmark
	local crown = Instance.new("Model")
	crown.Name = "CommandCrown"
	crown.Parent = hub
	for i = 0, 3 do
		local a = math.rad(45 + i * 90)
		local radial = CFrame.Angles(0, a, 0)
		part(crown, "CrownFoot", Vector3.new(6, 1.2, 8), radial * CFrame.new(0, 1.65, 18), COLORS.Dark, Enum.Material.Metal)
		part(crown, "CrownButtress", Vector3.new(4.2, 18, 5), radial * CFrame.new(0, 10.5, 18), COLORS.Metal, Enum.Material.Metal)
		part(crown, "CrownCap", Vector3.new(5.4, 2.2, 6.2), radial * CFrame.new(0, 20.1, 18), COLORS.Wall, Enum.Material.Metal)
		part(crown, "CrownStripe", Vector3.new(0.28, 14, 0.22), radial * CFrame.new(0, 10.8, 20.56), COLORS.Blue, Enum.Material.Neon, NOFX)
		part(crown, "CrownBridge", Vector3.new(5, 1.1, 12), radial * CFrame.new(0, 19.5, 11.5), COLORS.Metal, Enum.Material.Metal)
	end
	makeRing(crown, "CrownRingOuter", CFrame.new(0, 21, 0), 18.5, 40, 0.45, COLORS.Blue, Enum.Material.Neon)
	makeRing(crown, "CrownRingInner", CFrame.new(0, 20.5, 0), 14.5, 36, 0.22, COLORS.White, Enum.Material.Neon)

	-- hanging sign facing the spawn side
	makeSign(
		lobby,
		"CommandSign",
		CFrame.new(0, 17, 8.6) * CFrame.Angles(0, math.pi, 0),
		Vector3.new(18, 4.6, 0.8),
		"LAST HOUSE HQ",
		"SURVIVE THE NIGHT",
		COLORS.White
	)
end

--------------------------------------------------------------------------------
-- Stations
--------------------------------------------------------------------------------

local function extraSummon(model, L, color, name)
	disc(model, name .. "_Pedestal", 8, 0.8, L(0, 1.3, 3), COLORS.Metal, Enum.Material.Metal)
	makeRing(model, name .. "_CircleOuter", L(0, 0.98, 3), 7.2, 36, 0.2, color)
	makeRing(model, name .. "_CircleInner", L(0, 0.98, 3), 5.4, 32, 0.2, color)

	-- rotating rune ring
	local runes = Instance.new("Model")
	runes.Name = name .. "_Runes"
	runes.Parent = model
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		part(runes, "Rune", Vector3.new(0.6, 0.08, 1.4), L(0, 1.0, 3) * CFrame.Angles(0, a, 0) * CFrame.new(6.3, 0, 0), color, Enum.Material.Neon, NOFX)
	end
	runes.WorldPivot = L(0, 1.0, 3)
	animate(runes, 0.5)

	-- hologram turret
	disc(model, name .. "_TurretMount", 2.4, 1.4, L(0, 2.4, 3), COLORS.Wall, Enum.Material.Metal)
	local holo = { Transparency = 0.15, CanCollide = false, CanQuery = false, CastShadow = false }
	local head = Instance.new("Model")
	head.Name = name .. "_TurretHead"
	head.Parent = model
	part(head, "Body", Vector3.new(2.2, 1.6, 2.4), L(0, 4.2, 3), color, Enum.Material.ForceField, holo)
	rod(head, "BarrelL", 3.6, 0.55, L(-0.6, 4.3, 3) * CFrame.new(0, 0, -2.1), color, Enum.Material.ForceField, holo)
	rod(head, "BarrelR", 3.6, 0.55, L(0.6, 4.3, 3) * CFrame.new(0, 0, -2.1), color, Enum.Material.ForceField, holo)
	local eye = part(head, "Eye", Vector3.new(0.5, 0.5, 0.5), L(0, 5.2, 2.4), COLORS.White, Enum.Material.Neon, NOFX)
	eye.Shape = Enum.PartType.Ball
	head.WorldPivot = L(0, 4.2, 3)
	animate(head, 0.6, 0.2, 1.2)

	-- energy column
	local column = disc(model, name .. "_Column", 4, 10, L(0, 6, 3), color, Enum.Material.Neon, {
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Transparency = 0.85,
	})
	addLight(column, color, 2, 26, 0.3, 2.5)
	sparkles(model, L(0, 2, 3), Vector3.new(6, 0.5, 6), color, 14, 4)
end

local function extraShop(model, L, color, name)
	-- treasure chest
	part(model, name .. "_Chest", Vector3.new(4.2, 2, 2.8), L(0, 1.95, 3), Color3.fromRGB(88, 58, 34), Enum.Material.WoodPlanks)
	part(model, name .. "_ChestLid", Vector3.new(4.4, 0.9, 3), L(0, 3.4, 3), Color3.fromRGB(98, 66, 38), Enum.Material.WoodPlanks)
	for _, x in ipairs({ -1.3, 1.3 }) do
		part(model, name .. "_ChestBand", Vector3.new(0.4, 3.3, 3.1), L(x, 2.45, 3), COLORS.Gold, Enum.Material.Metal)
	end
	part(model, name .. "_ChestClasp", Vector3.new(0.7, 0.7, 0.2), L(0, 2.9, 1.5), COLORS.Gold, Enum.Material.Neon, NOFX)

	-- spinning coin
	local coin = Instance.new("Model")
	coin.Name = name .. "_Coin"
	coin.Parent = model
	local face = cyl(coin, "Face", Vector3.new(0.4, 3, 3), L(0, 6, 3), COLORS.Gold, Enum.Material.Neon, NOFX)
	cyl(coin, "Inlay", Vector3.new(0.5, 2.1, 2.1), L(0, 6, 3), Color3.fromRGB(160, 105, 25), Enum.Material.Metal, NOFX)
	coin.WorldPivot = L(0, 6, 3)
	animate(coin, 1.6, 0.35, 1.3)
	addLight(face, COLORS.Gold, 1.8, 24, 0.2, 2)

	-- gold-trimmed supply crates
	for _, sx in ipairs({ -8, 8 }) do
		local function box(y, size, yaw)
			local cf = L(sx, y, 5) * CFrame.Angles(0, math.rad(yaw), 0)
			part(model, name .. "_ShopCrate", size, cf, Color3.fromRGB(40, 38, 34), Enum.Material.Metal)
			for _, dy in ipairs({ -0.4, 0.4 }) do
				part(model, name .. "_CrateTrim", Vector3.new(size.X + 0.12, 0.18, size.Z + 0.12), cf * CFrame.new(0, dy * size.Y, 0), COLORS.Gold, Enum.Material.Neon, NOFX)
			end
		end
		box(2.45, Vector3.new(3.2, 3, 3.2), 0)
		box(4.65, Vector3.new(2.4, 1.4, 2.4), sx * 3)
	end

	sparkles(model, L(0, 3.5, 3), Vector3.new(5, 1, 5), color, 10, 3)
end

local STATIONS = {
	{
		name = "SummoningStation",
		pos = Vector3.new(-48, 0, 40),
		title = "SUMMON TURRETS",
		sub = "UNLOCK NEW DEFENSES",
		cta = "SUMMON",
		color = COLORS.Purple,
		extra = extraSummon,
	},
	{
		name = "ShopStation",
		pos = Vector3.new(48, 0, 40),
		title = "SHOP & REWARDS",
		sub = "GEAR UP & CLAIM LOOT",
		cta = "SHOP",
		color = COLORS.Gold,
		extra = extraShop,
	},
}

local function makeStation(lobby, def)
	local model = Instance.new("Model")
	model.Name = def.name
	model.Parent = lobby

	local name = def.name
	local color = def.color
	-- Station faces the hub (local -Z points to the center of the lobby)
	local base = CFrame.lookAt(def.pos, Vector3.new(0, def.pos.Y, 0))
	local function L(x, y, z)
		return base * CFrame.new(x, y, z)
	end

	-- layered round platform
	disc(model, name .. "_Platform", 32, 0.4, L(0, 0.2, 0), COLORS.Metal, Enum.Material.Metal)
	local rim = disc(model, name .. "_Border", 31, 0.2, L(0, 0.5, 0), color, Enum.Material.Neon, NOFX)
	addLight(rim, color, 1, 22, 0.15, 2)
	disc(model, name .. "_Floor", 29.5, 0.3, L(0, 0.75, 0), COLORS.Floor, Enum.Material.Metal)
	disc(model, name .. "_InlayGlow", 24, 0.04, L(0, 0.92, 0), color, Enum.Material.Neon, NOFX)
	disc(model, name .. "_Inlay", 23.4, 0.04, L(0, 0.93, 0), COLORS.Floor, Enum.Material.Metal, NOFX)

	-- pillars with neon strips
	for _, x in ipairs({ -9.5, 9.5 }) do
		for _, z in ipairs({ -9.5, 9.5 }) do
			part(model, name .. "_Pillar", Vector3.new(1.4, 11.2, 1.4), L(x, 6.5, z), COLORS.Metal, Enum.Material.Metal)
			local sx = (x > 0) and -0.72 or 0.72
			part(model, name .. "_PillarGlow", Vector3.new(0.15, 8, 0.5), L(x + sx, 6.5, z), color, Enum.Material.Neon, NOFX)
		end
	end

	-- roof
	disc(model, name .. "_Roof", 30, 1, L(0, 12, 0), COLORS.Wall, Enum.Material.Metal)
	local roofGlow = disc(model, name .. "_RoofGlow", 30.6, 0.25, L(0, 11.4, 0), color, Enum.Material.Neon, NOFX)
	addLight(roofGlow, color, 1.4, 30, 0.2, 1.8)

	-- back wall + display
	part(model, name .. "_BackWall", Vector3.new(18, 8, 1), L(0, 4.9, 11), COLORS.Wall, Enum.Material.Metal)
	makeSign(model, name .. "_Display", L(0, 5.4, 10.2), Vector3.new(13, 4.2, 0.3), def.sub, nil, color)

	-- counter
	part(model, name .. "_Counter", Vector3.new(15, 2.2, 2.6), L(0, 2, -7), COLORS.Metal, Enum.Material.Metal)
	part(model, name .. "_CounterTop", Vector3.new(15.6, 0.3, 3.2), L(0, 3.25, -7), COLORS.Wall, Enum.Material.Metal)
	part(model, name .. "_CounterGlow", Vector3.new(15, 0.18, 0.12), L(0, 2.1, -8.32), color, Enum.Material.Neon, NOFX)
	makeSign(model, name .. "_Terminal", L(0, 4.5, -6.6) * CFrame.Angles(math.rad(15), 0, 0), Vector3.new(5, 2.4, 0.25), def.cta, nil, color)

	-- big sign on the roof
	for _, x in ipairs({ -7, 7 }) do
		part(model, name .. "_SignPost", Vector3.new(0.8, 3.2, 0.8), L(x, 13.6, -4), COLORS.Metal, Enum.Material.Metal)
	end
	makeSign(model, name .. "_Sign", L(0, 15.2, -4), Vector3.new(19, 4, 0.8), def.title, nil, color)

	-- station-specific centerpiece
	def.extra(model, L, color, name)

	-- invisible interaction zone (hook your logic here)
	local trigger = part(
		model,
		name .. "_Trigger",
		Vector3.new(16, 6, 10),
		L(0, 3.5, -5),
		color,
		Enum.Material.SmoothPlastic,
		{
			CanCollide = false,
			CanTouch = true,
			CanQuery = true,
			CastShadow = false,
			Transparency = 1
		}
	)
	trigger.Transparency = 1
	trigger:SetAttribute("StationId", name)
end

local function buildSectorArchitecture(lobby)
	local architecture = Instance.new("Folder")
	architecture.Name = "SectorArchitecture"
	architecture.Parent = lobby

	local sectorNames = {
		SummoningStation = { code = "03", label = "RESEARCH", height = 18 },
		ShopStation = { code = "04", label = "QUARTERMASTER", height = 14 },
	}

	for _, def in ipairs(STATIONS) do
		local info = sectorNames[def.name]
		local model = Instance.new("Model")
		model.Name = def.name .. "_Bastion"
		model.Parent = architecture
		local base = CFrame.lookAt(def.pos, Vector3.new(0, def.pos.Y, 0))
		local function L(x, y, z)
			return base * CFrame.new(x, y, z)
		end

		part(model, "Facade", Vector3.new(34, 8, 2.4), L(0, 12.5, 18), COLORS.Wall, Enum.Material.Metal)
		part(model, "FacadeInset", Vector3.new(29, 5.4, 0.35), L(0, 12.5, 16.72), COLORS.Dark, Enum.Material.Metal)
		part(model, "FacadeTrim", Vector3.new(34.6, 0.32, 0.35), L(0, 16.45, 16.62), def.color, Enum.Material.Neon, NOFX)
		makeSign(model, "SectorLabel", L(0, 12.6, 16.48), Vector3.new(25, 3.8, 0.25), info.code .. " / " .. info.label, nil, def.color)

		for _, side in ipairs({ -1, 1 }) do
			local x = side * 17.8
			part(model, "BastionFoot", Vector3.new(6.4, 1.2, 7.4), L(x, 0.9, 16.5), COLORS.Dark, Enum.Material.Metal)
			part(model, "BastionTower", Vector3.new(4.4, info.height, 5.2), L(x, info.height / 2 + 1.2, 17), COLORS.Metal, Enum.Material.Metal)
			part(model, "BastionCrown", Vector3.new(6, 1.6, 6.8), L(x, info.height + 1.2, 17), COLORS.Wall, Enum.Material.Metal)
			part(model, "BastionStripe", Vector3.new(0.3, info.height - 3, 0.28), L(x, info.height / 2 + 1.1, 14.25), def.color, Enum.Material.Neon, NOFX)
			part(model, "CanopyBrace", Vector3.new(1.2, 1.2, 12), L(side * 12.8, 12.3, 10) * CFrame.Angles(0, math.rad(side * 12), 0), COLORS.Metal, Enum.Material.Metal)
		end

		for i = -3, 3 do
			local x = i * 4.5
			part(model, "RoofBlade", Vector3.new(2.2, 0.8, 13), L(x, 17.3 + math.abs(i) * 0.65, 13.5), (i % 2 == 0) and COLORS.Metal or COLORS.Wall, Enum.Material.Metal)
			part(model, "RoofBladeGlow", Vector3.new(0.18, 0.18, 10.5), L(x + 1.05, 17.8 + math.abs(i) * 0.65, 13.2), def.color, Enum.Material.Neon, NOFX)
		end

		local beacon = part(model, "SectorBeacon", Vector3.new(0.8, 0.8, 0.8), L(0, 19.5, 18), COLORS.White, Enum.Material.Neon, NOFX)
		beacon.Shape = Enum.PartType.Ball
		addLight(beacon, def.color, 2.2, 28, 0.25, 1.8)
	end
end

--------------------------------------------------------------------------------
-- Matchmaking depot (north side): four truck bays, each with a lobby hangar
--------------------------------------------------------------------------------

local v3 = Vector3.new

local DEPOT = {
	backZ = -69.5, -- interior face of the north wall
	mouthZ = -47.5, -- front opening of every hangar
	pitch = 28, -- distance between bay centres
	truckZ = -36.5, -- truck origin; trucks face south (+Z) toward the exit
}

local BAYS = {
	{ name = "MatchBay1", label = "LOBBY 01", color = COLORS.Cyan, paint = Color3.fromRGB(44, 60, 78), roof = "radar" },
	{ name = "MatchBay2", label = "LOBBY 02", color = COLORS.Green, paint = Color3.fromRGB(52, 68, 52), roof = "rack" },
	{ name = "MatchBay3", label = "LOBBY 03", color = COLORS.Orange, paint = Color3.fromRGB(78, 62, 46), roof = "turret" },
	{ name = "MatchBay4", label = "LOBBY 04", color = COLORS.Red, paint = Color3.fromRGB(70, 48, 54), roof = "antenna" },
}

local function surfaceLabel(part0, face, text, color, size)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.4
	gui.Parent = part0

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = size or UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0.15
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
	return label
end

-- Roof-mounted gear gives each truck its own silhouette
local function buildTruckRoofGear(truck, L, def)
	local color = def.color

	if def.roof == "radar" then
		disc(truck, "RadarMast", 1.2, 1.2, L(0, 9.1, 3), COLORS.Dark, Enum.Material.Metal)
		local dish = Instance.new("Model")
		dish.Name = "RadarDish"
		dish.Parent = truck
		local tilt = CFrame.Angles(math.rad(-28), 0, 0)
		disc(dish, "DishPlate", 3.8, 0.25, L(0, 10.2, 3) * tilt, COLORS.Metal, Enum.Material.Metal)
		disc(dish, "DishGlow", 3.2, 0.1, L(0, 10.2, 3) * tilt * CFrame.new(0, 0.18, 0), color, Enum.Material.Neon, NOFX)
		rod(dish, "DishFeed", 1.8, 0.18, L(0, 10.9, 2.4) * tilt, COLORS.Metal, Enum.Material.Metal, NOFX)
		dish.WorldPivot = L(0, 10.2, 3)
		animate(dish, 0.9)
	elseif def.roof == "rack" then
		part(truck, "RackFrame", v3(7, 0.3, 10.6), L(0, 8.65, 2.9), COLORS.Dark, Enum.Material.Metal)
		for i, z in ipairs({ -0.4, 3.4, 7 }) do
			local x = (i % 2 == 0) and 1.6 or -1.6
			part(truck, "RoofCrate", v3(2.6, 1.3, 2.6), L(x, 9.45, z), Color3.fromRGB(88, 100, 74), Enum.Material.WoodPlanks)
			part(truck, "RoofCrateBand", v3(2.7, 0.2, 2.7), L(x, 9.45, z), color, Enum.Material.Neon, NOFX)
		end
	elseif def.roof == "turret" then
		disc(truck, "TurretRing", 3.4, 0.5, L(0, 8.75, 3), COLORS.Dark, Enum.Material.Metal)
		local head = Instance.new("Model")
		head.Name = "RoofTurret"
		head.Parent = truck
		part(head, "Body", v3(2.4, 1.4, 2.8), L(0, 9.7, 3), COLORS.Wall, Enum.Material.Metal)
		part(head, "Shield", v3(2.8, 1.6, 0.4), L(0, 9.8, 1.5), def.paint, Enum.Material.Metal)
		for _, side in ipairs({ -1, 1 }) do
			rod(head, "Barrel", 3.6, 0.5, L(side * 0.6, 9.8, 3) * CFrame.new(0, 0, -3.2), COLORS.Dark, Enum.Material.Metal)
			part(head, "Muzzle", v3(0.45, 0.45, 0.2), L(side * 0.6, 9.8, 3) * CFrame.new(0, 0, -5.1), color, Enum.Material.Neon, NOFX)
		end
		head.WorldPivot = L(0, 9.7, 3)
		animate(head, 0.45)
	else
		for i, mast in ipairs({ { -2.4, 3.2, 4.5 }, { 0, 2.2, 6 }, { 2.4, 4.6, 3.6 } }) do
			disc(truck, "Mast", 0.25, mast[3], L(mast[1], 8.5 + mast[3] / 2, mast[2]), COLORS.Metal, Enum.Material.Metal)
			local tip = part(truck, "MastTip", v3(0.5, 0.5, 0.5), L(mast[1], 8.5 + mast[3] + 0.2, mast[2]), COLORS.Red, Enum.Material.Neon, NOFX)
			tip.Shape = Enum.PartType.Ball
			if i == 2 then
				addLight(tip, COLORS.Red, 1.4, 16, 0.6, 3)
			end
		end
		part(truck, "MastArm", v3(4, 0.2, 0.2), L(0, 13.5, 2.2), COLORS.Metal, Enum.Material.Metal, NOFX)
	end
end

-- Armoured box truck. Local -Z is the front, so `base` should face the exit.
local function buildTruck(parent, base, def)
	local color, paint = def.color, def.paint
	local truck = Instance.new("Model")
	truck.Name = def.name .. "_Truck"
	truck.Parent = parent

	local function L(x, y, z)
		return base * CFrame.new(x, y, z)
	end
	local tire = Color3.fromRGB(18, 19, 22)
	local glassProps = { Transparency = 0.3, CanCollide = false, CanQuery = false }
	local glassColor = Color3.fromRGB(70, 110, 140)

	-- chassis, underglow, wheels
	part(truck, "Chassis", v3(6.6, 1, 17.4), L(0, 2.2, -0.3), COLORS.Dark, Enum.Material.Metal)
	for _, side in ipairs({ -1, 1 }) do
		part(truck, "Underglow", v3(0.2, 0.14, 15), L(side * 3.35, 1.85, 0.2), color, Enum.Material.Neon, NOFX)
		part(truck, "Fender", v3(2.1, 0.4, 4.2), L(side * 3.8, 3.5, -6.2), paint, Enum.Material.Metal)
		part(truck, "Fender", v3(2.1, 0.4, 8.4), L(side * 3.8, 3.5, 4.6), paint, Enum.Material.Metal)
	end
	for _, z in ipairs({ -6.2, 2.8, 6.4 }) do
		for _, side in ipairs({ -1, 1 }) do
			cyl(truck, "Wheel", v3(1.5, 3.2, 3.2), L(side * 3.7, 1.6, z), tire, Enum.Material.Rubber)
			cyl(truck, "Hub", v3(0.2, 1.5, 1.5), L(side * 4.5, 1.6, z), color, Enum.Material.Neon, NOFX)
		end
	end

	-- cab
	part(truck, "Cab", v3(7.6, 4.8, 5.6), L(0, 5.1, -6.4), paint, Enum.Material.Metal)
	part(truck, "CabRoof", v3(7.8, 0.35, 5.8), L(0, 7.65, -6.4), COLORS.Metal, Enum.Material.Metal)
	part(truck, "Windshield", v3(6.4, 2.1, 0.25), L(0, 5.9, -9.25), glassColor, Enum.Material.Glass, glassProps)
	for _, side in ipairs({ -1, 1 }) do
		part(truck, "SideWindow", v3(0.25, 1.9, 2.8), L(side * 3.85, 5.9, -6.0), glassColor, Enum.Material.Glass, glassProps)
		part(truck, "MirrorArm", v3(0.6, 0.15, 0.15), L(side * 4.1, 6.4, -8.6), COLORS.Dark, Enum.Material.Metal, NOFX)
		part(truck, "Mirror", v3(0.3, 1, 0.5), L(side * 4.45, 6.1, -8.6), COLORS.Dark, Enum.Material.Metal, NOFX)
		part(truck, "CabStripe", v3(0.12, 0.3, 5.4), L(side * 3.83, 3.7, -6.4), color, Enum.Material.Neon, NOFX)

		local lamp = part(truck, "Headlight", v3(1.4, 0.8, 0.3), L(side * 3.0, 3.9, -9.35), COLORS.Warm, Enum.Material.Neon, NOFX)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 55
		spot.Range = 26
		spot.Brightness = 1.2
		spot.Color = COLORS.Warm
		spot.Shadows = false
		spot.Parent = lamp
	end
	part(truck, "Grille", v3(4.4, 1.6, 0.3), L(0, 3.9, -9.35), COLORS.Dark, Enum.Material.Metal)
	for _, y in ipairs({ 3.5, 3.9, 4.3 }) do
		part(truck, "GrilleSlat", v3(4, 0.1, 0.1), L(0, y, -9.55), color, Enum.Material.Neon, NOFX)
	end
	part(truck, "FrontBumper", v3(7.8, 0.9, 0.9), L(0, 2.4, -9.4), COLORS.Dark, Enum.Material.Metal)
	hazard(truck, L(0, 2.4, -9.88), 7.6, 0.7, 1.9)
	part(truck, "LightBar", v3(5, 0.35, 0.5), L(0, 7.95, -8.4), color, Enum.Material.Neon, NOFX)

	local beacon = part(truck, "CabBeacon", v3(0.7, 0.7, 0.7), L(0, 8.2, -5.4), COLORS.White, Enum.Material.Neon, NOFX)
	beacon.Shape = Enum.PartType.Ball
	addLight(beacon, color, 1.6, 22, 0.5, 2.6)

	-- cargo box
	part(truck, "CargoBox", v3(7.8, 5.8, 11.8), L(0, 5.6, 2.9), paint, Enum.Material.Metal)
	part(truck, "CargoRoof", v3(8, 0.3, 12), L(0, 8.65, 2.9), COLORS.Metal, Enum.Material.Metal)
	for _, z in ipairs({ -2.7, 0.8, 4.3, 8.5 }) do
		part(truck, "BoxRib", v3(7.95, 6, 0.35), L(0, 5.6, z), COLORS.Metal, Enum.Material.Metal)
	end
	for _, side in ipairs({ -1, 1 }) do
		for _, y in ipairs({ 7.9, 3.3 }) do
			part(truck, "BoxStripe", v3(0.12, 0.35, 11.4), L(side * 3.93, y, 2.9), color, Enum.Material.Neon, NOFX)
		end
		local plate = part(truck, "BoxPlate", v3(0.12, 2.6, 8), L(side * 3.93, 5.6, 3.2), COLORS.Dark, Enum.Material.Metal, NOFX)
		surfaceLabel(plate, (side == 1) and Enum.NormalId.Right or Enum.NormalId.Left, def.label, color, UDim2.fromScale(0.92, 0.5))
	end

	-- rear doors and tail lights face the hangar
	part(truck, "RearDoors", v3(7.4, 5.2, 0.2), L(0, 5.5, 8.95), COLORS.Dark, Enum.Material.Metal)
	part(truck, "RearSeam", v3(0.1, 5, 0.1), L(0, 5.5, 9.08), color, Enum.Material.Neon, NOFX)
	for _, side in ipairs({ -1, 1 }) do
		part(truck, "TailLight", v3(0.9, 0.5, 0.2), L(side * 3.0, 3.3, 9.05), COLORS.Red, Enum.Material.Neon, NOFX)
	end
	part(truck, "RearBumper", v3(7.8, 0.7, 0.7), L(0, 2.2, 9.2), COLORS.Dark, Enum.Material.Metal)
	hazard(truck, L(0, 2.2, 9.57) * CFrame.Angles(0, math.pi, 0), 7.6, 0.6, 1.9)

	buildTruckRoofGear(truck, L, def)
	return truck
end

-- Square hangar behind the truck: the space where a player creates a lobby
local function buildHangar(model, def, bx)
	local name, color = def.name, def.color
	local backZ, mouthZ = DEPOT.backZ, DEPOT.mouthZ
	local depth = mouthZ - backZ
	local midZ = (backZ + mouthZ) / 2

	-- floor
	part(model, name .. "_HangarFloor", v3(24, 0.3, depth), v3(bx, 0.15, midZ), COLORS.Dark, Enum.Material.Metal)
	part(model, name .. "_HangarInlay", v3(22.4, 0.06, depth - 1.6), v3(bx, 0.33, midZ), COLORS.Floor, Enum.Material.DiamondPlate, NOFX)
	for _, side in ipairs({ -1, 1 }) do
		part(model, name .. "_FloorEdge", v3(0.3, 0.06, depth - 1), v3(bx + side * 11.6, 0.37, midZ), color, Enum.Material.Neon, NOFX)
	end
	part(model, name .. "_Threshold", v3(24, 0.06, 0.35), v3(bx, 0.37, mouthZ + 0.6), color, Enum.Material.Neon, NOFX)

	-- roof, beams and lighting
	part(model, name .. "_HangarRoof", v3(24, 1.2, depth), v3(bx, 14, midZ), COLORS.Wall, Enum.Material.Metal)
	for _, side in ipairs({ -1, 1 }) do
		part(model, name .. "_RoofBeam", v3(1, 0.8, depth), v3(bx + side * 6, 13, midZ), COLORS.Metal, Enum.Material.Metal)
		part(model, name .. "_RoofStrip", v3(0.4, 0.12, depth - 3), v3(bx + side * 6, 12.55, midZ), COLORS.White, Enum.Material.Neon, NOFX)
	end
	local lamp = part(model, name .. "_HangarLamp", v3(3, 0.2, 3), v3(bx, 13.3, midZ), COLORS.Warm, Enum.Material.Neon, NOFX)
	addLight(lamp, COLORS.Warm, 1.1, 30, 0.06, 1.4)

	-- back wall with the bay's call sign
	part(model, name .. "_BackWall", v3(23.6, 12.6, 0.4), v3(bx, 6.6, -68.6), COLORS.Panel, Enum.Material.Metal)
	for _, side in ipairs({ -1, 1 }) do
		part(model, name .. "_BackStrip", v3(0.25, 11, 0.2), v3(bx + side * 11.2, 6.6, -68.35), color, Enum.Material.Neon, NOFX)
	end
	makeSign(
		model,
		name .. "_BackSign",
		CFrame.new(bx, 9.4, -68.3) * CFrame.Angles(0, math.pi, 0),
		v3(16, 3.4, 0.3),
		"CREATE LOBBY",
		"STEP INTO THE RING TO HOST",
		color
	)

	-- lobby terminal
	part(model, name .. "_Console", v3(9, 2.4, 3), v3(bx, 1.5, -66.2), COLORS.Metal, Enum.Material.Metal)
	part(model, name .. "_ConsoleTop", v3(9.6, 0.3, 3.6), v3(bx, 2.85, -66.2), COLORS.Wall, Enum.Material.Metal)
	part(model, name .. "_ConsoleGlow", v3(9, 0.16, 0.12), v3(bx, 1.7, -64.65), color, Enum.Material.Neon, NOFX)
	part(model, name .. "_TerminalStem", v3(1, 0.8, 0.8), v3(bx, 3.4, -66.5), COLORS.Dark, Enum.Material.Metal)
	makeSign(
		model,
		name .. "_Terminal",
		CFrame.new(bx, 4.5, -66.3) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(15), 0, 0),
		v3(6, 2.6, 0.25),
		"HOST LOBBY",
		"0 / 4 SQUAD",
		color
	)

	-- lobby pad where the host stands
	local padPos = v3(bx, 0.4, -58.5)
	disc(model, name .. "_PadRing", 11, 0.08, padPos, color, Enum.Material.Neon, NOFX)
	disc(model, name .. "_PadBase", 10.5, 0.1, padPos + v3(0, 0.01, 0), COLORS.Dark, Enum.Material.Metal, NOFX)
	disc(model, name .. "_PadRingInner", 7, 0.1, padPos + v3(0, 0.02, 0), color, Enum.Material.Neon, NOFX)
	local core = disc(model, name .. "_PadCore", 6.5, 0.12, padPos + v3(0, 0.03, 0), COLORS.Floor, Enum.Material.Metal, NOFX)
	addLight(core, color, 1.2, 18, 0.2, 2)

	local padLabel = part(model, name .. "_PadLabel", v3(5.4, 0.05, 1.5), v3(bx, 0.52, -54.6), COLORS.Dark, Enum.Material.SmoothPlastic, NOFX)
	padLabel.Transparency = 1
	surfaceLabel(padLabel, Enum.NormalId.Top, "HOST LOBBY", color)

	-- four squad slots (MatchConfig.MAX_PLAYERS)
	for _, x in ipairs({ -4.5, -1.5, 1.5, 4.5 }) do
		disc(model, name .. "_SlotRing", 1.9, 0.06, v3(bx + x, 0.56, -63), color, Enum.Material.Neon, NOFX)
		disc(model, name .. "_SlotCore", 1.5, 0.07, v3(bx + x, 0.57, -63), COLORS.Dark, Enum.Material.Metal, NOFX)
	end

	-- holographic lobby model on the left, supply crates on the right
	local standPos = v3(bx - 8.2, 0, -65.5)
	disc(model, name .. "_HoloStand", 4, 1.2, standPos + v3(0, 0.9, 0), COLORS.Metal, Enum.Material.Metal)
	disc(model, name .. "_HoloStandGlow", 4.2, 0.12, standPos + v3(0, 1.55, 0), color, Enum.Material.Neon, NOFX)
	local holo = { Transparency = 0.25, CanCollide = false, CanQuery = false, CastShadow = false }
	local house = Instance.new("Model")
	house.Name = name .. "_HoloHouse"
	house.Parent = model
	local housePos = standPos + v3(0, 3.4, 0)
	part(house, "Body", v3(2.2, 1.5, 2.2), housePos, color, Enum.Material.ForceField, holo)
	part(house, "RoofL", v3(1.7, 0.25, 2.6), CFrame.new(housePos + v3(-0.8, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(35)), color, Enum.Material.ForceField, holo)
	part(house, "RoofR", v3(1.7, 0.25, 2.6), CFrame.new(housePos + v3(0.8, 1.1, 0)) * CFrame.Angles(0, 0, math.rad(-35)), color, Enum.Material.ForceField, holo)
	house.WorldPivot = CFrame.new(housePos)
	animate(house, 0.8, 0.2, 1.5)

	local cratePos = v3(bx + 8.2, 0, -65.8)
	part(model, name .. "_SupplyCrate", v3(3.4, 2.7, 3.2), cratePos + v3(0, 1.65, 0), Color3.fromRGB(88, 100, 74), Enum.Material.WoodPlanks)
	part(model, name .. "_SupplyCrate", v3(2.4, 1.6, 2.4), cratePos + v3(0, 3.8, 0) , Color3.fromRGB(78, 90, 66), Enum.Material.WoodPlanks)
	for _, y in ipairs({ 1.65, 3.8 }) do
		part(model, name .. "_CrateBand", v3(3.5, 0.2, 3.3), cratePos + v3(0, y, 0), color, Enum.Material.Neon, NOFX)
	end

	-- status boards on the side piers
	for _, side in ipairs({ -1, 1 }) do
		makeSign(
			model,
			name .. ((side == -1) and "_SquadBoard" or "_StatusBoard"),
			CFrame.new(bx + side * 11.85, 8, -58.5) * CFrame.Angles(0, side * math.pi / 2, 0),
			v3(9, 3.2, 0.25),
			(side == -1) and "SQUAD 0 / 4" or "STATUS: OPEN",
			(side == -1) and "WAITING FOR PLAYERS" or "LOBBY NOT STARTED",
			color
		)
	end

	sparkles(model, v3(bx, 1, -58.5), v3(8, 1, 8), color, 5, 2)
end

-- Open forecourt in front of the hangar where the truck is parked
local function buildForecourt(model, def, bx)
	local name, color = def.name, def.color
	local frontZ = -24.5
	local length = frontZ - DEPOT.mouthZ
	local midZ = (frontZ + DEPOT.mouthZ) / 2

	part(model, name .. "_Forecourt", v3(24, 0.14, length), v3(bx, 0.07, midZ), Color3.fromRGB(34, 38, 44), Enum.Material.Metal, NOFX)
	for _, side in ipairs({ -1, 1 }) do
		part(model, name .. "_CourtEdge", v3(0.3, 0.05, length), v3(bx + side * 11.7, 0.16, midZ), color, Enum.Material.Neon, NOFX)
		-- bollards at the exit end
		part(model, name .. "_Bollard", v3(0.7, 2.2, 0.7), v3(bx + side * 11.4, 1.1, frontZ + 0.5), COLORS.Metal, Enum.Material.Metal)
		part(model, name .. "_BollardCap", v3(0.8, 0.25, 0.8), v3(bx + side * 11.4, 2.3, frontZ + 0.5), color, Enum.Material.Neon, NOFX)
	end

	-- hazard stop line at the exit end
	for k = 0, 9 do
		part(
			model,
			name .. "_StopLine",
			v3(2.4, 0.05, 0.9),
			v3(bx - 12 + (k + 0.5) * 2.4, 0.16, frontZ - 0.3),
			(k % 2 == 0) and COLORS.Hazard or COLORS.Dark,
			Enum.Material.Metal,
			NOFX
		)
	end

	-- exit chevrons on the left walkway, bay number on the right
	local chevronPos = v3(bx - 8.2, 0.16, -32)
	local chevronCF = CFrame.lookAt(chevronPos, chevronPos + v3(0, 0, 1))
	for _, side in ipairs({ -1, 1 }) do
		part(
			model,
			name .. "_ExitChevron",
			v3(2.4, 0.05, 0.28),
			chevronCF * CFrame.new(side * 0.6, 0, 0) * CFrame.Angles(0, side * math.rad(34), 0),
			color,
			Enum.Material.Neon,
			NOFX
		)
	end
	local number = part(model, name .. "_BayNumber", v3(5, 0.05, 3), v3(bx + 8.2, 0.17, -32), COLORS.Dark, Enum.Material.SmoothPlastic, NOFX)
	number.Transparency = 1
	surfaceLabel(number, Enum.NormalId.Top, string.format("%02d", tonumber(string.match(name, "%d+"))), color)
end

local function buildMatchBays(lobby)
	local structure = Instance.new("Folder")
	structure.Name = "MatchDepotStructure"
	structure.Parent = lobby

	local backZ, mouthZ = DEPOT.backZ, DEPOT.mouthZ
	local depth = mouthZ - backZ
	local midZ = (backZ + mouthZ) / 2
	local count = #BAYS
	local frontZ = mouthZ + 1

	-- piers between and around the bays
	for i = 0, count do
		local px = (i - count / 2) * DEPOT.pitch
		local leftDef, rightDef = BAYS[i], BAYS[i + 1]
		local leftColor = (leftDef or rightDef).color
		local rightColor = (rightDef or leftDef).color

		part(structure, "Pier", v3(4, 15, depth + 1), v3(px, 7.5, midZ + 0.5), COLORS.Wall, Enum.Material.Metal)
		part(structure, "PierPlate", v3(3.2, 13.5, 0.3), v3(px, 7.5, frontZ - 0.15), COLORS.Dark, Enum.Material.Metal)
		part(structure, "PierStripe", v3(0.3, 12.5, 0.2), v3(px - 0.9, 7.5, frontZ + 0.05), leftColor, Enum.Material.Neon, NOFX)
		part(structure, "PierStripe", v3(0.3, 12.5, 0.2), v3(px + 0.9, 7.5, frontZ + 0.05), rightColor, Enum.Material.Neon, NOFX)
		part(structure, "PierCap", v3(5.2, 1, depth + 2), v3(px, 15.5, midZ + 0.5), COLORS.Metal, Enum.Material.Metal)
		local beacon = part(structure, "PierBeacon", v3(0.9, 0.9, 0.9), v3(px, 16.4, frontZ + 0.5), COLORS.White, Enum.Material.Neon, NOFX)
		beacon.Shape = Enum.PartType.Ball
		hazard(structure, CFrame.new(px, 0.9, frontZ + 0.1) * CFrame.Angles(0, math.pi, 0), 4, 1.2, 1)
	end

	-- overall depot sign carried on the outer piers
	for _, side in ipairs({ -1, 1 }) do
		part(structure, "DepotSignPost", v3(0.8, 3.5, 0.8), v3(side * 27, 17.75, frontZ), COLORS.Metal, Enum.Material.Metal)
	end
	makeSign(
		structure,
		"DepotSign",
		CFrame.new(0, 20.4, frontZ) * CFrame.Angles(0, math.pi, 0),
		v3(58, 5, 0.8),
		"MATCHMAKING DEPOT",
		"BOARD A TRUCK  •  HOST YOUR OWN LOBBY",
		COLORS.White
	)

	for index, def in ipairs(BAYS) do
		local bx = (index - (count + 1) / 2) * DEPOT.pitch
		local model = Instance.new("Model")
		model.Name = def.name
		model.Parent = lobby
		model:SetAttribute("BayIndex", index)

		buildHangar(model, def, bx)
		buildForecourt(model, def, bx)

		-- hangar portal: shutter housing, hazard lip and bay sign
		part(model, def.name .. "_Lintel", v3(24, 2.6, 1.6), v3(bx, 12.4, mouthZ + 0.3), COLORS.Metal, Enum.Material.Metal)
		part(model, def.name .. "_LintelGlow", v3(24, 0.2, 0.3), v3(bx, 11, frontZ - 0.1), def.color, Enum.Material.Neon, NOFX)
		hazard(model, CFrame.new(bx, 11.4, frontZ - 0.12) * CFrame.Angles(0, math.pi, 0), 22, 0.5, 1.5)
		makeSign(
			model,
			def.name .. "_PortalSign",
			CFrame.new(bx, 15.2, mouthZ + 0.5) * CFrame.Angles(0, math.pi, 0),
			v3(22, 2.6, 0.6),
			def.label,
			"MATCHMAKING BAY",
			def.color
		)

		-- the truck is parked in front of the hangar, nose pointing at the exit
		local origin = v3(bx, 0, DEPOT.truckZ)
		buildTruck(model, CFrame.lookAt(origin, origin + v3(0, 0, 1)), def)

		local trigger = part(
			model,
			def.name .. "_Trigger",
			v3(22, 7, 20),
			v3(bx, 3.8, -59),
			def.color,
			Enum.Material.SmoothPlastic,
			{ CanCollide = false, CanTouch = true, CanQuery = true, CastShadow = false, Transparency = 1 }
		)
		trigger:SetAttribute("StationId", def.name)
		trigger:SetAttribute("BayIndex", index)

		model.WorldPivot = CFrame.new(bx, 3, -50)
	end
end

--------------------------------------------------------------------------------
-- Military decoration
--------------------------------------------------------------------------------

local function crate(parent, placement, size, label)
	local body = part(parent, "SupplyCrate", size, placement, Color3.fromRGB(92, 105, 78), Enum.Material.WoodPlanks)
	for _, y in ipairs({ -0.36, 0.36 }) do
		part(parent, "CrateBand", Vector3.new(size.X + 0.2, 0.45, size.Z + 0.2), placement * CFrame.new(0, y * size.Y, 0), Color3.fromRGB(44, 50, 44), Enum.Material.Metal, NOFX)
	end
	if label then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.Parent = body
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(0.7, 0.22)
		text.Position = UDim2.fromScale(0.15, 0.39)
		text.Text = label
		text.TextColor3 = Color3.fromRGB(225, 225, 200)
		text.TextTransparency = 0.15
		text.TextScaled = true
		text.Font = Enum.Font.GothamBlack
		text.Parent = gui
	end
end

local function sandbagWall(parent, placement, count, rows)
	local tones = {
		Color3.fromRGB(132, 119, 91),
		Color3.fromRGB(120, 108, 82),
		Color3.fromRGB(142, 128, 98),
	}
	for r = 0, rows - 1 do
		for i = 0, count - 1 do
			local x = (i - (count - 1) / 2 + (r % 2) * 0.5) * 4.2
			part(
				parent,
				"Sandbag",
				Vector3.new(4.2, 1.1, 2.2),
				placement * CFrame.new(x, 0.55 + r * 1.05, 0) * CFrame.Angles(0, rng:NextNumber(-0.08, 0.08), 0),
				tones[rng:NextInteger(1, #tones)],
				Enum.Material.Fabric
			)
		end
	end
end

local function jerseyBarrier(parent, placement)
	part(parent, "JerseyBarrier", Vector3.new(10, 3, 2.5), placement * CFrame.new(0, 1.5, 0), Color3.fromRGB(112, 117, 122), Enum.Material.Concrete)
	part(parent, "JerseyBase", Vector3.new(10, 0.8, 3.4), placement * CFrame.new(0, 0.4, 0), Color3.fromRGB(98, 103, 108), Enum.Material.Concrete)
	hazard(parent, placement * CFrame.new(0, 2.3, -1.28), 10, 0.8, 1.25)
end

local function hedgehog(parent, position)
	local cf = CFrame.new(position + Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	local size = Vector3.new(8, 0.9, 0.9)
	part(parent, "TankTrap", size, cf * CFrame.Angles(0, 0, math.pi / 4), COLORS.Metal, Enum.Material.Metal)
	part(parent, "TankTrap", size, cf * CFrame.Angles(0, 0, -math.pi / 4), COLORS.Metal, Enum.Material.Metal)
	part(parent, "TankTrap", size, cf * CFrame.Angles(0, math.pi / 2, math.pi / 4), COLORS.Metal, Enum.Material.Metal)
end

local function fireBarrel(parent, position)
	disc(parent, "FireBarrel", 3, 4, position + Vector3.new(0, 2, 0), Color3.fromRGB(140, 60, 45), Enum.Material.Metal)
	for _, y in ipairs({ 1, 3 }) do
		disc(parent, "BarrelRing", 3.15, 0.3, position + Vector3.new(0, y, 0), Color3.fromRGB(70, 35, 28), Enum.Material.Metal, NOFX)
	end
	local top = disc(parent, "BarrelCoals", 2.6, 0.2, position + Vector3.new(0, 4.05, 0), Color3.fromRGB(20, 16, 14), Enum.Material.Slate, NOFX)

	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 0
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(255, 70, 20)
	fire.Parent = top

	addLight(top, Color3.fromRGB(255, 150, 70), 2.2, 24, 0.35, 9)
end

local function buildMilitary(lobby)
	local deco = Instance.new("Model")
	deco.Name = "MilitaryDecor"
	deco.Parent = lobby

	-- supply crate stacks (back corners, near the guard towers)
	local labels = { "AMMO", "MEDIC", "FUEL", "RATIONS" }
	for index, side in ipairs({ -1, 1 }) do
		local c = Vector3.new(side * 64, 0, 61)
		crate(deco, CFrame.new(c + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, math.rad(side * 12), 0), Vector3.new(6, 5, 6), labels[index])
		crate(deco, CFrame.new(c + Vector3.new(6.5, 2, 1)) * CFrame.Angles(0, math.rad(-side * 8), 0), Vector3.new(5, 4, 5), labels[index + 2])
		crate(deco, CFrame.new(c + Vector3.new(0.4, 6.5, 0.2)) * CFrame.Angles(0, math.rad(25), 0), Vector3.new(4, 3, 4), nil)
	end

	-- sandbag barricades
	for _, side in ipairs({ -1, 1 }) do
		sandbagWall(deco, CFrame.new(side * 72, 0, -52), 6, 3)
		sandbagWall(deco, CFrame.new(side * 16, 0, 60), 3, 2)
	end

	-- jersey barriers on the east / west flanks
	for _, z in ipairs({ -14, 0, 14 }) do
		jerseyBarrier(deco, CFrame.new(76, 0, z) * CFrame.Angles(0, math.pi / 2, 0))
		jerseyBarrier(deco, CFrame.new(-76, 0, z) * CFrame.Angles(0, -math.pi / 2, 0))
	end

	-- tank traps
	for _, p in ipairs({
		Vector3.new(-28, 0, 60),
		Vector3.new(28, 0, 60),
	}) do
		hedgehog(deco, p)
	end

	-- fire barrels
	for _, p in ipairs({
		Vector3.new(-14, 0, 50),
		Vector3.new(14, 0, 50),
		Vector3.new(-70, 0, -20),
		Vector3.new(70, 0, -20),
	}) do
		fireBarrel(deco, p)
	end
end

local function buildPerimeterSigns(lobby)
	local signs = Instance.new("Folder")
	signs.Name = "PerimeterWayfinding"
	signs.Parent = lobby

	makeSign(
		signs,
		"SouthSectorSign",
		CFrame.new(58, 9, 69.1),
		Vector3.new(18, 4.5, 0.5),
		"SECTOR B-02",
		"SAFE ZONE",
		COLORS.Green
	)
	makeSign(
		signs,
		"EastSectorSign",
		CFrame.new(89.1, 9, -45) * CFrame.Angles(0, math.pi / 2, 0),
		Vector3.new(16, 4.5, 0.5),
		"ARMORY",
		"SUPPLY ACCESS",
		COLORS.Gold
	)
	makeSign(
		signs,
		"WestSectorSign",
		CFrame.new(-89.1, 9, 45) * CFrame.Angles(0, -math.pi / 2, 0),
		Vector3.new(16, 4.5, 0.5),
		"COMMAND",
		"HQ UPLINK",
		COLORS.Purple
	)
end

local function buildAtmosphericDetails(lobby)
	local atmosphere = Instance.new("Folder")
	atmosphere.Name = "AtmosphericDetails"
	atmosphere.Parent = lobby

	for _, point in ipairs({
		Vector3.new(-82, 1, 45),
		Vector3.new(82, 1, 45),
		Vector3.new(-82, 1, -45),
		Vector3.new(82, 1, -45),
		Vector3.new(-25, 1, -63),
		Vector3.new(25, 1, -63),
	}) do
		addSmoke(atmosphere, point, Vector3.new(8, 1, 8), Color3.fromRGB(120, 135, 155))
	end

	-- slow dust motes catching the lamp light across the whole hall
	if CONFIG.Particles then
		local emitterPart = part(atmosphere, "DustEmitter", Vector3.new(170, 1, 130), Vector3.new(0, 24, 0), COLORS.White, Enum.Material.SmoothPlastic, NOFX)
		emitterPart.Transparency = 1

		local dust = Instance.new("ParticleEmitter")
		dust.Name = "DustMotes"
		dust.Color = ColorSequence.new(COLORS.Warm)
		dust.LightEmission = 0.6
		dust.Size = NumberSequence.new(0.14)
		dust.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.55),
			NumberSequenceKeypoint.new(0.75, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		dust.Lifetime = NumberRange.new(9, 13)
		dust.Speed = NumberRange.new(0.6, 1.6)
		dust.Rate = 12
		dust.SpreadAngle = Vector2.new(180, 180)
		dust.EmissionDirection = Enum.NormalId.Bottom
		dust.Parent = emitterPart
	end
end

local function buildWallDetails(lobby)
	local details = Instance.new("Folder")
	details.Name = "WallDetails"
	details.Parent = lobby

	-- Interior face of every wall is local -Z, matching buildWall.
	local walls = {
		{ CFrame.new(0, 0, -71) * CFrame.Angles(0, math.pi, 0), 180, { -72, 72 } },
		{ CFrame.new(0, 0, 71), 180, { -48, -24, 0, 24 } },
		{ CFrame.new(91, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 140, { -24, 24 } },
		{ CFrame.new(-91, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), 140, { -24, 24 } },
	}

	for _, wall in ipairs(walls) do
		local placement, length, bannerSlots = wall[1], wall[2], wall[3]

		-- twin utility pipes with brackets and color-coded bands
		for index, pipe in ipairs({
			{ y = 17, color = COLORS.Metal, band = COLORS.Blue },
			{ y = 15.8, color = COLORS.Dark, band = COLORS.Red },
		}) do
			cyl(details, "WallPipe", Vector3.new(length - 4, 0.7, 0.7), placement * CFrame.new(0, pipe.y, -2.4), pipe.color, Enum.Material.Metal)
			for step = 0, math.floor((length - 16) / 12) do
				local x = -length / 2 + 8 + step * 12
				part(details, "PipeBracket", Vector3.new(0.5, 1.4, 0.9), placement * CFrame.new(x, pipe.y, -2.1), COLORS.Dark, Enum.Material.Metal, NOFX)
				if index == 1 and step % 2 == 0 then
					cyl(details, "PipeBand", Vector3.new(0.5, 0.85, 0.85), placement * CFrame.new(x + 6, pipe.y, -2.4), pipe.band, Enum.Material.Neon, NOFX)
				end
			end
		end

		-- hanging faction banners
		for _, x in ipairs(bannerSlots) do
			local banner = part(details, "Banner", Vector3.new(5, 10, 0.15), placement * CFrame.new(x, 8.6, -2.3), Color3.fromRGB(28, 36, 48), Enum.Material.Fabric)
			part(details, "BannerRod", Vector3.new(6.2, 0.35, 0.35), placement * CFrame.new(x, 13.8, -2.3), COLORS.Metal, Enum.Material.Metal, NOFX)
			part(details, "BannerTrim", Vector3.new(5, 0.3, 0.2), placement * CFrame.new(x, 3.7, -2.35), COLORS.Blue, Enum.Material.Neon, NOFX)

			local gui = Instance.new("SurfaceGui")
			gui.Name = "Emblem"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.LightInfluence = 0.3
			gui.Parent = banner

			local mark = Instance.new("TextLabel")
			mark.Name = "Mark"
			mark.BackgroundTransparency = 1
			mark.Size = UDim2.fromScale(0.8, 0.3)
			mark.Position = UDim2.fromScale(0.1, 0.25)
			mark.Text = "LH"
			mark.TextColor3 = COLORS.Blue
			mark.TextScaled = true
			mark.Font = Enum.Font.GothamBlack
			mark.Parent = gui

			local caption = Instance.new("TextLabel")
			caption.Name = "Caption"
			caption.BackgroundTransparency = 1
			caption.Size = UDim2.fromScale(0.8, 0.07)
			caption.Position = UDim2.fromScale(0.1, 0.6)
			caption.Text = "HOLD THE LINE"
			caption.TextColor3 = COLORS.White
			caption.TextTransparency = 0.2
			caption.TextScaled = true
			caption.Font = Enum.Font.GothamBold
			caption.Parent = gui
		end
	end
end

local function buildFloorMarkings(lobby)
	local markings = Instance.new("Folder")
	markings.Name = "FloorMarkings"
	markings.Parent = lobby

	-- stencils flanking the spawn lane, readable when walking from spawn toward the hub
	for _, stencil in ipairs({
		{ x = -10, text = "SAFE ZONE", color = COLORS.Green },
		{ x = 10, text = "STAY ALERT", color = COLORS.Hazard },
	}) do
		local pad = part(markings, "Stencil", Vector3.new(11, 0.05, 3.4), Vector3.new(stencil.x, 0.11, 31), COLORS.Dark, Enum.Material.SmoothPlastic, NOFX)
		pad.Transparency = 1

		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Top
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.5
		gui.Parent = pad

		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.fromScale(1, 1)
		text.Text = stencil.text
		text.TextColor3 = stencil.color
		text.TextTransparency = 0.25
		text.TextScaled = true
		text.Font = Enum.Font.GothamBlack
		text.Parent = gui
	end

	-- hazard-striped boundary around the command hub
	local segments = 40
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		part(
			markings,
			"HubHazard",
			Vector3.new(1.2, 0.06, 3.4),
			CFrame.Angles(0, a, 0) * CFrame.new(21.4, 0.53, 0),
			(i % 2 == 0) and COLORS.Hazard or COLORS.Dark,
			Enum.Material.Metal,
			NOFX
		)
	end
end

--------------------------------------------------------------------------------
-- Arrival
--------------------------------------------------------------------------------

local function buildArrivalGate(lobby)
	local gate = Instance.new("Model")
	gate.Name = "ArrivalGate"
	gate.Parent = lobby

	local z = 59
	part(gate, "ArrivalDeck", Vector3.new(34, 0.5, 11), Vector3.new(0, 0.25, z), COLORS.Metal, Enum.Material.Metal)
	part(gate, "ArrivalInlay", Vector3.new(30, 0.06, 9), Vector3.new(0, 0.54, z), COLORS.Floor, Enum.Material.SmoothPlastic, NOFX)

	for _, side in ipairs({ -1, 1 }) do
		local x = side * 13.5
		part(gate, "GateFoot", Vector3.new(5.5, 1.2, 5.5), Vector3.new(x, 0.8, z), COLORS.Dark, Enum.Material.Metal)
		part(gate, "GatePillar", Vector3.new(2.8, 12, 3.2), Vector3.new(x, 7.2, z), COLORS.Wall, Enum.Material.Metal)
		part(gate, "GatePillarFace", Vector3.new(1.8, 9.5, 0.25), Vector3.new(x, 7.2, z - 1.7), COLORS.Metal, Enum.Material.Metal)

		local strip = part(
			gate,
			"GatePillarGlow",
			Vector3.new(0.35, 8.5, 0.3),
			Vector3.new(x, 7.6, z - 1.9),
			COLORS.Green,
			Enum.Material.Neon,
			NOFX
		)
		addLight(strip, COLORS.Green, 2.1, 24, 0.2, 1.6)
		disc(gate, "GateBeaconRing", 4.8, 0.28, Vector3.new(x, 13.5, z), COLORS.Green, Enum.Material.Neon, NOFX)
		local beacon = part(gate, "GateBeacon", Vector3.new(1.4, 1.4, 1.4), Vector3.new(x, 14.6, z), COLORS.White, Enum.Material.Neon, NOFX)
		beacon.Shape = Enum.PartType.Ball
		addLight(beacon, COLORS.Green, 1.8, 30, 0.5, 2.4)
	end

	part(gate, "GateHeader", Vector3.new(30, 3, 3.2), Vector3.new(0, 13.2, z), COLORS.Metal, Enum.Material.Metal)
	part(gate, "GateHeaderGlow", Vector3.new(29, 0.3, 0.25), Vector3.new(0, 11.55, z - 1.75), COLORS.Green, Enum.Material.Neon, NOFX)
	makeSign(
		gate,
		"ArrivalSign",
		CFrame.new(0, 13.35, z - 1.72),
		Vector3.new(24, 2.4, 0.3),
		"LAST HOUSE",
		nil,
		COLORS.White
	)

	for _, x in ipairs({ -6, -3, 0, 3, 6 }) do
		part(
			gate,
			"ArrivalGuide",
			Vector3.new(1.8, 0.06, 0.24),
			CFrame.new(x, 0.62, z - 4.1) * CFrame.Angles(0, math.rad(x < 0 and 35 or -35), 0),
			COLORS.Green,
			Enum.Material.Neon,
			NOFX
		)
	end
end

local function buildSpawn(lobby)
	local pos = Vector3.new(0, 0, 46)

	disc(lobby, "SpawnPad", 16, 0.4, pos + Vector3.new(0, 0.2, 0), COLORS.Metal, Enum.Material.Metal)
	makeRing(lobby, "SpawnRingOuter", CFrame.new(pos + Vector3.new(0, 0.5, 0)), 7, 32, 0.3, COLORS.Green)
	makeRing(lobby, "SpawnRingInner", CFrame.new(pos + Vector3.new(0, 0.5, 0)), 4.8, 24, 0.2, COLORS.Green)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.Position = pos + Vector3.new(0, 0.6, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Material = Enum.Material.Neon
	spawn.Color = COLORS.Green
	spawn.Transparency = 0.35
	spawn.Parent = lobby
	addLight(spawn, COLORS.Green, 1.5, 20, 0.15, 2)
end

--------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------

local function startAnimations()
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if not CONFIG.Animate then
		return
	end

	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock()

		for _, a in ipairs(animated) do
			if a.obj.Parent then
				local cf = a.base * CFrame.Angles(0, a.spin * t, 0)
				if a.bob then
					cf += Vector3.new(0, math.sin(t * a.bobSpeed + a.phase) * a.bob, 0)
				end
				a.obj:PivotTo(cf)
			end
		end

		for _, p in ipairs(pulses) do
			if p.light.Parent then
				p.light.Brightness = p.base * (1 + p.amp * math.sin(t * p.speed + p.phase))
			end
		end
	end)
end

function LobbyBuilder.Build()
	-- Clean up the previous build
	local oldLobby = Workspace:FindFirstChild("GeneratedLobby")
	if oldLobby then
		oldLobby:Destroy()
	end
	if connection then
		connection:Disconnect()
		connection = nil
	end
	table.clear(animated)
	table.clear(pulses)
	rng = Random.new(2026)

	local lobby = Instance.new("Folder")
	lobby.Name = "GeneratedLobby"
	lobby.Parent = Workspace

	-- Structure
	buildFloor(lobby)
	buildWall(lobby, "NorthWall", CFrame.new(0, 0, -71) * CFrame.Angles(0, math.pi, 0), 180, 2)
	buildWall(lobby, "SouthWall", CFrame.new(0, 0, 71), 180, 2)
	buildWall(lobby, "EastWall", CFrame.new(91, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 140, 2)
	buildWall(lobby, "WestWall", CFrame.new(-91, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0), 140, 2)

	if CONFIG.Skyline then
		buildSkyline(lobby)
	end
	buildTrusses(lobby)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			buildGuardTower(lobby, Vector3.new(sx * 82, 0, sz * 62))
		end
	end

	-- Center + paths
	buildHub(lobby)
	buildLane(lobby, Vector3.new(0, 0, 24), Vector3.new(0, 0, 38), COLORS.Green)
	for _, def in ipairs(STATIONS) do
		local dir = Vector3.new(def.pos.X, 0, def.pos.Z).Unit
		local from = dir * 22
		local to = Vector3.new(def.pos.X, 0, def.pos.Z) - dir * 17
		buildLane(lobby, from, to, def.color)
		makeStation(lobby, def)
	end
	buildSectorArchitecture(lobby)
	buildMatchBays(lobby)

	-- Props
	buildMilitary(lobby)
	buildPerimeterSigns(lobby)
	buildAtmosphericDetails(lobby)
	buildWallDetails(lobby)
	buildFloorMarkings(lobby)
	if CONFIG.ArrivalGate then
		buildArrivalGate(lobby)
	end
	buildSpawn(lobby)

	setupLighting()
	startAnimations()

	print("Project Last House lobby successfully generated!")
end

return LobbyBuilder