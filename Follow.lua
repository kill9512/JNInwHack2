local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Advanced Follow + Debug")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false 

local lastJump = 0
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันวาดเส้น Debug (ปรับปรุงให้บางและจาง) ---
local function updateDebugLine(name, startPos, endPos, color)
    local terrain = workspace.Terrain
    local line = terrain:FindFirstChild(name)
    
    if not debugEnabled then 
        if line then line:Destroy() end
        return 
    end
    
    if not line then
        line = Instance.new("LineHandleAdornment")
        line.Name = name
        line.Thickness = 2 -- เส้นเล็กตามคำขอ
        line.Transparency = 0.5 -- จางๆ
        line.AlwaysOnTop = true
        line.Adornee = terrain
        line.Parent = terrain
    end
    
    line.Color3 = color or Color3.fromRGB(255, 0, 0)
    line.Length = (startPos - endPos).Magnitude
    line.CFrame = CFrame.lookAt(startPos, endPos)
end

-- --- ฟังก์ชันอัปเดตรายชื่อ ---
local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then 
            table.insert(t, p.DisplayName.." (@"..p.Name..")") 
        end 
    end
    return t
end

-- --- UI Elements ---
Section:NewDropdown("Target Mode", "Choose Mode", {"Manual", "Max HP", "Min HP"}, function(m) 
    SelectedMode = m 
end)

local drop = Section:NewDropdown("Select Target", "User", refresh(), function(s) 
    if s == "None (Off)" then
        SelectedPlayerName = nil
    else
        SelectedPlayerName = s:match("@([^%)]+)")
    end
end)

Section:NewButton("Refresh List", "Update Player List", function()
    drop:Refresh(refresh())
end)

local MoveSection = Tab:NewSection("Control & Debug")
MoveSection:NewToggle("Enable Follow", "Start Movement Logic", function(s) 
    followEnabled = s 
end)

MoveSection:NewToggle("Show Debug Lines", "Faint Red Line to Target", function(s) 
    debugEnabled = s 
    if not s then
        if workspace.Terrain:FindFirstChild("TargetTrace") then workspace.Terrain.TargetTrace:Destroy() end
    end
end)

MoveSection:NewSlider("Follow Distance", "Gap", 20, 1, function(s) 
    followDistance = s 
end)

-- --- LOOP 1: DEBUG LINE (ทำงานแยกอิสระ) ---
task.spawn(function()
    while true do
        task.wait()
        if debugEnabled then
            local target = nil
            if SelectedMode == "Manual" then
                target = Players:FindFirstChild(SelectedPlayerName or "")
            else
                -- หาเป้าหมายตาม HP
                local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
                for _, p in pairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") then
                        local hp = p.Character.Humanoid.Health
                        if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then
                            bestHP = hp; target = p
                        end
                    end
                end
            end

            if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local startPos = LocalPlayer.Character.HumanoidRootPart.Position
                local endPos = target.Character.HumanoidRootPart.Position
                updateDebugLine("TargetTrace", startPos, endPos, Color3.fromRGB(255, 50, 50))
            else
                if workspace.Terrain:FindFirstChild("TargetTrace") then workspace.Terrain.TargetTrace:Destroy() end
            end
        end
    end
end)

-- --- LOOP 2: MOVEMENT LOGIC (การเดิน) ---
task.spawn(function()
    while task.wait(0.05) do
        if not followEnabled then continue end
        
        local target = nil
        -- ค้นหาเป้าหมาย (ซ้ำกับข้างบนเพื่อให้แน่ใจว่าค่าตรงกัน)
        if SelectedMode == "Manual" then
            target = Players:FindFirstChild(SelectedPlayerName or "")
        else
            local bestHP = (SelectedMode == "Max HP") and -1 or math.huge
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character:FindFirstChild("Humanoid") then
                    local hp = p.Character.Humanoid.Health
                    if (SelectedMode == "Max HP" and hp > bestHP) or (SelectedMode == "Min HP" and hp < bestHP) then
                        bestHP = hp; target = p
                    end
                end
            end
        end

        if target and target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local tRoot = target.Character.HumanoidRootPart
            
            if myHuman and myRoot then
                rayParams.FilterDescendantsInstances = {myChar, target.Character}
                local dist = (tRoot.Position - myRoot.Position).Magnitude

                if dist > followDistance then
                    -- สั่งเดินตรงไปหาเป้าหมาย (Logic การกระจัดเดิม)
                    myHuman:MoveTo(tRoot.Position)
                    
                    -- เช็คสิ่งกีดขวางระดับเข่าเพื่อกระโดด
                    local ray = workspace:Raycast(myRoot.Position, (tRoot.Position - myRoot.Position).Unit * 5, rayParams)
                    if ray and tick() - lastJump > 0.6 then
                        myHuman.Jump = true
                        lastJump = tick()
                    end
                else
                    myHuman:MoveTo(myRoot.Position) -- หยุดเดิน
                end
            end
        end
    end
end)
