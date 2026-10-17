local ESP = {}
ESP.__index = ESP

local function GetBoundingBox(Model)
	if Model:IsA("BasePart") then
		return Model.CFrame, Model.Size
	end

	local Primary = Model.PrimaryPart or Model:FindFirstChildWhichIsA("BasePart")
	if not Primary then
		local Parts = Model:GetDescendants()
		local Min, Max = nil, nil

		for _, Inst in next, Parts do
			if Inst:IsA("BasePart") and Inst.CanCollide then
				local cf, sz = Inst.CFrame, Inst.Size
				local h = sz * 0.5
				local Points = {
					cf:PointToWorldSpace(Vector3.new(-h.X, -h.Y, -h.Z)),
					cf:PointToWorldSpace(Vector3.new(h.X, -h.Y, -h.Z)),
					cf:PointToWorldSpace(Vector3.new(-h.X, h.Y, -h.Z)),
					cf:PointToWorldSpace(Vector3.new(h.X, h.Y, -h.Z)),
					cf:PointToWorldSpace(Vector3.new(-h.X, -h.Y, h.Z)),
					cf:PointToWorldSpace(Vector3.new(h.X, -h.Y, h.Z)),
					cf:PointToWorldSpace(Vector3.new(-h.X, h.Y, h.Z)),
					cf:PointToWorldSpace(Vector3.new(h.X, h.Y, h.Z)),
				}

				for _, p in next, Points do
					local v = p
					if Min == nil then
						Min, Max = v, v
					else
						Min = Vector3.new(math.min(Min.X, v.X), math.min(Min.Y, v.Y), math.min(Min.Z, v.Z))
						Max = Vector3.new(math.max(Max.X, v.X), math.max(Max.Y, v.Y), math.max(Max.Z, v.Z))
					end
				end
			end
		end

		if not Min then
			return CFrame.new(Model:GetPivot().Position), Vector3.one
		end

		local Size = Max - Min
		local Cf = CFrame.new(Min:Lerp(Max, 0.5))
		return Cf, Size
	end

	return Primary.CFrame, Primary.Size
end

local function ProjectTo2D(Camera, TargetGui, WorldPos)
	if not Camera or not TargetGui or not WorldPos then
		return nil
	end

	local V = Camera:WorldToViewportPoint(WorldPos)
	if V.Z <= 0 then
		return nil
	end

	local Sz = TargetGui.AbsoluteSize
	return Vector2.new(V.X * Sz.X, V.Y * Sz.Y)
end

local function GetHumanoid(Model)
	if Model:IsA("Model") then
		local Hum = Model:FindFirstChildWhichIsA("Humanoid")
		if Hum then
			return Hum
		end
	end

	if Model:IsA("Player") then
		local Char = Model.Character
		if Char then
			return Char:FindFirstChildWhichIsA("Humanoid")
		end
	end

	return nil
end

local function GetRoot(Model)
	if Model:IsA("Model") then
		local Root = Model.PrimaryPart or Model:FindFirstChild("HumanoidRootPart") or Model:FindFirstChildWhichIsA("BasePart")
		if Root then
			return Root
		end
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
	if Model:IsA("Player") then
		return Model.Character
	end
	if Model:IsA("Model") then
		return Model
	end
	return nil
end

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
	if not self.Folder.Name then
		self.Folder.Name = "ESP"
	end

	local Ok, RootGui = pcall(function()
		return game:GetService("CoreGui")
	end)

	if not Ok then
		RootGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	end

	self.Folder.Name = "ESP"
	self.Folder.Parent = RootGui

	self.TracerGui = Instance.new("ScreenGui")
	self.TracerGui.Name = "ESPTracers"
	self.TracerGui.IgnoreGuiInset = true
	self.TracerGui.ResetOnSpawn = false
	self.TracerGui.DisplayOrder = 999
	self.TracerGui.Parent = self.Folder.Parent

	self.Running = false
	return self
end

function ESP:Set(Options)
	if not Options then return end
	self.Color = Options.Color or self.Color
	self.OutlineColor = Options.OutlineColor or self.OutlineColor
	self.TextColor = Options.TextColor or self.TextColor
	self.PlayersOnly = Options.PlayersOnly ~= nil and Options.PlayersOnly or self.PlayersOnly
	self.TeamCheck = Options.TeamCheck ~= nil and Options.TeamCheck or self.TeamCheck
	self.AliveCheck = Options.AliveCheck ~= nil and Options.AliveCheck or self.AliveCheck
	if Options.MaxDistance ~= nil then self.MaxDistance = Options.MaxDistance end
	if Options.ShowName ~= nil then self.ShowName = Options.ShowName end
	if Options.ShowHealth ~= nil then self.ShowHealth = Options.ShowHealth end
	if Options.ShowDistance ~= nil then self.ShowDistance = Options.ShowDistance end
	if Options.ShowBox ~= nil then self.ShowBox = Options.ShowBox end
	if Options.ShowFill ~= nil then self.ShowFill = Options.ShowFill end
	if Options.ShowTracer ~= nil then self.ShowTracer = Options.ShowTracer end
end

function ESP:Add(Target, Overrides)
	Overrides = Overrides or {}
	local Key = nil
	if typeof(Target) == "Instance" then
		Key = Target.Name
	else
		Key = tostring(Target)
	end

	if self.Objects[Key] then
		return self.Objects[Key]
	end

	local Entry = {}
	Entry.Target = Target
	Entry.Enabled = true
	Entry.Color = Overrides.Color or self.Color
	Entry.Overrides = Overrides

	local Main = Instance.new("BillboardGui")
	Main.Name = Key
	Main.Adornee = nil
	Main.AlwaysOnTop = true
	Main.Size = UDim2.new(0, 180, 0, 70)
	Main.StudsOffset = Vector3.new(0, 3, 0)
	Main.Parent = self.Folder

	local Box = Instance.new("Frame")
	Box.Name = "Box"
	Box.BackgroundTransparency = 1
	Box.Size = UDim2.new(1, -6, 1, -6)
	Box.Position = UDim2.new(0, 3, 0, 3)
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
	BoxFill.Size = UDim2.new(1, 0, 1, 0)
	BoxFill.Visible = self.ShowFill
	BoxFill.ZIndex = 1
	BoxFill.Parent = Box

	local Name = Instance.new("TextLabel")
	Name.Name = "Name"
	Name.BackgroundTransparency = 1
	Name.Position = UDim2.new(0, 5, 0, -18)
	Name.Size = UDim2.new(1, -10, 0, 16)
	Name.Font = Enum.Font.GothamBold
	Name.TextSize = 14
	Name.TextColor3 = self.TextColor
	Name.TextStrokeTransparency = 0.4
	Name.TextXAlignment = Enum.TextXAlignment.Left
	Name.Text = Overrides.Name or Key
	Name.Visible = self.ShowName
	Name.Parent = Main

	local Health = Instance.new("TextLabel")
	Health.Name = "Health"
	Health.BackgroundTransparency = 1
	Health.Position = UDim2.new(0, 5, 1, 2)
	Health.Size = UDim2.new(1, -10, 0, 12)
	Health.Font = Enum.Font.Gotham
	Health.TextSize = 12
	Health.TextColor3 = self.TextColor
	Health.TextStrokeTransparency = 0.4
	Health.TextXAlignment = Enum.TextXAlignment.Left
	Health.Text = "HP: -"
	Health.Visible = self.ShowHealth
	Health.Parent = Main

	local Dist = Instance.new("TextLabel")
	Dist.Name = "Dist"
	Dist.BackgroundTransparency = 1
	Dist.Position = UDim2.new(0, 5, 1, 16)
	Dist.Size = UDim2.new(1, -10, 0, 12)
	Dist.Font = Enum.Font.Gotham
	Dist.TextSize = 12
	Dist.TextColor3 = self.TextColor
	Dist.TextStrokeTransparency = 0.4
	Dist.TextXAlignment = Enum.TextXAlignment.Left
	Dist.Text = "[0m]"
	Dist.Visible = self.ShowDistance
	Dist.Parent = Main

	local Tracer = Instance.new("Frame")
	Tracer.Name = "Tracer"
	Tracer.BackgroundColor3 = Entry.Color
	Tracer.BorderSizePixel = 0
	Tracer.AnchorPoint = Vector2.new(0.5, 0.5)
	Tracer.Size = UDim2.new(0, 0, 0, 1)
	Tracer.Visible = self.ShowTracer
	Tracer.ZIndex = 0
	Tracer.Parent = self.TracerGui

	Entry.Gui = Main
	Entry.Box = Box
	Entry.BoxStroke = BoxStroke
	Entry.BoxFill = BoxFill
	Entry.NameLabel = Name
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
	for Key, Entry in next, self.Objects do
		if Entry.Gui then Entry.Gui:Destroy() end
		if Entry.Tracer then Entry.Tracer:Destroy() end
	end
	table.clear(self.Objects)
end

function ESP:TrackPlayers()
	self:Clear()
	local Players = game:GetService("Players")
	local Camera = workspace.CurrentCamera

	for _, p in next, Players:GetPlayers() do
		self:Add(p)
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
		local RunService = game:GetService("RunService")
		local Heartbeat = RunService.Heartbeat

		while self.Running do
			Heartbeat:Wait()
			Camera = workspace.CurrentCamera

			for _, Entry in next, self.Objects do
				local Target = Entry.Target
				local Char = GetChar(Target)
				local Root = GetRoot(Target)
				local Hum = GetHumanoid(Target)

				if not Char or not Root or not Hum then
					if Entry.Gui then Entry.Gui.Enabled = false end
					if Entry.Tracer then Entry.Tracer.Visible = false end
					continue
				end

				if self.AliveCheck and Hum.Health <= 0 then
					if Entry.Gui then Entry.Gui.Enabled = false end
					if Entry.Tracer then Entry.Tracer.Visible = false end
					continue
				end

				if typeof(Target) == "Player" then
					if self.TeamCheck then
						local MyChar = GetChar(game:GetService("Players").LocalPlayer)
						if MyChar then
							local MyTeam = game:GetService("Players").LocalPlayer.Team
							if MyTeam ~= Target.Team then
								-- allow; keep simple
							end
						end
					end
				end

				local Cf, Sz = GetBoundingBox(Char)
				local Top = Cf.Position + Vector3.new(0, Sz.Y * 0.5 + 1.5, 0)
				local Bottom = Cf.Position - Vector3.new(0, Sz.Y * 0.5 + 1, 0)
				local Pos = ProjectTo2D(Camera, self.Folder.Parent or Camera, Top)
				local Btm = ProjectTo2D(Camera, self.Folder.Parent or Camera, Bottom)

				if not Pos or not Btm then
					if Entry.Gui then Entry.Gui.Enabled = false end
					if Entry.Tracer then Entry.Tracer.Visible = false end
					continue
				end

				local Height = (Btm.Y - Pos.Y)
				local Width = Height * 0.5

				if Entry.Gui then
					Entry.Gui.Enabled = true
					Entry.Gui.Size = UDim2.new(0, Width, 0, Height)
					Entry.Gui.Adornee = Root
					Entry.Gui.StudsOffset = Vector3.new(0, Sz.Y * 0.5 + 3, 0)

					if Entry.Box then
						Entry.Box.Visible = self.ShowBox
					end
					if Entry.BoxFill then
						Entry.BoxFill.Visible = self.ShowFill
						Entry.BoxFill.BackgroundColor3 = Entry.Color or self.Color
					end
					if Entry.BoxStroke then
						Entry.BoxStroke.Color = self.OutlineColor
					end
					if Entry.NameLabel then
						Entry.NameLabel.Visible = self.ShowName
						Entry.NameLabel.TextColor3 = self.TextColor
						Entry.NameLabel.Text = Entry.Overrides.Name or Target.Name
					end
					if Entry.HealthLabel then
						Entry.HealthLabel.Visible = self.ShowHealth
						Entry.HealthLabel.TextColor3 = self.TextColor
						Entry.HealthLabel.Text = string.format("HP: %d/%d", math.floor(Hum.Health + 0.5), math.floor(Hum.MaxHealth + 0.5))
					end
					if Entry.DistLabel then
						local DistVal = math.floor((Root.Position - Camera.CFrame.Position).Magnitude + 0.5)
						Entry.DistLabel.Visible = self.ShowDistance
						Entry.DistLabel.TextColor3 = self.TextColor
						Entry.DistLabel.Text = string.format("[%dm]", DistVal)
					end
				end

				if Entry.Tracer and self.ShowTracer then
					Entry.Tracer.Visible = true
					Entry.Tracer.BackgroundColor3 = Entry.Color or self.Color
						local Screen = self.TracerGui
					if Screen and Screen:IsA("ScreenGui") then
						local Abs = Screen.AbsoluteSize
						local MidX = Abs.X * 0.5
						local MidY = Abs.Y
						local T = Pos
						local D = Vector2.new(T.X - MidX, T.Y - MidY)
						local L = D.Magnitude
						if L > 1 then
							local M = (Vector2.new(MidX, MidY) + T) * 0.5
							Entry.Tracer.Position = UDim2.fromOffset(M.X, M.Y)
							Entry.Tracer.Size = UDim2.fromOffset(L, 1)
							Entry.Tracer.Rotation = math.deg(math.atan2(D.Y, D.X))
						else
							Entry.Tracer.Visible = false
						end
					else
						Entry.Tracer.Visible = false
					end
				elseif Entry.Tracer then
					Entry.Tracer.Visible = false
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

function ESP:Preview(Parent)
	-- Builds a little 3D showcase (a ViewportFrame dummy) plus a fully
	-- self-contained ESP overlay drawn with plain Frames on top of it,
	-- so the preview also works inside menus / ViewportFrames.
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

	MakePart("UpperTorso", Vector3.new(2, 2, 1), Vector3.new(0.4, 0, 0), Color3.fromRGB(75, 110, 200))
	MakePart("LowerTorso", Vector3.new(2, 0.6, 1), Vector3.new(0.4, -0.35, 0), Color3.fromRGB(75, 110, 200))
	MakePart("Head", Vector3.new(1, 1, 1), Vector3.new(0.4, 1.5, 0), Color3.fromRGB(245, 215, 175))
	MakePart("LeftArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(-0.9, 0.1, 0), Color3.fromRGB(75, 110, 200))
	MakePart("RightArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(1.7, 0.1, 0), Color3.fromRGB(75, 110, 200))
	MakePart("LeftLeg", Vector3.new(0.8, 1.8, 0.8), Vector3.new(-0.05, -1.4, 0), Color3.fromRGB(45, 70, 140))
	MakePart("RightLeg", Vector3.new(0.8, 1.8, 0.8), Vector3.new(0.85, -1.4, 0), Color3.fromRGB(45, 70, 140))

	Model.Parent = Viewport
	Model.PrimaryPart = Model:FindFirstChild("UpperTorso")
	Camera.CFrame = CFrame.lookAt(Vector3.new(0.4, 0.9, 9), Vector3.new(0.4, 0.7, 0))

	-- The ESP overlay itself. Rendered with plain Frames so it works
	-- everywhere the ESP plugin gets Preview()ed (menus included).
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
	HealthBar.Visible = self.ShowHealth == true
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
	DistLabel.Visible = self.ShowDistance == true
	DistLabel.ZIndex = 3
	DistLabel.Parent = Overlay

	-- Projects a world point into ViewportFrame coordinates (perspective
	-- divide like the game does, scaled to the viewport's AbsoluteSize).
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
	end

	local Connection
	Connection = game:GetService("RunService").Heartbeat:Connect(function()
		local Size = Viewport.AbsoluteSize
		if Size.X < 12 or Size.Y < 12 then
			HideEverything()
			return
		end

		-- The dummy slowly spins so the ESP moves around a bit too.
		local Angle = os.clock() % 8 / 8 * (math.pi * 2)
		Model:PivotTo(CFrame.Angles(0, Angle, 0))

		local Center = Model:GetPivot().Position
		local TopPoint = ProjectPoint(Center + Vector3.new(0, 2.35, 0))
		local BottomPoint = ProjectPoint(Center - Vector3.new(0, 2.65, 0))

		if not TopPoint or not BottomPoint then
			HideEverything()
			return
		end

		local Height = math.max(BottomPoint.Y - TopPoint.Y, 8)
		local Width = Height / 2.4
		local MidX = (TopPoint.X + BottomPoint.X) / 2
		local MidY = (TopPoint.Y + BottomPoint.Y) / 2

		Box.Visible = self.ShowBox ~= false
		Box.Size = UDim2.fromOffset(Width, Height)
		Box.Position = UDim2.fromOffset(MidX - Width / 2, MidY - Height / 2)
		BoxOutline.Color = self.OutlineColor

		NameLabel.Visible = self.ShowName ~= false
		NameLabel.Text = "Preview"
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
			Tracer = nil;
			Color = self.Color;
		},
	}
end

return ESP