local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()
local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")
local Section = Tab:NewSection("Smart Follow Player")

-- --- Services ---
local Players = game.Players
local LocalPlayer = Players.LocalPlayer

-- --- Variables ---
local SelectedMode = "Manual"
local SelectedPlayerName = nil
local followDistance = 5
local followEnabled = false

local lastPos = Vector3.new(0,0,0)
local stuckTime = 0
local jumpCooldown = 0
local detourTimer = 0
local lockedDir = nil
local blockedAngles = {} -- จำมุมที่เดินไปไม่ได้ชั่วคราว

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

-- --- ฟังก์ชันแสกนหาทางเดินที่ไปต่อได้จริงๆ ---
local function scanSidePaths(myRoot, moveDir)
    -- แสกนมุมกว้าง 45, 90, 135 องศา ทั้งซ้ายและขวา
    local scanAngles = {60, -60, 90, -90, 135, -135}
    local bestDir = nil
    local maxDist = 0

    for _, angle in ipairs(scanAngles) do
        local rotatedDir = (CFrame.Angles(0, math.rad(angle), 0) * Vector3.new(moveDir.X, 0, moveDir.Z)).Unit
        local result = workspace:Raycast(myRoot.Position, rotatedDir * 12, rayParams)
        
        local freeDist = result and result.Distance or 12
        if freeDist > maxDist then
            maxDist = freeDist
            bestDir = rotatedDir
        end
    end
    return bestDir
end

-- --- UI Setup ---
Section:NewDropdown("Target Mode", "Mode", {"Manual", "Max HP", "Min HP"}, function(m) SelectedMode = m end)
local drop = Section:NewDropdown("Select Player", "Target", {}, function(s) 
    SelectedPlayerName = s:match("@([^%)]+)") 
end)

local function refresh()
    local t = {"None (Off)"}
    for _, p in pairs(Players:GetPlayers()) do 
        if p ~= LocalPlayer then table.insert(t, p.DisplayName.." (@"..p.Name..")") end 
    end
    drop:Refresh(t)
end
Section:NewButton("Refresh Players", "Update", refresh)
refresh()

local MoveSection = Tab:NewSection("Movement Control")
MoveSection:NewToggle("Enable Follow", "Start", function(state) followEnabled = state end)
MoveSection:NewSlider("Distance", "Gap", 20, 1, function(s) followDistance = s end)

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
                rayParams.FilterDescendantsInstances = {myChar, target.Character}
                local dist = (myRoot.Position - tRoot.Position).Magnitude
                local moveDir = (tRoot.Position - myRoot.Position).Unit
                
                -- ตรวจสอบการติด (Stuck)
                if (myRoot.Position - lastPos).Magnitude < 0.3 and myHuman.MoveDirection.Magnitude > 0 then
                    stuckTime = stuckTime + 0.1
                else
                    stuckTime = 0
                end
                lastPos = myRoot.Position

                if dist > followDistance then
                    -- ** 1. ระบบจัดการเมื่อติดมุม (Stuck Recovery) **
                    if detourTimer > 0 then
                        detourTimer = detourTimer - 0.1
                        myHuman:MoveTo(myRoot.Position + (lockedDir * 7))
                        continue
                    end

                    -- ตรวจสอบสิ่งกีดขวางข้างหน้า
                    local frontHit = workspace:Raycast(myRoot.Position, moveDir * 5, rayParams)

                    if stuckTime > 0.4 or frontHit then
                        -- ** ลองกระโดดเช็คก่อน 1 ครั้ง (Trial Jump) **
                        if jumpCooldown <= 0 then
                            myHuman.Jump = true
                            jumpCooldown = 10 -- คูลดาวน์โดด 1 วินาที (ป้องกันโดดไม่หยุด)
                            task.wait(0.2) -- รอดูผลลัพธ์การโดด
                        end
                        
                        -- ถ้ากระโดดแล้วยังติด (พิกัดไม่เปลี่ยน) ให้หักเลี้ยวทันที
                        if stuckTime > 0.5 then
                            local escape = scanSidePaths(myRoot, moveDir)
                            if escape then
                                lockedDir = escape
                                detourTimer = 1.2 -- ล็อกทางเบี่ยงไว้ 1.2 วินาที เพื่อให้พ้นมุม
                                myHuman:MoveTo(myRoot.Position + (lockedDir * 7))
                                stuckTime = 0
                            end
                        end
                    else
                        -- ทางสะดวก เดินไปหาเป้าหมายปกติ
                        myHuman:MoveTo(tRoot.Position)
                    end
                    
                    -- ลดคูลดาวน์กระโดด
                    if jumpCooldown > 0 then jumpCooldown = jumpCooldown - 1 end
                else
                    -- ถึงระยะแล้ว
                    myHuman:MoveTo(myRoot.Position)
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, Vector3.new(tRoot.Position.X, myRoot.Position.Y, tRoot.Position.Z))
                end
            end
        end
    end
end)
