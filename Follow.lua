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

-- ===================== FUNCTIONS =====================

-- Get player health
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

-- Update player list
local function UpdatePlayerTable()
    local tbl = {"None (Off)"}
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr.Name ~= game.Players.LocalPlayer.Name then
            table.insert(tbl, plr.Name)
        end
    end
    return tbl
end

-- ===================== UI =====================

Section:NewDropdown("Manual", "Choose how to find target",
    {"Manual", "Max HP", "Min HP", "Off"},
    function(mode)
        SelectedMode = mode
    end
)

local drop = Section:NewDropdown("None (Off)", "Manual selection",
    UpdatePlayerTable(),
    function(name)
        SelectedPlayer = (name ~= "None (Off)") and name or nil
    end
)

Section:NewButton("Refresh Dropdown", "Update list & Clear selection", function()
    drop:Refresh(UpdatePlayerTable())
    SelectedPlayer = nil
end)

Section:NewToggle("Use % Health Logic", "If ON, check health by percentage", function(state)
    UsePercentage = state
end)

-- ===================== MOVEMENT UI =====================

MoveSection:NewToggle("Enable Follow", "Start moving to target", function(state)
    followEnabled = state
end)

MoveSection:NewSlider("Follow Distance", "Distance from target", 20, 1, function(s)
    followDistance = s
end)

-- ===================== CORE =====================

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

        -- ===== MOVEMENT LOGIC =====
        if finalTarget
            and finalTarget.Character
            and finalTarget.Character:FindFirstChild("HumanoidRootPart") then

            local myChar = game.Players.LocalPlayer.Character
            local myHuman = myChar and myChar:FindFirstChild("Humanoid")
            local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
            local targetRoot = finalTarget.Character.HumanoidRootPart

            if myHuman and myRoot and targetRoot then
                local distance = (myRoot.Position - targetRoot.Position).Magnitude

                if distance > followDistance then
                    -- Raycast check
                    local ray = Ray.new(
                        myRoot.Position,
                        (targetRoot.Position - myRoot.Position).Unit * distance
                    )

                    local hit = workspace:FindPartOnRayWithIgnoreList(
                        ray,
                        {myChar, finalTarget.Character}
                    )

                    if not hit then
                        -- เดินตรง
                        myHuman:MoveTo(targetRoot.Position)
                    else
                        -- Pathfinding
                        local path = PathfindingService:CreatePath({
                            AgentCanJump = true,
                            AgentWaypointSpacing = 2
                        })

                        path:ComputeAsync(myRoot.Position, targetRoot.Position)

                        if path.Status == Enum.PathStatus.Success then
                            local waypoints = path:GetWaypoints()
                            local nextWaypoint = waypoints[3] or waypoints[2]

                            if nextWaypoint then
                                myHuman:MoveTo(nextWaypoint.Position)

                                if nextWaypoint.Action == Enum.PathfindingWaypointAction.Jump then
                                    myHuman.Jump = true
                                end
                            end
                        else
                            myHuman:MoveTo(targetRoot.Position)
                        end
                    end
                else
                    -- หยุดเมื่อถึงระยะ
                    myHuman:MoveTo(myRoot.Position)
                end
            end
        end
    end
end)
