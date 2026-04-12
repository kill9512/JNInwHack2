local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Path Visualizer Follow")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false
local debugEnabled = false

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- Folder สำหรับเก็บบล็อก Debug ---
local debugFolder = workspace:FindFirstChild("DebugPathFolder") or Instance.new("Folder", workspace)
debugFolder.Name = "DebugPathFolder"

-- --- ฟังก์ชันล้างบล็อกเก่า ---
local function clearBlocks()
    debugFolder:ClearAllChildren()
end

-- --- ฟังก์ชันเสกบล็อกจำลอง (Visual Block) ---
local function createVisualBlock(pos, color)
    if not debugEnabled then return end
    local p = Instance.new("Part")
    p.Size = Vector3.new(1, 1, 1)
    p.Position = pos
    p.Anchored = true
    p.CanCollide = false
    p.Transparency = 0.5
    p.Color = color
    p.Material = Enum.Material.Neon
    p.Parent = debugFolder
    return p
end

-- --- Logic ค้นหาทางเดินที่ดีที่สุดโดยการจำลองบล็อก ---
local function calculateBestPath(myRoot, targetPos)
    local currentPos = myRoot.Position
    local moveDir = (targetPos - currentPos).Unit
    local stepSize = 4 -- ระยะห่างแต่ละบล็อก
    
    clearBlocks() -- ล้างก่อนวาดใหม่

    -- 1. ลองจำลองทางตรง
    local isBlocked = false
    for i = 1, 4 do -- จำลองไปข้างหน้า 4 บล็อก
        local nextPos = currentPos + (moveDir * (i * stepSize))
        local hit = workspace:Raycast(currentPos + (moveDir * ((i-1) * stepSize)), moveDir * stepSize, rayParams)
        
        if hit then
            isBlocked = true
            createVisualBlock(hit.Position, Color3.fromRGB(255, 0, 0)) -- บล็อกแดงเมื่อชน
            break
        else
            createVisualBlock(nextPos, Color3.fromRGB(0, 255, 0)) -- บล็อกเขียวเมื่อผ่านได้
        end
    end

    -- 2. ถ้าทางตรงบล็อก ให้ลองซ้ายและขวา
    if isBlocked then
        local leftDir = (CFrame.Angles(0, math.rad(45), 0) * moveDir).Unit
        local rightDir = (CFrame.Angles(0, math.rad(-45), 0) * moveDir).Unit
        
        -- คำนวณหา "การกระจัด" (Distance to Target) ว่าทางไหนใกล้กว่า
        local leftPathPos = currentPos + (leftDir * stepSize)
        local rightPathPos = currentPos + (rightDir * stepSize)
        
        local leftDist = (leftPathPos - targetPos).Magnitude
        local rightDist = (rightPathPos - targetPos).Magnitude
        
        if leftDist < rightDist then
            createVisualBlock(leftPathPos, Color3.fromRGB(0, 255, 255)) -- สีฟ้า = ทางเลือก
            return leftPathPos
        else
            createVisualBlock(rightPathPos, Color3.fromRGB(0, 255, 255))
            return rightPathPos
        end
    end

    return targetPos
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Choose Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Target", "User", {}, function(s) 
    SelectedPlayerName = s:match("@([^%)]+)") 
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
    drop:Refresh(t)
end
Section:NewButton("Refresh List", "Update", refresh)
refresh()

local MoveSection = Tab:NewSection("Control & Debug")
MoveSection:NewToggle("Enable Follow", "Start Follow Logic", function(s) followEnabled = s end)
MoveSection:NewToggle("Show Path Blocks", "Spawn Visual Blocks", function(s) 
    debugEnabled = s 
    if not s then clearBlocks() end
end)
MoveSection:NewSlider("Follow Distance", "Gap", 20, 1, function(s) followDistance = s end)

-- --- LOGIC CORE ---
task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end
        
        local target = nil
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
                rayParams.FilterDescendantsInstances = {myChar, target.Character, debugFolder}
                local dist = (tRoot.Position - myRoot.Position).Magnitude

                if dist > followDistance then
                    -- คำนวณทางเดินด้วยระบบบล็อกจำลอง
                    local nextMovePoint = calculateBestPath(myRoot, tRoot.Position)
                    
                    myHuman:MoveTo(nextMovePoint)
                    
                    -- เช็คกระโดด
                    local jumpRay = workspace:Raycast(myRoot.Position, (nextMovePoint - myRoot.Position).Unit * 5, rayParams)
                    if jumpRay and myHuman.FloorMaterial ~= Enum.Material.Air then
                        myHuman.Jump = true
                    end
                else
                    myHuman:MoveTo(myRoot.Position)
                    clearBlocks()
                end
            end
        else
            clearBlocks()
        end
    end
end)
