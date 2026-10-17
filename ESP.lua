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
	self.Folder = Options.Folder or (game:GetService("CoreGui"):FindFirstChild("ESP") or Instance.new("Folder", game:GetService("CoreGui")))
	self.Folder.Name = "ESP"
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
	Name.TextXAlignment = Enum.TextAlignment.Left
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
	Health.TextXAlignment = Enum.TextAlignment.Left
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
	Dist.TextXAlignment = Enum.TextAlignment.Left
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
	Tracer.Parent = self.Folder

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
					local Screen = self.Folder.Parent
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
	if self.Folder then
		self.Folder:Destroy()
	end
end

function ESP:Preview(Parent)
	if not Parent then
		Parent = Instance.new("Frame")
		Parent.Name = "ESPPreviewContainer"
		Parent.BackgroundTransparency = 1
		Parent.Size = UDim2.fromScale(1, 1)
	end

	local Cam = Instance.new("Camera")
	Cam.FieldOfView = 40
	Cam.Parent = workspace

	local Vpf = Instance.new("ViewportFrame")
	Vpf.Name = "ESP_Preview"
	Vpf.Size = UDim2.new(1, -4, 1, -4)
	Vpf.Position = UDim2.new(0, 2, 0, 2)
	Vpf.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
	Vpf.Ambient = Color3.fromRGB(150, 150, 150)
	Vpf.LightColor = Color3.fromRGB(230, 230, 230)
	Vpf.LightDirection = Vector3.new(-0.7, 0.6, -0.3)
	Vpf.CurrentCamera = Cam
	Vpf.Parent = Parent

	local Model = Instance.new("Model")
	Model.Parent = Vpf

	local function MakePart(Name, Size, Position, Color)
		local P = Instance.new("Part")
		P.Name = Name
		P.Size = Size
		P.Position = Position
		P.Anchored = true
		P.Color = Color
		P.Material = Enum.Material.SmoothPlastic
		P.Parent = Model
		return P
	end

	local Torso = MakePart("UpperTorso", Vector3.new(2, 2, 1), Vector3.new(0, 2.5, 0), Color3.fromRGB(75, 110, 200))
	local LowerTorso = MakePart("LowerTorso", Vector3.new(2, 0.6, 1), Vector3.new(0, 1.7, 0), Color3.fromRGB(75, 110, 200))
	local Head = MakePart("Head", Vector3.new(1, 1, 1), Vector3.new(0, 4, 0), Color3.fromRGB(245, 215, 175))
	local LA = MakePart("LeftArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(-1.5, 2.8, 0), Color3.fromRGB(75, 110, 200))
	local RA = MakePart("RightArm", Vector3.new(0.8, 1.8, 0.8), Vector3.new(1.5, 2.8, 0), Color3.fromRGB(75, 110, 200))
	local LL = MakePart("LeftLeg", Vector3.new(0.8, 1.8, 0.8), Vector3.new(-0.5, 0.7, 0), Color3.fromRGB(45, 70, 140))
	local RL = MakePart("RightLeg", Vector3.new(0.8, 1.8, 0.8), Vector3.new(0.5, 0.7, 0), Color3.fromRGB(45, 70, 140))

	local Cf = Torso.CFrame:Lerp(Head.CFrame, 0.5)
	Cam.CFrame = Cf * CFrame.new(0, 1, 6) * CFrame.Angles(0, math.rad(180), 0)

	local root = Model:FindFirstChild("HumanoidRootPart") or Torso
	local Human = Instance.new("Humanoid")
	Human.Parent = Model

	local gui = Instance.new("ScreenGui")
	gui.Name = "ESP_Preview_Overlay"
	gui.IgnoreGuiInset = true
	gui.Parent = Vpf

	local Entry = ESP.new({
		ShowName = true,
		ShowHealth = true,
		ShowDistance = true,
		ShowBox = true,
		ShowFill = true,
		ShowTracer = true,
		Color = Color3.fromRGB(235, 75, 75),
		TextColor = Color3.new(1, 1, 1),
		OutlineColor = Color3.new(0, 0, 0),
	})

	Entry:Add(Model, { Name = "Preview" })

	local p = game:GetService("Players").LocalPlayer
	if p then
		Entry.Tracer.Visible = false
	end

	Entry.Tracked._Preview = game:GetService("RunService").Heartbeat:Connect(function()
		local Camera = Cam
		local Char = Model
		local Root = Torso
		local Sz = Vector3.new(3, 4, 1)
		local Top = Root.CFrame.Position + Vector3.new(0, Sz.Y * 0.5 + 1.5, 0)
		local Bottom = Root.CFrame.Position - Vector3.new(0, Sz.Y * 0.5 + 1, 0)
		local Pos = ProjectTo2D(Camera, gui, Top)
		local Btm = ProjectTo2D(Camera, gui, Bottom)

		if not Pos or not Btm then
			if Entry.Gui then Entry.Gui.Enabled = false end
			if Entry.Tracer then Entry.Tracer.Visible = false end
			return
		end

		local Height = (Btm.Y - Pos.Y)
		local Width = Height * 0.5

		if Entry.Gui then
			Entry.Gui.Enabled = true
			Entry.Gui.Size = UDim2.new(0, Width, 0, Height)
			Entry.Gui.Adornee = root
			Entry.Gui.StudsOffset = Vector3.new(0, Sz.Y * 0.5 + 3, 0)

			if Entry.Box then Entry.Box.Visible = self.ShowBox end
			if Entry.BoxFill then
				Entry.BoxFill.Visible = self.ShowFill
				Entry.BoxFill.BackgroundColor3 = Entry.Color or self.Color
			end
			if Entry.NameLabel then
				Entry.NameLabel.Visible = self.ShowName
				Entry.NameLabel.Text = Entry.Overrides.Name or "Preview"
			end
			if Entry.HealthLabel then
				Entry.HealthLabel.Visible = self.ShowHealth
				Entry.HealthLabel.Text = "HP: 500/500"
			end
			if Entry.DistLabel then
				Entry.DistLabel.Visible = self.ShowDistance
				local DistVal = math.floor((Root.Position - Camera.CFrame.Position).Magnitude + 0.5)
				Entry.DistLabel.Text = string.format("[%dm]", DistVal)
			end
		end

		if Entry.Tracer then Entry.Tracer.Visible = false end
	end)

	return {
		Cleanup = function()
			if Entry.Tracked._Preview then Entry.Tracked._Preview:Disconnect() end
			Entry:Destroy()
			if gui then gui:Destroy() end
			if Model then Model:Destroy() end
			if Cam then Cam:Destroy() end
			if Vpf then Vpf:Destroy() end
		end,
		ESP = Entry,
		Viewport = Vpf,
	}
end

return ESP