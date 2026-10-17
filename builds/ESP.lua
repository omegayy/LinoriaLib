local ESP = {}
ESP.__index = ESP

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

-- ============================================================================
--  Helpers
-- ============================================================================

-- Bounding box of a model, in world space. Uses the engine's own
-- GetBoundingBox (fast) and only falls back to manual work if it fails.
local function GetBoundingBox(Model)
	if typeof(Model) ~= "Instance" then
		return CFrame.new(), Vector3.new(3, 5, 1)
	end

	if Model:IsA("BasePart") then
		return Model.CFrame, Model.Size
	end

	local Ok, Cf, Sz = pcall(function()
		return Model:GetBoundingBox()
	end)

	if Ok and typeof(Cf) == "CFrame" and typeof(Sz) == "Vector3" then
		return Cf, Sz
	end

	local Primary = Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart")
	if Primary then
		return Primary.CFrame, Primary.Size
	end

	return CFrame.new(Model:GetPivot().Position), Vector3.new(3, 5, 1)
end

local function GetHumanoid(Model)
	if typeof(Model) ~= "Instance" then
		return nil
	end

	if Model:IsA("Model") then
		return Model:FindFirstChildWhichIsA("Humanoid")
	end

	if Model:IsA("Player") then
		local Char = Model.Character
		return Char and Char:FindFirstChildWhichIsA("Humanoid") or nil
	end

	return nil
end

local function GetRoot(Model)
	if typeof(Model) ~= "Instance" then
		return nil
	end

	if Model:IsA("Model") then
		return Model.PrimaryPart or Model:FindFirstChild("HumanoidRootPart") or Model:FindFirstChildWhichIsA("BasePart")
	end

	if Model:IsA("Player") then
		local Char = Model.Character
		if Char then
			return Char.PrimaryPart or Char:FindFirstChild("HumanoidRootPart") or Char:FindFirstChildWhichIsA("BasePart")
		end
	end

	return nil
end

local function GetChar(Model)
	if typeof(Model) ~= "Instance" then
		return nil
	end
	if Model:IsA("Player") then
		return Model.Character
	end
	if Model:IsA("Model") then
		return Model
	end
	return nil
end

-- Turns a health ratio into a green -> yellow -> red color
local function HealthColor(Ratio)
	return Color3.fromHSV(0.33 * math.clamp(Ratio, 0, 1), 0.85, 1)
end

-- ============================================================================
--  Setup
-- ============================================================================

function ESP.new(Options)
	Options = Options or {}
	local self = setmetatable({}, ESP)

	self.PlayersOnly = Options.PlayersOnly ~= false
	self.TeamCheck = Options.TeamCheck == true
	self.AliveCheck = Options.AliveCheck ~= false
	self.MaxDistance = Options.MaxDistance
	self.Color = Options.Color or Color3.new(0.8, 0.2, 0.2)
	self.OutlineColor = Options.OutlineColor or Color3.new(0, 0, 0)
	self.TextColor = Options.TextColor or Color3.new(1, 1, 1)
	self.ShowName = Options.ShowName ~= false
	self.ShowHealth = Options.ShowHealth == true
	self.ShowDistance = Options.ShowDistance == true
	self.ShowBox = Options.ShowBox ~= false
	self.ShowFill = Options.ShowFill == true
	self.ShowTracer = Options.ShowTracer == true

	self.Objects = {}
	self.Tracked = {}
	self.Connections = {}

	self.Folder = Options.Folder or Instance.new("Folder")
	self.Folder.Name = "ESP"

	-- Prefer a hidden container, fall back to PlayerGui
	local Ok, RootGui = pcall(function()
		return (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if not Ok or typeof(RootGui) ~= "Instance" then
		RootGui = LocalPlayer and LocalPlayer:FindFirstChildOfClass("PlayerGui")
	end
	if not RootGui and LocalPlayer then
		RootGui = LocalPlayer:WaitForChild("PlayerGui", 10)
	end

	self.Folder.Parent = RootGui

	self.TracerGui = Instance.new("ScreenGui")
	self.TracerGui.Name = "ESPTracers"
	self.TracerGui.IgnoreGuiInset = true
	self.TracerGui.ResetOnSpawn = false
	self.TracerGui.DisplayOrder = 999
	self.TracerGui.Parent = RootGui

	self.Running = false
	return self
end

function ESP:Set(Options)
	if not Options then return end

	if Options.Color ~= nil then self.Color = Options.Color end
	if Options.OutlineColor ~= nil then self.OutlineColor = Options.OutlineColor end
	if Options.TextColor ~= nil then self.TextColor = Options.TextColor end
	if Options.PlayersOnly ~= nil then self.PlayersOnly = Options.PlayersOnly end
	if Options.TeamCheck ~= nil then self.TeamCheck = Options.TeamCheck end
	if Options.AliveCheck ~= nil then self.AliveCheck = Options.AliveCheck end
	if Options.MaxDistance ~= nil then self.MaxDistance = Options.MaxDistance end
	if Options.ShowName ~= nil then self.ShowName = Options.ShowName end
	if Options.ShowHealth ~= nil then self.ShowHealth = Options.ShowHealth end
	if Options.ShowDistance ~= nil then self.ShowDistance = Options.ShowDistance end
	if Options.ShowBox ~= nil then self.ShowBox = Options.ShowBox end
	if Options.ShowFill ~= nil then self.ShowFill = Options.ShowFill end
	if Options.ShowTracer ~= nil then self.ShowTracer = Options.ShowTracer end
end

-- ============================================================================
--  Tracking (this is what draws the boxes on real players)
-- ============================================================================

function ESP:Add(Target, Overrides)
	Overrides = Overrides or {}

	local Key = typeof(Target) == "Instance" and Target.Name or tostring(Target)
	if self.Objects[Key] then
		return self.Objects[Key]
	end

	local Entry = {
		Target = Target,
		Enabled = true,
		Color = Overrides.Color or self.Color,
		Overrides = Overrides,
	}

	-- One BillboardGui per player, sized in STUDIES so it automatically
	-- scales with distance (that is what makes the box hug the character).
	local Main = Instance.new("BillboardGui")
	Main.Name = Key
	Main.Adornee = nil
	Main.AlwaysOnTop = true
	Main.Size = UDim2.fromScale(3.5, 5.5)
	Main.StudsOffsetWorldSpace = Vector3.zero
	Main.Enabled = false
	Main.Parent = self.Folder

	local Box = Instance.new("Frame")
	Box.Name = "Box"
	Box.BackgroundTransparency = 1
	Box.Size = UDim2.fromScale(1, 1)
	Box.Visible = self.ShowBox
	Box.Parent = Main

	local BoxStroke = Instance.new("UIStroke")
	BoxStroke.Color = self.OutlineColor
	BoxStroke.Thickness = 2
	BoxStroke.Parent = Box

	local BoxFill = Instance.new("Frame")
	BoxFill.Name = "Fill"
	BoxFill.BackgroundColor3 = Entry.Color
	BoxFill.BackgroundTransparency = 0.85
	BoxFill.BorderSizePixel = 0
	BoxFill.Size = UDim2.fromScale(1, 1)
	BoxFill.Visible = self.ShowFill
	BoxFill.ZIndex = 1
	BoxFill.Parent = Box

	-- Name sits on top of the box, health + distance below it.
	-- Text is pixel-sized so it stays readable at any distance.
	local Name = Instance.new("TextLabel")
	Name.Name = "Name"
	Name.BackgroundTransparency = 1
	Name.AnchorPoint = Vector2.new(0.5, 1)
	Name.Position = UDim2.new(0.5, 0, 0, -3)
	Name.Size = UDim2.new(1, 40, 0, 15)
	Name.Font = Enum.Font.GothamBold
	Name.TextSize = 14
	Name.TextColor3 = self.TextColor
	Name.TextStrokeTransparency = 0.4
	Name.TextXAlignment = Enum.TextXAlignment.Center
	Name.TextTruncate = Enum.TextTruncate.AtEnd
	Name.Text = Overrides.Name or Key
	Name.Visible = self.ShowName
	Name.ZIndex = 2
	Name.Parent = Main

	local HealthBar = Instance.new("Frame")
	HealthBar.Name = "HealthBar"
	HealthBar.BackgroundColor3 = Color3.new(0, 0, 0)
	HealthBar.BackgroundTransparency = 0.35
	HealthBar.BorderSizePixel = 0
	HealthBar.AnchorPoint = Vector2.new(1, 0.5)
	HealthBar.Position = UDim2.new(0, -3, 0.5, 0)
	HealthBar.Size = UDim2.new(0, 3, 1, 0)
	HealthBar.Visible = self.ShowHealth
	HealthBar.ZIndex = 1
	HealthBar.Parent = Main

	local HealthFill = Instance.new("Frame")
	HealthFill.Name = "HealthFill"
	HealthFill.BackgroundColor3 = Color3.fromRGB(90, 220, 110)
	HealthFill.BorderSizePixel = 0
	HealthFill.AnchorPoint = Vector2.new(0, 1)
	HealthFill.Position = UDim2.fromScale(0, 1)
	HealthFill.Size = UDim2.fromScale(1, 1)
	HealthFill.ZIndex = 2
	HealthFill.Parent = HealthBar

	local Health = Instance.new("TextLabel")
	Health.Name = "Health"
	Health.BackgroundTransparency = 1
	Health.AnchorPoint = Vector2.new(0.5, 0)
	Health.Position = UDim2.new(0.5, 0, 1, 2)
	Health.Size = UDim2.new(1, 40, 0, 13)
	Health.Font = Enum.Font.Gotham
	Health.TextSize = 12
	Health.TextColor3 = self.TextColor
	Health.TextStrokeTransparency = 0.4
	Health.TextXAlignment = Enum.TextXAlignment.Center
	Health.Text = "HP: -"
	Health.Visible = self.ShowHealth
	Health.ZIndex = 2
	Health.Parent = Main

	local Dist = Instance.new("TextLabel")
	Dist.Name = "Dist"
	Dist.BackgroundTransparency = 1
	Dist.AnchorPoint = Vector2.new(0.5, 0)
	Dist.Position = UDim2.new(0.5, 0, 1, 16)
	Dist.Size = UDim2.new(1, 40, 0, 13)
	Dist.Font = Enum.Font.Gotham
	Dist.TextSize = 12
	Dist.TextColor3 = self.TextColor
	Dist.TextStrokeTransparency = 0.4
	Dist.TextXAlignment = Enum.TextXAlignment.Center
	Dist.Text = "[0m]"
	Dist.Visible = self.ShowDistance
	Dist.ZIndex = 2
	Dist.Parent = Main

	local Tracer = Instance.new("Frame")
	Tracer.Name = "Tracer"
	Tracer.BackgroundColor3 = Entry.Color
	Tracer.BorderSizePixel = 0
	Tracer.AnchorPoint = Vector2.new(0.5, 0.5)
	Tracer.Size = UDim2.fromOffset(0, 1)
	Tracer.Visible = false
	Tracer.Parent = self.TracerGui

	Entry.Gui = Main
	Entry.Box = Box
	Entry.BoxStroke = BoxStroke
	Entry.BoxFill = BoxFill
	Entry.NameLabel = Name
	Entry.HealthBar = HealthBar
	Entry.HealthFill = HealthFill
	Entry.HealthLabel = Health
	Entry.DistLabel = Dist
	Entry.Tracer = Tracer

	self.Objects[Key] = Entry
	return Entry
end

function ESP:Remove(Target)
	local Key = typeof(Target) == "Instance" and Target.Name or tostring(Target)
	local Entry = self.Objects[Key]
	if not Entry then return end

	if Entry.Gui then Entry.Gui:Destroy() end
	if Entry.Tracer then Entry.Tracer:Destroy() end
	self.Objects[Key] = nil
end

function ESP:Clear()
	for _, Entry in next, self.Objects do
		if Entry.Gui then Entry.Gui:Destroy() end
		if Entry.Tracer then Entry.Tracer:Destroy() end
	end
	table.clear(self.Objects)
end

function ESP:TrackPlayers()
	self:Clear()

	local Camera = workspace.CurrentCamera

	for _, p in next, Players:GetPlayers() do
		if p ~= LocalPlayer then
			self:Add(p)
		end
	end

	if not self.Tracked._PlayerAdded then
		self.Tracked._PlayerAdded = Players.PlayerAdded:Connect(function(p)
			self:Add(p)
		end)
		table.insert(self.Connections, self.Tracked._PlayerAdded)
	end

	if not self.Tracked._PlayerRemoving then
		self.Tracked._PlayerRemoving = Players.PlayerRemoving:Connect(function(p)
			self:Remove(p)
		end)
		table.insert(self.Connections, self.Tracked._PlayerRemoving)
	end

	if self.Running then return end
	self.Running = true

	task.spawn(function()
		local Heartbeat = RunService.Heartbeat

		while self.Running do
			Heartbeat:Wait()
			Camera = workspace.CurrentCamera
			if not Camera then continue end

			for _, Entry in next, self.Objects do
				local Target = Entry.Target
				local Char = GetChar(Target)
				local Root = GetRoot(Target)
				local Hum = GetHumanoid(Target)

				local function Hide()
					if Entry.Gui then Entry.Gui.Enabled = false end
					if Entry.Tracer then Entry.Tracer.Visible = false end
				end

				-- character not spawned yet / already dead / turned off
				if not Char or not Root or not Hum or Entry.Enabled == false then
					Hide()
					continue
				end

				if self.AliveCheck and Hum.Health <= 0 then
					Hide()
					continue
				end

				-- hide team-mates when TeamCheck is on
				if self.TeamCheck and Target:IsA("Player") then
					local MyTeam = LocalPlayer and LocalPlayer.Team
					if MyTeam and Target.Team == MyTeam then
						Hide()
						continue
					end
				end

				-- distance limit (stud distance from our camera)
				local Distance = (Root.Position - Camera.CFrame.Position).Magnitude
				if self.MaxDistance and Distance > self.MaxDistance then
					Hide()
					continue
				end

				-- the box IS the character's bounding box, in studs, centered on it
				local BbCf, BbSize = GetBoundingBox(Char)
				local Center = BbCf.Position

				if Entry.Gui then
					Entry.Gui.Enabled = true
					Entry.Gui.Adornee = Root
					Entry.Gui.Size = UDim2.fromScale(math.max(BbSize.X, 1.2), math.max(BbSize.Y, 2))
					Entry.Gui.StudsOffsetWorldSpace = Center - Root.Position

					local Col = Entry.Color or self.Color

					if Entry.Box then
						Entry.Box.Visible = self.ShowBox
					end
					if Entry.BoxFill then
						Entry.BoxFill.Visible = self.ShowFill
						Entry.BoxFill.BackgroundColor3 = Col
					end
					if Entry.BoxStroke then
						Entry.BoxStroke.Color = self.OutlineColor
					end
					if Entry.NameLabel then
						Entry.NameLabel.Visible = self.ShowName
						Entry.NameLabel.TextColor3 = self.TextColor
						Entry.NameLabel.Text = Entry.Overrides.Name or Target.Name
					end
					if Entry.HealthBar and Entry.HealthFill then
						local Ratio = math.clamp(Hum.Health / math.max(Hum.MaxHealth, 1), 0, 1)
						Entry.HealthBar.Visible = self.ShowHealth
						Entry.HealthFill.Visible = self.ShowHealth
						Entry.HealthFill.Size = UDim2.fromScale(1, Ratio)
						Entry.HealthFill.BackgroundColor3 = HealthColor(Ratio)
					end
					if Entry.HealthLabel then
						Entry.HealthLabel.Visible = self.ShowHealth
						Entry.HealthLabel.TextColor3 = self.TextColor
						Entry.HealthLabel.Text = string.format("HP: %d/%d", math.floor(Hum.Health + 0.5), math.floor(Hum.MaxHealth + 0.5))
					end
					if Entry.DistLabel then
						Entry.DistLabel.Visible = self.ShowDistance
						Entry.DistLabel.TextColor3 = self.TextColor
						Entry.DistLabel.Text = string.format("[%dm]", math.floor(Distance + 0.5))
					end
				end

				-- Tracer: WorldToViewportPoint already returns PIXELS, no scaling needed
				if Entry.Tracer then
					local V, OnScreen = Camera:WorldToViewportPoint(Root.Position)

					if self.ShowTracer and OnScreen then
						local Abs = self.TracerGui.AbsoluteSize
						local Origin = Vector2.new(Abs.X * 0.5, Abs.Y)
						local TargetPt = Vector2.new(V.X, V.Y)
						local Delta = TargetPt - Origin
						local Len = Delta.Magnitude

						if Len > 1 then
							local Mid = (Origin + TargetPt) * 0.5
							Entry.Tracer.Visible = true
							Entry.Tracer.BackgroundColor3 = Entry.Color or self.Color
							Entry.Tracer.Position = UDim2.fromOffset(Mid.X, Mid.Y)
							Entry.Tracer.Size = UDim2.fromOffset(Len, 1)
							Entry.Tracer.Rotation = math.deg(math.atan2(Delta.Y, Delta.X))
						else
							Entry.Tracer.Visible = false
						end
					else
						Entry.Tracer.Visible = false
					end
				end
			end
		end
	end)
end

function ESP:Stop()
	self.Running = false
end

function ESP:Destroy()
	self:Stop()
	self:Clear()

	for _, c in next, self.Connections do
		pcall(function() c:Disconnect() end)
	end
	table.clear(self.Connections)

	if self.TracerGui then
		self.TracerGui:Destroy()
	end
	if self.Folder then
		self.Folder:Destroy()
	end
end

-- ============================================================================
--  Preview — clones YOUR OWN avatar in a basic pose and shows it in a box
-- ============================================================================

function ESP:Preview(Parent)
	local Container = Parent
	if not Container then
		Container = Instance.new("Frame")
		Container.Name = "ESPPreviewContainer"
		Container.BackgroundTransparency = 1
		Container.Size = UDim2.fromScale(1, 1)
	end

	local Viewport = Instance.new("ViewportFrame")
	Viewport.Name = "ESP_Preview"
	Viewport.Size = UDim2.fromScale(1, 1)
	Viewport.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
	Viewport.Ambient = Color3.fromRGB(150, 150, 150)
	Viewport.LightColor = Color3.fromRGB(255, 255, 255)
	Viewport.LightDirection = Vector3.new(-0.7, 0.6, -0.3)
	Viewport.CurrentCamera = Instance.new("Camera")
	Viewport.CurrentCamera.FieldOfView = 40
	Viewport.Parent = Container

	local Camera = Viewport.CurrentCamera
	Camera.Parent = Viewport

	-- Preview state, filled in once the avatar is ready
	local PreviewModel = nil
	local PreviewHeight = 5.4
	local PreviewBase = CFrame.new(0, 2.75, 0)

	-- Strips behaviour + physics, clears every joint back to the basic pose
	local function NeutralizeClone(Clone)
		for _, Obj in next, Clone:GetDescendants() do
			if Obj:IsA("BaseScript") or Obj:IsA("Script") or Obj:IsA("LocalScript") or Obj:IsA("ModuleScript") then
				Obj:Destroy()
			elseif Obj:IsA("Animator") then
				Obj:Destroy()
			elseif Obj:IsA("ParticleEmitter") or Obj:IsA("Fire") or Obj:IsA("Smoke") or Obj:IsA("Light") then
				Obj:Destroy()
			elseif Obj:IsA("BasePart") then
				Obj.Anchored = true
				Obj.CanCollide = false
				Obj.CanTouch = false
				Obj.CanQuery = false
				Obj.Massless = true
			end
		end

		-- Zero out every joint transform -> the default (basic) pose
		for _, Obj in next, Clone:GetDescendants() do
			if Obj:IsA("Motor6D") then
				Obj.Transform = CFrame.new()
			end
		end

		local Hum = Clone:FindFirstChildWhichIsA("Humanoid")
		if Hum then
			Hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			Hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end

		Clone.Name = "PreviewAvatar"
	end

	local function InstallAvatar(Clone)
		NeutralizeClone(Clone)
		Clone.Parent = Viewport

		local Ok, _, Sz = pcall(function() return Clone:GetBoundingBox() end)
		if Ok and typeof(Sz) == "Vector3" and Sz.Y > 0.5 then
			PreviewHeight = Sz.Y
		end

		PreviewBase = CFrame.new(0, PreviewHeight / 2 + 0.05, 0)
		Clone:PivotTo(PreviewBase)
		PreviewModel = Clone
	end

	-- Last resort if the avatar can't be cloned: a plain block dummy
	local function MakeBlockDummy()
		local Model = Instance.new("Model")
		Model.Name = "PreviewDummy"

		local function MakePart(Name, Size, Offset, Color)
			local Part = Instance.new("Part")
			Part.Name = Name
			Part.Size = Size
			Part.CFrame = CFrame.new(Offset)
			Part.Anchored = true
			Part.Color = Color
			Part.Material = Enum.Material.SmoothPlastic
			Part.Parent = Model
			return Part
		end

		MakePart("UpperTorso", Vector3.new(2, 2, 1), Vector3.new(0, 0, 0), Color3.fromRGB(75, 110, 200))
		MakePart("LowerTorso", Vector3.new(2, 0.6, 1), Vector3.new(0, -0.35, 0), Color3.fromRGB(75, 110, 200))
		MakePart("Head", Vector3.new(1, 1, 1), Vector3.new(0, 1.5, 0), Color3.fromRGB(245, 215, 175))
		MakePart("LeftArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(-1.4, 0.1, 0), Color3.fromRGB(75, 110, 200))
		MakePart("RightArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(1.4, 0.1, 0), Color3.fromRGB(75, 110, 200))
		MakePart("LeftLeg", Vector3.new(0.8, 1.8, 0.8), Vector3.new(-0.45, -1.4, 0), Color3.fromRGB(45, 70, 140))
		MakePart("RightLeg", Vector3.new(0.8, 1.8, 0.8), Vector3.new(0.45, -1.4, 0), Color3.fromRGB(45, 70, 140))

		Model.PrimaryPart = Model:FindFirstChild("UpperTorso")
		return Model
	end

	-- Build the avatar in the background (cloning + description calls can yield)
	task.spawn(function()
		-- 1) our actual in-game character, frozen in a basic pose
		local Char = LocalPlayer and LocalPlayer.Character
		if typeof(Char) == "Instance" then
			Char.Archivable = true
			local Ok, Clone = pcall(function() return Char:Clone() end)
			if Ok and typeof(Clone) == "Instance" then
				InstallAvatar(Clone)
				return
			end
		end

		-- 2) no character? build it from our account's appearance
		if LocalPlayer then
			local OkDesc, Desc = pcall(function()
				return Players:GetHumanoidDescriptionFromUserId(LocalPlayer.UserId)
			end)
			if OkDesc and typeof(Desc) == "Instance" then
				local OkModel, Made = pcall(function()
					return Players:CreateHumanoidModelFromDescription(Desc, Enum.HumanoidRigType.R15)
				end)
				if OkModel and typeof(Made) == "Instance" then
					InstallAvatar(Made)
					return
				end
			end
		end

		-- 3) plain block dummy
		InstallAvatar(MakeBlockDummy())
	end)

	-- The ESP overlay itself, drawn with plain Frames so it works everywhere
	local Overlay = Instance.new("Frame")
	Overlay.Name = "ESP_Preview_Overlay"
	Overlay.BackgroundTransparency = 1
	Overlay.Size = UDim2.fromScale(1, 1)
	Overlay.Parent = Container

	local Box = Instance.new("Frame")
	Box.Name = "Box"
	Box.BackgroundTransparency = 1
	Box.BorderSizePixel = 0
	Box.Visible = self.ShowBox ~= false
	Box.ZIndex = 2
	Box.Parent = Overlay

	local BoxOutline = Instance.new("UIStroke")
	BoxOutline.Color = self.OutlineColor
	BoxOutline.Thickness = 2
	BoxOutline.Parent = Box

	local Fill = Instance.new("Frame")
	Fill.Name = "Fill"
	Fill.BackgroundColor3 = self.Color
	Fill.BackgroundTransparency = 0.85
	Fill.Size = UDim2.fromScale(1, 1)
	Fill.BorderSizePixel = 0
	Fill.Visible = self.ShowFill == true
	Fill.ZIndex = 1
	Fill.Parent = Box

	local NameLabel = Instance.new("TextLabel")
	NameLabel.Name = "Name"
	NameLabel.BackgroundTransparency = 1
	NameLabel.Font = Enum.Font.GothamBold
	NameLabel.TextSize = 13
	NameLabel.TextColor3 = self.TextColor
	NameLabel.TextStrokeTransparency = 0.5
	NameLabel.TextXAlignment = Enum.TextXAlignment.Center
	NameLabel.AnchorPoint = Vector2.new(0.5, 1)
	NameLabel.Size = UDim2.new(0, 200, 0, 14)
	NameLabel.Visible = self.ShowName ~= false
	NameLabel.ZIndex = 3
	NameLabel.Parent = Overlay

	local HealthBar = Instance.new("Frame")
	HealthBar.Name = "HealthBar"
	HealthBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	HealthBar.BackgroundTransparency = 0.4
	HealthBar.BorderSizePixel = 0
	HealthBar.AnchorPoint = Vector2.new(1, 0.5)
	HealthBar.Size = UDim2.new(0, 4, 1, 0)
	HealthBar.Visible = self.ShowHealth ~= false
	HealthBar.ZIndex = 2
	HealthBar.Parent = Overlay

	local HealthFill = Instance.new("Frame")
	HealthFill.BackgroundColor3 = Color3.fromRGB(80, 220, 100)
	HealthFill.BorderSizePixel = 0
	HealthFill.AnchorPoint = Vector2.new(0, 1)
	HealthFill.Position = UDim2.fromScale(0, 1)
	HealthFill.Size = UDim2.fromScale(1, 0.76)
	HealthFill.ZIndex = 3
	HealthFill.Parent = HealthBar

	local DistLabel = Instance.new("TextLabel")
	DistLabel.Name = "Distance"
	DistLabel.BackgroundTransparency = 1
	DistLabel.Font = Enum.Font.Gotham
	DistLabel.TextSize = 12
	DistLabel.TextColor3 = self.TextColor
	DistLabel.TextStrokeTransparency = 0.5
	DistLabel.TextXAlignment = Enum.TextXAlignment.Center
	DistLabel.AnchorPoint = Vector2.new(0.5, 0)
	DistLabel.Size = UDim2.new(0, 200, 0, 14)
	DistLabel.Visible = self.ShowDistance ~= false
	DistLabel.ZIndex = 3
	DistLabel.Parent = Overlay

	local Tracer = Instance.new("Frame")
	Tracer.Name = "Tracer"
	Tracer.BackgroundColor3 = self.Color
	Tracer.BorderSizePixel = 0
	Tracer.AnchorPoint = Vector2.new(0.5, 0.5)
	Tracer.Size = UDim2.fromOffset(0, 1)
	Tracer.Visible = false
	Tracer.ZIndex = 2
	Tracer.Parent = Overlay

	-- Perspective projection into the viewport, so the overlay tracks the avatar
	local function ProjectPoint(WorldPos)
		local Size = Viewport.AbsoluteSize
		local ObjectSpace = Camera.CFrame:PointToObjectSpace(WorldPos)
		if ObjectSpace.Z >= 0 then
			return nil
		end

		local HalfHeight = -ObjectSpace.Z * math.tan(math.rad(Camera.FieldOfView) / 2)
		local HalfWidth = HalfHeight * (Size.X / Size.Y)
		return Vector2.new(
			(ObjectSpace.X / HalfWidth + 1) / 2 * Size.X,
			(1 - ObjectSpace.Y / HalfHeight) / 2 * Size.Y
		)
	end

	local function HideEverything()
		Box.Visible = false
		NameLabel.Visible = false
		HealthBar.Visible = false
		DistLabel.Visible = false
		Tracer.Visible = false
	end

	local PreviewName = (LocalPlayer and LocalPlayer.DisplayName) or "Preview"

	local Connection
	Connection = RunService.Heartbeat:Connect(function()
		local Size = Viewport.AbsoluteSize
		if Size.X < 12 or Size.Y < 12 then
			HideEverything()
			return
		end

		-- camera frames whatever avatar is loaded (cloning can still be in flight)
		Camera.CFrame = CFrame.lookAt(
			Vector3.new(0, PreviewHeight * 0.62, 9.5),
			Vector3.new(0, PreviewHeight * 0.5, 0)
		)

		if not PreviewModel then
			HideEverything()
			return
		end

		-- slow spin so the ESP overlay moves around a bit too
		local Angle = os.clock() % 8 / 8 * (math.pi * 2)
		PreviewModel:PivotTo(PreviewBase * CFrame.Angles(0, Angle, 0))

		local Center = PreviewModel:GetPivot().Position
		local TopPoint = ProjectPoint(Center + Vector3.new(0, PreviewHeight / 2 + 0.4, 0))
		local BottomPoint = ProjectPoint(Center - Vector3.new(0, PreviewHeight / 2 + 0.6, 0))

		if not TopPoint or not BottomPoint then
			HideEverything()
			return
		end

		local Height = math.max(BottomPoint.Y - TopPoint.Y, 8)
		local Width = Height / 2.6
		local MidX = (TopPoint.X + BottomPoint.X) / 2
		local MidY = (TopPoint.Y + BottomPoint.Y) / 2

		Box.Visible = self.ShowBox ~= false
		Box.Size = UDim2.fromOffset(Width, Height)
		Box.Position = UDim2.fromOffset(MidX - Width / 2, MidY - Height / 2)
		BoxOutline.Color = self.OutlineColor
		Fill.BackgroundColor3 = self.Color

		NameLabel.Visible = self.ShowName ~= false
		NameLabel.Text = PreviewName
		NameLabel.Position = UDim2.fromOffset(MidX, MidY - Height / 2 - 2)
		NameLabel.TextColor3 = self.TextColor

		HealthBar.Visible = self.ShowHealth ~= false
		HealthBar.Position = UDim2.fromOffset(MidX - Width / 2 - 7, MidY)
		HealthBar.Size = UDim2.new(0, 4, 0, Height)
		HealthFill.Size = UDim2.fromScale(1, 0.76)

		DistLabel.Visible = self.ShowDistance ~= false
		DistLabel.Text = "[128m]"
		DistLabel.Position = UDim2.fromOffset(MidX, MidY + Height / 2 + 2)
		DistLabel.TextColor3 = self.TextColor

		-- tracer from the bottom-centre of the preview up to the box
		if self.ShowTracer then
			local Origin = Vector2.new(Size.X * 0.5, Size.Y)
			local TargetPt = Vector2.new(MidX, MidY + Height / 2)
			local Delta = TargetPt - Origin
			local Len = Delta.Magnitude

			if Len > 1 then
				local Mid = (Origin + TargetPt) * 0.5
				Tracer.Visible = true
				Tracer.BackgroundColor3 = self.Color
				Tracer.Position = UDim2.fromOffset(Mid.X, Mid.Y)
				Tracer.Size = UDim2.fromOffset(Len, 1)
				Tracer.Rotation = math.deg(math.atan2(Delta.Y, Delta.X))
			else
				Tracer.Visible = false
			end
		else
			Tracer.Visible = false
		end
	end)

	return {
		Viewport = Viewport,
		Overlay = Overlay,
		Cleanup = function()
			if Connection then
				Connection:Disconnect()
			end
			if Overlay then
				Overlay:Destroy()
			end
			if Viewport then
				Viewport:Destroy()
			end
			if not Parent and Container ~= Parent then
				Container:Destroy()
			end
		end,
		ESP = {
			Box = Box;
			BoxFill = Fill;
			NameLabel = NameLabel;
			HealthLabel = HealthBar;
			DistLabel = DistLabel;
			Tracer = Tracer;
			Color = self.Color;
		},
	}
end

return ESP
