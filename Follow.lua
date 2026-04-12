local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/xHeptc/Kavo-UI-Library/main/source.lua"))()

local Window = Library.CreateLib("KONG GUISUS", "DarkTheme")
local Tab = Window:NewTab("Main")

-- ===================== SECTIONS =====================

local Section = Tab:NewSection("Smart Follow Player")
local MoveSection = Tab:NewSection("Movement Control")

-- ===================== VARIABLES =====================

local SelectedMode = "Manual"
local SelectedPlayer = nil
local UsePercentage = false

local followDistance = 5
local followEnabled = false

local PathfindingService = game:GetService("PathfindingService")
local lastPathUpdate = 0 -- ไว้คุมจังหวะไม่ให้คิดทางเดินถี่เกินไป

-- ===================== FUNCTIONS =====================

local function getHealth(plr)
    local char = plr.Character
    if char and char:FindFirstChild("Humanoid") then
        if UsePercentage then
            return char.Humanoid.Health / char.Humanoid.MaxHealth
        else
            return char.Humanoid.Health
        end
    end
    return nil
end

local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr.Name ~= game.Players.LocalPlayer.Name then
            table.insert(tbl, plr.Name)
        end
    end
    return tbl
end

-- ===================== UI ELEMENTS =====================

Section:NewDropdown("Manual", "Choose how to find target",
    {"Manual", "Max HP", "Min HP", "Off"},
    function(mode)
        SelectedMode = mode
    end
)

local drop = Section:NewDropdown("None (Off)", "Manual selection",
    UpdatePlayerTable(),
    function(name)
        SelectedPlayer = (name == "None (Off)") and nil or name
    end
)

Section:NewButton("Refresh Dropdown", "Update list & Clear selection", function()
    local newList = UpdatePlayerTable()
    drop:Refresh(newList)
    SelectedPlayer = nil
end)

Section:NewToggle("Use % Health Logic", "If ON, check health by percentage", function(state)
    UsePercentage = state
end)

MoveSection:NewToggle("Enable Follow", "Start moving to target", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance from target", 20, 1, function(s)
    followDistance = s
end)

-- ===================== CORE LOGIC =====================

task.spawn(function()
    while task.wait(0.1) do
        if not followEnabled then continue end

        local finalTarget = nil

        -- ===== TARGET SELECTION =====
        if SelectedMode == "Manual" then
            finalTarget = game.Players:FindFirstChild(SelectedPlayer)
        elseif SelectedMode == "Max HP" then
            local highHealth = -1
            for _, p in pairs(game.Players:GetPlayers()) do
                if p ~= game.Players.LocalPlayer then
                    local hp = getHealth(p)
                    if hp and hp > highHealth then
                        highHealth = hp
                        finalTarget = p
                    end
                end
            end
        elseif SelectedMode == "Min HP" then
            local lowHealth = math.huge
            for _, p in pairs(game.Players:GetPlayers()) do
                if p ~= game.Players.LocalPlayer then
                    local hp = getHealth(p)
                    if hp and hp < lowHealth then
                        lowHealth = hp
                        finalTarget = p
                    end
                end
            end
        end

        -- ===== MOVEMENT LOGIC (Smooth & Smart) =====
        if finalTarget and finalTarget.Character and finalTarget.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = game.Players.LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local targetRoot = finalTarget.Character.HumanoidRootPart

            if myHuman and myRoot and targetRoot then
                local distance = (myRoot.Position - targetRoot.Position).Magnitude

                if distance > followDistance then
                    -- 1. เช็คว่าทางโล่งไหม (Raycast)
                    local rayDirection = (targetRoot.Position - myRoot.Position).Unit * distance
                    local raycastParams = RaycastParams.new()
                    raycastParams.FilterDescendantsInstances = {myChar, finalTarget.Character}
                    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
                    
                    local raycastResult = game.Workspace:Raycast(myRoot.Position, rayDirection, raycastParams)

                    if not raycastResult then
                        -- ทางโล่ง: วิ่งตรงๆ ไปหาเพื่อน (ลื่นที่สุด)
                        myHuman:MoveTo(targetRoot.Position)
                    else
                        -- ติดกำแพง: คำนวณทางเดิน (จำกัดให้คิดแค่ 1 ครั้งต่อ 0.5 วินาที)
                        if tick() - lastPathUpdate > 0.5 then
                            lastPathUpdate = tick()
                            
                            local path = PathfindingService:CreatePath({
                                AgentCanJump = true,
                                AgentWaypointSpacing = 3
                            })
                            path:ComputeAsync(myRoot.Position, targetRoot.Position)

                            if path.Status == Enum.PathStatus.Success then
                                local waypoints = path:GetWaypoints()
                                -- ข้ามไปเดินจุดที่ 3 เพื่อลดจังหวะชะงัก
                                local nextPoint = waypoints[3] or waypoints[2]
                                if nextPoint then
                                    myHuman:MoveTo(nextPoint.Position)
                                    if nextPoint.Action == Enum.PathfindingWaypointAction.Jump then
                                        myHuman.Jump = true
                                    end
                                end
                            else
                                -- ถ้าคำนวณไม่ได้จริงๆ ให้เดินหน้าตรงไปก่อน
                                myHuman:MoveTo(targetRoot.Position)
                            end
                        end
                    end
                else
                    -- ถึงระยะแล้วให้หยุดเดิน
                    myHuman:MoveTo(myRoot.Position)
                end
            end
        end
    end
end)
