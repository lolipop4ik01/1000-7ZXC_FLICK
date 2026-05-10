--[[
    Flick To Murderer / Auto Shoot
    Полностью независимый скрипт
    Работает на Murder Mystery 2
]]

-- ========== СЕРВИСЫ ==========
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ========== КОНФИГ ПО УМОЛЧАНИЮ ==========
local Config = {
    FlickEnabled = false,
    FlickSpeed = 1,          -- 1-50
    AutoShootEnabled = false,
    BigButtonSize = 200,
    BindButtonSize = 0.11,
}

-- ========== СОХРАНЕНИЕ ПОЗИЦИЙ ==========
local SAVE_FILE = "FlickButtonPositions.json"

local function savePositions(data)
    pcall(function()
        if writefile then
            writefile(SAVE_FILE, HttpService:JSONEncode(data))
        end
    end)
end

local function loadPositions()
    local ok, result = pcall(function()
        if readfile and isfile and isfile(SAVE_FILE) then
            return HttpService:JSONDecode(readfile(SAVE_FILE))
        end
    end)
    if ok and type(result) == "table" then return result end
    return {}
end

local savedPositions = loadPositions()

local DEFAULT_POSITIONS = {
    big  = { xs = 0.5, xo = 0, ys = 0.5, yo = 0 },
    bind = { xs = 0.1, xo = 0, ys = 0.9, yo = 0 },
}

-- ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==========
local function getSafeParent()
    local parent = gethui and gethui()
    if parent and typeof(parent) == "Instance" then
        return parent
    end
    parent = CoreGui
    if parent and typeof(parent) == "Instance" then
        return parent
    end
    return LocalPlayer:WaitForChild("PlayerGui")
end

local function notify(msg, duration)
    duration = duration or 2
    pcall(function()
        local sg = getSafeParent():FindFirstChild("FlickNotifications")
        if not sg then
            sg = Instance.new("ScreenGui")
            sg.Name = "FlickNotifications"
            sg.ResetOnSpawn = false
            sg.IgnoreGuiInset = true
            sg.Parent = getSafeParent()
        end
        
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 300, 0, 50)
        frame.Position = UDim2.new(0.5, -150, 0.8, 0)
        frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
        frame.BackgroundTransparency = 0.2
        frame.BorderSizePixel = 0
        frame.Parent = sg
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = msg
        label.TextColor3 = Color3.new(1, 1, 1)
        label.Font = Enum.Font.Jura
        label.TextSize = 14
        label.Parent = frame
        
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
        
        frame:TweenPosition(UDim2.new(0.5, -150, 0.75, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.3, true)
        
        task.wait(duration)
        
        frame:TweenPosition(UDim2.new(0.5, -150, 0.85, 0), Enum.EasingDirection.In, Enum.EasingStyle.Quad, 0.3, true)
        task.wait(0.3)
        frame:Destroy()
    end)
end

-- ========== MAID (ДЛЯ УПРАВЛЕНИЯ ПАМЯТЬЮ) ==========
local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({_tasks = {}, _destroyed = false}, Maid)
end

function Maid:GiveTask(t)
    if self._destroyed then
        if typeof(t) == "RBXScriptConnection" then t:Disconnect()
        elseif typeof(t) == "Instance" then t:Destroy()
        elseif type(t) == "function" then t()
        elseif type(t) == "table" and type(t.Destroy) == "function" then t:Destroy() end
        return
    end
    table.insert(self._tasks, t)
    return t
end

function Maid:DoCleaning()
    if self._destroyed then return end
    self._destroyed = true
    for _, t in pairs(self._tasks) do
        if typeof(t) == "RBXScriptConnection" then t:Disconnect()
        elseif typeof(t) == "Instance" then t:Destroy()
        elseif type(t) == "function" then t()
        elseif type(t) == "table" and type(t.Destroy) == "function" then t:Destroy() end
    end
    self._tasks = {}
end

function Maid:Destroy() self:DoCleaning() end

-- ========== BIG BUTTON SYSTEM ==========
local BBSystem = {Buttons = {}, Connections = {}}

local BB_GRAD_SEQ = ColorSequence.new({
    ColorSequenceKeypoint.new(0,    Color3.new(0.0784314, 0.0784314, 0.0784314)),
    ColorSequenceKeypoint.new(0.75, Color3.new(0.0784314, 0.0784314, 0.54902)),
    ColorSequenceKeypoint.new(1,    Color3.new(0.470588,  0.156863,  0.470588))
})

local function BB_GetStorage()
    local parent = getSafeParent()
    local sg = parent:FindFirstChild("@BBStorage")
    if not sg then
        sg = Instance.new("ScreenGui")
        sg.Name = "@BBStorage"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        pcall(function() sg.ScreenInsets = Enum.ScreenInsets.None end)
        sg.Parent = parent
    end
    return sg
end

local function BB_MakeDraggable(gui, func, ripple, sound, getSizeFunc)
    local dragging, dragInput, dragStart, startPos = false
    local hasMoved = false
    local tInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    local function getNormalSize()
        return getSizeFunc and getSizeFunc() or UDim2.new(0, 200, 0, 75)
    end

    local function getBigSize()
        local ns = getNormalSize()
        return UDim2.new(ns.X.Scale, ns.X.Offset * 1.1, ns.Y.Scale, ns.Y.Offset * 1.1)
    end

    gui.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            hasMoved = false
            dragStart = input.Position
            startPos = gui.Position
            TweenService:Create(gui, tInfo, {Size = getBigSize()}):Play()
            
            local absPos = gui.AbsolutePosition
            ripple.Position = UDim2.new(0, input.Position.X - absPos.X, 0, input.Position.Y - absPos.Y)
            ripple.Size = UDim2.new(0, 0, 0, 0)
            ripple.BackgroundTransparency = 0.5
            ripple.Visible = true
            sound:Play()
            
            TweenService:Create(ripple, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 300, 0, 300),
                BackgroundTransparency = 1
            }):Play()
            
            local rel
            rel = UserInputService.InputEnded:Connect(function(endInput)
                if endInput.UserInputType == input.UserInputType then
                    dragging = false
                    TweenService:Create(gui, tInfo, {Size = getNormalSize()}):Play()
                    
                    if not hasMoved and func then
                        pcall(func)
                    end
                    
                    savedPositions.big = {
                        xs = gui.Position.X.Scale, xo = gui.Position.X.Offset,
                        ys = gui.Position.Y.Scale, yo = gui.Position.Y.Offset
                    }
                    savePositions(savedPositions)
                    rel:Disconnect()
                end
            end)
        end
    end)
    
    gui.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            if delta.Magnitude > 7 then hasMoved = true end
            gui.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local function AddBigButton(id, text, func, getSizeFunc)
    if BBSystem.Buttons[id] then return end
    
    local storage = BB_GetStorage()
    local bb = Instance.new("TextButton")
    bb.Name = id
    bb.Size = getSizeFunc and getSizeFunc() or UDim2.new(0, 200, 0, 75)
    
    local sp = savedPositions.big or DEFAULT_POSITIONS.big
    bb.Position = UDim2.new(sp.xs, sp.xo, sp.ys, sp.yo)
    bb.AnchorPoint = Vector2.new(0.5, 0.5)
    bb.BackgroundColor3 = Color3.new(1, 1, 1)
    bb.BackgroundTransparency = 0.9
    bb.BorderSizePixel = 0
    bb.Font = Enum.Font.Jura
    bb.Text = text
    bb.TextSize = 24
    bb.TextColor3 = Color3.new(1, 1, 1)
    bb.TextWrapped = true
    bb.ClipsDescendants = true
    bb.AutoButtonColor = false
    bb.ZIndex = 5
    bb.Visible = true
    bb.Parent = storage

    Instance.new("UICorner", bb).CornerRadius = UDim.new(0, 5)
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(1, 1, 1)
    stroke.Thickness = 1.5
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = bb
    
    local gradient = Instance.new("UIGradient")
    gradient.Color = BB_GRAD_SEQ
    gradient.Parent = stroke

    local ripple = Instance.new("Frame")
    ripple.Name = "@ripple"
    ripple.BackgroundColor3 = Color3.fromRGB(0, 155, 255)
    ripple.BackgroundTransparency = 0.5
    ripple.ZIndex = 4
    ripple.Size = UDim2.new(0, 0, 0, 0)
    ripple.AnchorPoint = Vector2.new(0.5, 0.5)
    ripple.Visible = false
    ripple.Parent = bb
    Instance.new("UICorner", ripple).CornerRadius = UDim.new(1, 0)

    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://3868133279"
    sound.Volume = 0.5
    sound.Parent = bb

    BB_MakeDraggable(bb, func, ripple, sound, getSizeFunc)
    
    BBSystem.Connections[id] = RunService.RenderStepped:Connect(function()
        gradient.Rotation = (gradient.Rotation + 1) % 360
    end)
    
    BBSystem.Buttons[id] = bb
end

local function SetBigButtonVisible(id, visible)
    local btn = BBSystem.Buttons[id]
    if btn then btn.Visible = visible end
end

-- ========== BIND BUTTON SYSTEM ==========
local BindableButtons = {Buttons = {}, Maids = {}, Count = 0}

local SHAPES = {
    [0] = "rbxassetid://86221076925479",
    [1] = "rbxassetid://96242665417546",
    [2] = "rbxassetid://97129189935336",
    [3] = "rbxassetid://76165862027868",
    [4] = "rbxassetid://125868092127496"
}

local NORMAL_COLOR = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.new(0.133333, 0.827451, 0.494118)),
    ColorSequenceKeypoint.new(0.6, Color3.new(0.231373, 0.509804, 0.498039)),
    ColorSequenceKeypoint.new(1,   Color3.new(0.501961, 0.501961, 0.501961))
})

local function Bind_GetStorage()
    local parent = getSafeParent()
    local sg = parent:FindFirstChild("@bindstorage")
    if not sg then
        sg = Instance.new("ScreenGui")
        sg.Name = "@bindstorage"
        sg.ResetOnSpawn = false
        sg.IgnoreGuiInset = true
        pcall(function() sg.ScreenInsets = Enum.ScreenInsets.None end)
        sg.Parent = parent
    end
    return sg
end

local function Bind_MakeDraggable(gui, maid, ripple, sound, clickFunc)
    local dragging, dragInput, dragStart, startPos = false
    local hasMoved = false

    maid:GiveTask(gui.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = gui.Position
            hasMoved = false
            sound:Play()
            
            local absPos = gui.AbsolutePosition
            ripple.Position = UDim2.new(0, input.Position.X - absPos.X, 0, input.Position.Y - absPos.Y)
            ripple.Size = UDim2.new(0, 0, 0, 0)
            ripple.BackgroundTransparency = 0.5
            ripple.Visible = true
            
            TweenService:Create(ripple, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
                Size = UDim2.new(0, 45, 0, 45),
                BackgroundTransparency = 1
            }):Play()
            
            local rel
            rel = UserInputService.InputEnded:Connect(function(endInput)
                if endInput.UserInputType == input.UserInputType then
                    dragging = false
                    if not hasMoved and clickFunc then
                        pcall(clickFunc)
                    else
                        savedPositions.bind = {
                            xs = gui.Position.X.Scale, xo = gui.Position.X.Offset,
                            ys = gui.Position.Y.Scale, yo = gui.Position.Y.Offset
                        }
                        savePositions(savedPositions)
                    end
                    rel:Disconnect()
                end
            end)
        end
    end))

    maid:GiveTask(gui.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end))

    maid:GiveTask(UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            if delta.Magnitude > 7 then hasMoved = true end
            local screen = gui.Parent.AbsoluteSize
            gui.Position = UDim2.new(startPos.X.Scale + (delta.X / screen.X), 0, startPos.Y.Scale + (delta.Y / screen.Y), 0)
        end
    end))
end

function BindableButtons.AddBButton(id, text, clickFunc)
    if BindableButtons.Buttons[id] then return end

    local buttonMaid = Maid.new()
    local camera = workspace.CurrentCamera
    local screen = camera.ViewportSize
    local buttonSizeY = Config.BindButtonSize
    local widthScale = buttonSizeY * (screen.Y / screen.X)

    local sp = savedPositions.bind
    local xPos, yPos
    if sp then
        xPos = sp.xs
        yPos = sp.ys
    else
        xPos = 0.1 + ((BindableButtons.Count % 8) * (widthScale + 0.005))
        yPos = 0.9 - (math.floor(BindableButtons.Count / 8) * (buttonSizeY + 0.015))
    end

    local ImageButton = Instance.new("ImageButton")
    ImageButton.Name = id
    ImageButton.Size = UDim2.new(widthScale, 0, buttonSizeY, 0)
    ImageButton.Position = UDim2.new(xPos, 0, yPos, 0)
    ImageButton.AnchorPoint = Vector2.new(0.5, 0.5)
    ImageButton.Image = SHAPES[0]
    ImageButton.BackgroundTransparency = 1
    ImageButton.BorderSizePixel = 0
    ImageButton.ClipsDescendants = false
    ImageButton.AutoButtonColor = false
    ImageButton.Visible = true
    ImageButton.Parent = Bind_GetStorage()
    buttonMaid:GiveTask(ImageButton)

    local TextLabel = Instance.new("TextLabel", ImageButton)
    TextLabel.Name = "@Text"
    TextLabel.Size = UDim2.new(0.8, 0, 0.8, 0)
    TextLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    TextLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    TextLabel.BackgroundTransparency = 1
    TextLabel.Font = Enum.Font.Jura
    TextLabel.Text = text
    TextLabel.TextColor3 = Color3.new(1, 1, 1)
    TextLabel.TextSize = 10
    TextLabel.TextWrapped = true
    TextLabel.ZIndex = 3

    local Aspect = Instance.new("UIAspectRatioConstraint", ImageButton)
    Aspect.AspectRatio = 1
    Aspect.AspectType = Enum.AspectType.ScaleWithParentSize

    local Stroke = Instance.new("UIGradient", ImageButton)
    Stroke.Name = "@Stroke"
    Stroke.Color = NORMAL_COLOR

    local ripple = Instance.new("Frame")
    ripple.Name = "@ripple"
    ripple.BackgroundColor3 = Color3.fromRGB(0, 155, 255)
    ripple.BackgroundTransparency = 0.5
    ripple.Size = UDim2.new(0, 0, 0, 0)
    ripple.AnchorPoint = Vector2.new(0.5, 0.5)
    ripple.Visible = false
    ripple.ZIndex = 2
    ripple.Parent = ImageButton
    Instance.new("UICorner", ripple).CornerRadius = UDim.new(1, 0)

    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://3868133279"
    sound.Volume = 0.5
    sound.Parent = ImageButton

    Bind_MakeDraggable(ImageButton, buttonMaid, ripple, sound, clickFunc)
    buttonMaid:GiveTask(RunService.RenderStepped:Connect(function()
        Stroke.Rotation = (Stroke.Rotation + 1) % 360
    end))

    BindableButtons.Buttons[id] = ImageButton
    BindableButtons.Maids[id] = buttonMaid
    BindableButtons.Count = BindableButtons.Count + 1
end

local function SetBindButtonVisible(id, visible)
    local btn = BindableButtons.Buttons[id]
    if btn then btn.Visible = visible end
end

-- ========== ОСНОВНАЯ ЛОГИКА FLICK ==========
local function findMurderer()
    if game.PlaceId == 142823291 then
        local success, roleData = pcall(function()
            local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
            if remote and remote:IsA("RemoteFunction") then
                return remote:InvokeServer()
            end
        end)
        if success and roleData then
            for playerName, data in pairs(roleData) do
                if data.Role == "Murderer" and not data.Killed and not data.Dead then
                    local p = Players:FindFirstChild(playerName)
                    if p then return p end
                end
            end
        end
        return nil
    else
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local char = player.Character
                local root = char:FindFirstChild("HumanoidRootPart")
                local hum = char:FindFirstChild("Humanoid")
                if root and hum and hum.Health > 0 then
                    local bp = player:FindFirstChild("Backpack")
                    if bp and bp:FindFirstChild("Knife") then return player end
                    for _, tool in ipairs(char:GetChildren()) do
                        if tool:IsA("Tool") and tool.Name == "Knife" then return player end
                    end
                end
            end
        end
        return nil
    end
end

local function findShootRemote()
    local ns = ReplicatedStorage:FindFirstChild("Axioria Solver was here.")
    if not ns then return nil end
    for _, v in ipairs(ns:GetChildren()) do
        if v:IsA("RemoteEvent") then return v end
    end
    return nil
end

local function autoShoot(murderer)
    if not Config.AutoShootEnabled then return end
    if not murderer or not murderer.Character then return end
    local remote = findShootRemote()
    if not remote then return end
    local murdererRoot = murderer.Character:FindFirstChild("HumanoidRootPart")
    if not murdererRoot then return end
    pcall(function()
        remote:FireServer({
            workspace.CurrentCamera.CFrame,
            CFrame.new(murdererRoot.Position),
        })
    end)
end

local function flickToMurderer()
    if not Config.FlickEnabled then
        notify("Flick is disabled!", 2)
        return
    end
    
    local murderer = findMurderer()
    if not murderer or not murderer.Character or not murderer.Character:FindFirstChild("HumanoidRootPart") then
        notify("Murderer not found!", 2)
        return
    end
    
    local cam = workspace.CurrentCamera
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not root or not hum then return end

    local targetPos = murderer.Character.HumanoidRootPart.Position
    local oldCFrame = cam.CFrame
    local targetCFrame = CFrame.lookAt(oldCFrame.Position, targetPos)

    local currentLook = oldCFrame.LookVector
    local targetLook = (targetPos - oldCFrame.Position).Unit
    local dot = math.clamp(currentLook:Dot(targetLook), -1, 1)
    local angleDist = math.acos(dot)
    local angularSpeed = Config.FlickSpeed * 0.5 * math.pi
    local totalTime = math.max(angleDist / angularSpeed, 0.016)
    local steps = 8
    local waitTime = totalTime / steps

    for i = 1, steps do
        cam.CFrame = oldCFrame:Lerp(targetCFrame, i / steps)
        task.wait(waitTime)
    end

    autoShoot(murderer)
end

local function getBBSize()
    return UDim2.new(0, Config.BigButtonSize, 0, Config.BigButtonSize * 0.375)
end

-- ========== GUI ==========
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FlickGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = getSafeParent()

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 320, 0, 420)
MainFrame.Position = UDim2.new(0.5, -160, 0.5, -210)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 40)
Title.Position = UDim2.new(0, 0, 0, 5)
Title.BackgroundTransparency = 1
Title.Text = "FLICK TO MURDERER"
Title.TextColor3 = Color3.fromRGB(255, 100, 100)
Title.Font = Enum.Font.Jura
Title.TextSize = 20
Title.TextScaled = true
Title.Parent = MainFrame

local ListLayout = Instance.new("UIListLayout")
ListLayout.Padding = UDim.new(0, 8)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.Parent = MainFrame

local Padding = Instance.new("UIPadding")
Padding.PaddingTop = UDim.new(0, 50)
Padding.PaddingLeft = UDim.new(0, 10)
Padding.PaddingRight = UDim.new(0, 10)
Padding.Parent = MainFrame

-- Функции создания GUI элементов
local function CreateToggle(text, callback, default)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 40)
    button.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.Jura
    button.TextSize = 16
    button.Text = text .. ": OFF"
    button.Parent = MainFrame
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
    
    local state = default or false
    
    button.MouseButton1Click:Connect(function()
        state = not state
        button.Text = text .. ": " .. (state and "ON" or "OFF")
        button.BackgroundColor3 = state and Color3.fromRGB(60, 80, 60) or Color3.fromRGB(40, 40, 45)
        if callback then callback(state) end
    end)
    
    button.BackgroundColor3 = state and Color3.fromRGB(60, 80, 60) or Color3.fromRGB(40, 40, 45)
    button.Text = text .. ": " .. (state and "ON" or "OFF")
    
    return button
end

local function CreateButton(text, callback)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, 0, 0, 40)
    button.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
    button.TextColor3 = Color3.new(1, 1, 1)
    button.Font = Enum.Font.Jura
    button.TextSize = 16
    button.Text = text
    button.Parent = MainFrame
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 8)
    
    button.MouseButton1Click:Connect(function()
        if callback then callback() end
    end)
    
    return button
end

local function CreateSlider(text, minVal, maxVal, defaultVal, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 55)
    frame.BackgroundTransparency = 1
    frame.Parent = MainFrame
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 20)
    label.BackgroundTransparency = 1
    label.Text = text .. ": " .. defaultVal
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Font = Enum.Font.Jura
    label.TextSize = 14
    label.Parent = frame
    
    local slider = Instance.new("Frame")
    slider.Size = UDim2.new(1, 0, 0, 25)
    slider.Position = UDim2.new(0, 0, 0, 25)
    slider.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    slider.Parent = frame
    Instance.new("UICorner", slider).CornerRadius = UDim.new(0, 12)
    
    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((defaultVal - minVal) / (maxVal - minVal), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
    fill.Parent = slider
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 12)
    
    local dragging = false
    local value = defaultVal
    
    local function updateSlider(input)
        local pos = math.clamp((input.Position.X - slider.AbsolutePosition.X) / slider.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(pos, 0, 1, 0)
        value = minVal + pos * (maxVal - minVal)
        value = math.floor(value)
        label.Text = text .. ": " .. value
        if callback then callback(value) end
    end
    
    slider.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            updateSlider(input)
        end
    end)
    
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            updateSlider(input)
        end
    end)
end

-- Глобальные флаги для кнопок
local bigButtonShown = false
local bindButtonShown = false

-- Создание GUI
CreateToggle("Flick", function(state)
    Config.FlickEnabled = state
    notify(state and "Flick enabled" or "Flick disabled", 1)
end, false)

CreateSlider("Flick Speed", 1, 50, 1, function(value)
    Config.FlickSpeed = value
end)

CreateToggle("Auto Shoot", function(state)
    Config.AutoShootEnabled = state
    notify(state and "Auto Shoot ON" or "Auto Shoot OFF", 1)
end, false)

CreateButton("FLICK NOW", function()
    flickToMurderer()
end)

CreateToggle("Show Big Button", function(state)
    if state then
        if not bigButtonShown then
            AddBigButton("flick_big", "FLICK", flickToMurderer, getBBSize)
            bigButtonShown = true
        else
            SetBigButtonVisible("flick_big", true)
        end
        local btn = BBSystem.Buttons["flick_big"]
        if btn then btn.Size = getBBSize() end
    else
        SetBigButtonVisible("flick_big", false)
    end
end, false)

CreateSlider("Big Button Size", 100, 400, 200, function(value)
    Config.BigButtonSize = value
    local btn = BBSystem.Buttons["flick_big"]
    if btn and btn.Visible then
        btn.Size = getBBSize()
    end
end)

CreateButton("Reset Big Button Position", function()
    savedPositions.big = nil
    savePositions(savedPositions)
    local btn = BBSystem.Buttons["flick_big"]
    if btn then
        local dp = DEFAULT_POSITIONS.big
        btn.Position = UDim2.new(dp.xs, dp.xo, dp.ys, dp.yo)
    end
    notify("Big button position reset", 2)
end)

CreateToggle("Show Bind Button", function(state)
    if state then
        if not bindButtonShown then
            BindableButtons.AddBButton("flick_bind", "FLICK", flickToMurderer)
            bindButtonShown = true
        else
            SetBindButtonVisible("flick_bind", true)
        end
        local btn = BindableButtons.Buttons["flick_bind"]
        if btn then
            local screen = workspace.CurrentCamera.ViewportSize
            btn.Size = UDim2.new(Config.BindButtonSize * (screen.Y / screen.X), 0, Config.BindButtonSize, 0)
        end
    else
        SetBindButtonVisible("flick_bind", false)
    end
end, false)

CreateSlider("Bind Button Size", 5, 25, 11, function(value)
    Config.BindButtonSize = value / 100
    local btn = BindableButtons.Buttons["flick_bind"]
    if btn and btn.Visible then
        local screen = workspace.CurrentCamera.ViewportSize
        btn.Size = UDim2.new(Config.BindButtonSize * (screen.Y / screen.X), 0, Config.BindButtonSize, 0)
    end
end)

CreateButton("Reset Bind Button Position", function()
    savedPositions.bind = nil
    savePositions(savedPositions)
    local btn = BindableButtons.Buttons["flick_bind"]
    if btn then
        local dp = DEFAULT_POSITIONS.bind
        btn.Position = UDim2.new(dp.xs, dp.xo, dp.ys, dp.yo)
    end
    notify("Bind button position reset", 2)
end)

-- ========== KEYBIND ==========
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.F then
        flickToMurderer()
    end
end)

-- ========== ЗАГРУЗОЧНОЕ УВЕДОМЛЕНИЕ ==========
task.wait(1)
notify("Flick To Murderer loaded!\nPress F to flick", 3)

print("Flick To Murderer script loaded successfully!")