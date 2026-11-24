local Lighting = game:GetService("Lighting")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

-- Higher quality levels render neon and bloom much hotter, so the lobby is
-- tuned down progressively. LOW is the baseline LobbyBuilder generates.
local LOW = {
	Brightness = 1.55,
	Exposure = 0.05,
	BloomIntensity = 0.42,
	BloomSize = 22,
	BloomThreshold = 1.25,
	Saturation = 0.14,
	Contrast = 0.08,
	SunRays = 0.04,
}

local MAX = {
	Brightness = 1.05,
	Exposure = -0.4,
	BloomIntensity = 0.14,
	BloomSize = 12,
	BloomThreshold = 2,
	Saturation = 0.08,
	Contrast = 0.05,
	SunRays = 0.01,
}

local SAVED_MAX = 10 -- graphics menu slider (1-10)
local RENDER_MAX = 21 -- engine render quality (1-21), used when set to Automatic

local applying = false

-- Returns 0 (lowest quality) .. 1 (maximum quality)
local function getQualityAlpha()
	local saved = UserGameSettings.SavedQualityLevel.Value
	if saved > 0 then
		return math.clamp((saved - 1) / (SAVED_MAX - 1), 0, 1)
	end

	local ok, level = pcall(function()
		return settings().Rendering.QualityLevel.Value
	end)
	if ok and level and level > 0 then
		return math.clamp((level - 1) / (RENDER_MAX - 1), 0, 1)
	end

	return 0.5
end

local function blend(key, alpha)
	return LOW[key] + (MAX[key] - LOW[key]) * alpha
end

local function apply()
	if applying then
		return
	end
	applying = true

	local alpha = getQualityAlpha()

	Lighting.Brightness = blend("Brightness", alpha)
	Lighting.ExposureCompensation = blend("Exposure", alpha)

	local bloom = Lighting:FindFirstChild("LobbyFX_Bloom")
	if bloom then
		bloom.Intensity = blend("BloomIntensity", alpha)
		bloom.Size = blend("BloomSize", alpha)
		bloom.Threshold = blend("BloomThreshold", alpha)

		-- The legacy Bloom stacks on top of the lobby bloom and blows out neon.
		local legacy = Lighting:FindFirstChild("Bloom")
		if legacy and legacy:IsA("BloomEffect") then
			legacy.Enabled = false
		end
	end

	local color = Lighting:FindFirstChild("LobbyFX_Color")
	if color then
		color.Saturation = blend("Saturation", alpha)
		color.Contrast = blend("Contrast", alpha)
	end

	local rays = Lighting:FindFirstChild("LobbyFX_Rays")
	if rays then
		rays.Intensity = blend("SunRays", alpha)
	end

	applying = false
end

apply()

pcall(function()
	settings().Rendering:GetPropertyChangedSignal("QualityLevel"):Connect(apply)
end)
UserGameSettings:GetPropertyChangedSignal("SavedQualityLevel"):Connect(apply)

-- The server builds the lobby effects after the client may have started.
Lighting.ChildAdded:Connect(function()
	task.defer(apply)
end)
Lighting:GetPropertyChangedSignal("Brightness"):Connect(apply)
Lighting:GetPropertyChangedSignal("ExposureCompensation"):Connect(apply)
