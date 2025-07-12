-- =====================================================================================
-- DCS REINFORCED AUTO-RESUPPLY MISSION SCRIPT - COMPLETE VERSION
-- Description: Automated supply truck and helicopter missions for local SAM site replacement
-- Author: MythNZ
-- Version: 0.3.25 (Inital Release)
-- =====================================================================================

-- =====================================================================================
-- CONFIGURATION SECTION
-- =====================================================================================

local CONFIG = {

    CHECK_INTERVAL = 10, -- Interval for checking zones and units (in seconds)
    HELICOPTER_CHECK_INTERVAL = 3, -- Faster interval for helicopter monitoring (in seconds)
    DEBUG_MODE = 1, -- Debug levels: 0=off, 1=basic, 2=detailed, 3=verbose

    -- Zone Names (must match mission editor exactly)
    ZONES = {
        SUPPORT_HELO_DEPLOY = "SUPPORT_HELO_DEPLOY", -- Base name for helo deployment zones (supports numbered variants: SUPPORT_HELO_DEPLOY-1, SUPPORT_HELO_DEPLOY-2, etc.)
        SUPPORT_TRUCK_DEPLOY = "SUPPORT_TRUCK_DEPLOY", -- Base name for truck deployment zones (supports numbered variants: SUPPORT_TRUCK_DEPLOY-1, SUPPORT_TRUCK_DEPLOY-2, etc.)
        SUPPORT_AMMO_SUPPLY = "SUPPORT_AMMO_SUPPLY", -- Zone for spawning random cargo/ammo supplies
        SR_SAM_DEPLOYMENT_PREFIX = "SR_SAM", -- Prefix for short range SAM deployment zones
        LR_SAM_DEPLOYMENT_PREFIX = "LR_SAM", -- Prefix for long range SAM deployment zones
        MAX_DISTANCE_FROM_DEPLOY = 1000, -- Maximum distance from deployment zone to spawn SAM
        MAX_CONCURRENT_DEPLOYMENTS = 10 -- Maximum number of concurrent deployments
    },
    
    -- Coalition Mission Parameters
    RED_COALITION = coalition.side.RED,
    BLUE_COALITION = coalition.side.BLUE,

    -- Spawn Limits
    SPAWN_LIMITS = {
        TRUCK = 5,
        HELO = 5
    },

    -- Starting Supply Objects this will be divided across supply zones
    STARTING_SUPPLY_OBJECTS = 80, 
    
    -- SAM Deployment Settings
    SAM = {
        ACTIVATION_ATTEMPTS = 3,
        RETRY_DELAY = 2,
        UNIT_SPACING = 30,
        CLEANUP_DELAY = 15, -- Increased to 15 seconds for ultra-safe vehicle cleanup after SAM deployment (especially for helicopters)
        ENABLE_VEHICLE_CLEANUP = true, -- Re-enabled with safer cleanup method

        POSITION_RANDOMIZATION = {
            ENABLED = true,
            MAX_OFFSET = 15, -- Maximum random offset in meters
            MIN_DISTANCE = 8  -- Minimum distance between units
        }
    },
    
    -- Vehicle Route Settings
    VEHICLE = {
        TRUCK_SPEED = 20,
        HELO_SPEED = 50,
        HELO_ALTITUDE = 500,
        ENABLE_HELICOPTER_SPAWNING = true
    },

    SAM_UNITS = {
        SHORT_RANGE = {
            [country.id.CJTF_BLUE] = {
                { type = "M 818", skill = "High" },
                { type = "NASAMS_Command_Post", skill = "High" },
                { type = "NASAMS_Radar_MPQ64F1", skill = "High" },
                { type = "NASAMS_LN_B", skill = "High" }
            },
            [country.id.CJTF_RED] = {
                { type = "Ural-4320-31", skill = "High" },
                { type = "5p73 s-125 ln", skill = "High" },  -- Short range launcher unit
                { type = "5p73 s-125 ln", skill = "High" },  -- Short range launcher unit
                { type = "snr s-125 tr", skill = "High" },  -- Short range Track radar unit
                { type = "p-19 s-125 sr", skill = "High" },  -- Short range Search radar unit

            }
        },
        LONG_RANGE = {
            [country.id.CJTF_BLUE] = {
                { type = "M 818", skill = "High" },
                { type = "Hawk cwar", skill = "High" },
                { type = "Hawk ln", skill = "High" },
                { type = "Hawk ln", skill = "High" },
                { type = "Hawk pcp", skill = "High" },
                { type = "Hawk sr", skill = "High" },
                { type = "Hawk tr", skill = "High" },
            },
            [country.id.CJTF_RED] = {
                { type = "Ural-4320-31", skill = "High" }, 
                { type = "Kub 2P25 ln", skill = "High" },  -- Medium range launcher unit
                { type = "Kub 2P25 ln", skill = "High" },  -- Medium range launcher unit
                { type = "Kub 2P25 ln", skill = "High" },  -- Medium range launcher unit
                { type = "Kub 1S91 str", skill = "High" },  -- Medium range Search Track Radar unit
                { type = "Kub 1S91 str", skill = "High" },  -- Medium range Search Track Radar unit
            }
        },
    },

    -- Supply Vehicle Configurations
    SUPPLY_VEHICLES = {
        TRUCK = {
            [country.id.CJTF_BLUE] = {
                { type = "M 818", skill = "High" },
                -- { type = "Hummer", skill = "High" },
                -- { type = "M1043 HMMWV Armament", skill = "High" }
            },
            [country.id.CJTF_RED] = {
                { type = "Ural-375", skill = "High" },
                -- { type = "UAZ-469", skill = "High" },
                -- { type = "Ural-4320-31", skill = "High" }
            }
        },
        HELICOPTER = {
            [country.id.CJTF_BLUE] = {
                { type = "Mi-8MT", skill = "High", livery = nil },
                -- { type = "UH-1H", skill = "High", livery = nil }
            },
            [country.id.CJTF_RED] = {
                { type = "Mi-8MT", skill = "High", livery = nil }
                -- Note: Only Mi-8MT is used to prevent DCS crashes with complex helicopter types
            }
        }
    },

    AVAILABLE_SUPPLY_OBJECT_TYPES = {
        { type = "ammo_cargo", name = "Ammo Crate" },
        { type = "fueltank", name = "Fuel Tank" },
        { type = "iso_container", name = "ISO Container" },
        { type = "iso_container_small", name = "Small Container" },
        { type = "container_cargo", name = "Cargo Container" },
        { type = "f_bar_cargo", name = "F-Bar Cargo" },
        { type = "iso_container_small", name = "Supply Box" }
    }
}

-- =====================================================================================
-- STATE MANAGEMENT
-- =====================================================================================

local MissionState = {
    -- Vehicle Groups 
    vehicles = {
        truck = nil,  -- Legacy single truck reference
        helo = nil,   -- Legacy single helo reference
        supplyGroups = {}  -- New: Track multiple supply groups by zone
    },
    
    -- Deployment Zones 
    zones = {
        srSamZones = {},  -- Short range SAM deployment zones
        lrSamZones = {},  -- Long range SAM deployment zones
        truckSpawnZones = {},  -- Multiple truck spawn zones (SUPPORT_TRUCK_DEPLOY, SUPPORT_TRUCK_DEPLOY-1, etc.)
        heloSpawnZones = {},   -- Multiple helo spawn zones (SUPPORT_HELO_DEPLOY, SUPPORT_HELO_DEPLOY-1, etc.)
        ammoSpawnZones = {},  -- Multiple ammo supply zones for supply cargo spawning
        truckSpawn = nil,  -- Legacy single truck spawn zone
        heloSpawn = nil   -- Legacy single helo spawn zone
    },
    
    -- Mission Status
    missions = {
        truck = {
            spawnCount = CONFIG.SPAWN_LIMITS.TRUCK
        },
        helo = {
            spawnCount = CONFIG.SPAWN_LIMITS.HELO
        },
        -- Zone-specific mission states
        zoneStates = {}  -- Will contain per-zone mission status
    },
    
    -- Zone Monitoring
    monitoring = {
        activeZones = {},  -- Zones currently being monitored
        monitoringActive = false
    },
    
    -- Unit Tracking
    originalUnitsInZone = {},
    spawnedCargo = {},  -- Track currently spawned cargo objects
    cargoSpawnCount = 0, -- Counter for unique cargo naming
    gridStates = {},    -- Track grid positioning state for each ammo supply zone
    
    -- Group cache for reducing coalition.getGroups() calls
    groupCache = {
        groundGroups = {},
        lastUpdate = 0,
        updateInterval = 5 -- Update cache every 5 seconds
    },
    
    -- System Status
    initialized = false
}

-- =====================================================================================
-- UTILITY FUNCTIONS
-- =====================================================================================

local Utils = {}

function Utils.showMessage(text, duration)
    duration = duration or 10
    trigger.action.outText(text, duration)
end

function Utils.showDebugMessage(text, duration, level)
    level = level or 1  -- Default to level 1 if not specified
    if CONFIG.DEBUG_MODE >= level then
        duration = duration or 5
        trigger.action.outText("DEBUG L" .. level .. ": " .. text, duration)
    end
end

function Utils.getDistance(point1, point2)
    local dx = point1.x - point2.x
    local dz = point1.z - point2.z
    return math.sqrt(dx * dx + dz * dz)
end

function Utils.isPointInZone(point, zone)
    if not point or not zone or not zone.point or not zone.radius then
        return false
    end
    local zonePoint = {x = zone.point.x, z = zone.point.z}
    local distance = Utils.getDistance(point, zonePoint)
    return distance <= zone.radius
end

function Utils.getGroupByName(groupName)
    return Group.getByName(groupName)
end

function Utils.getZoneByName(zoneName)
    return trigger.misc.getZone(zoneName)
end

function Utils.safeExecute(operation, errorMessage)
    local success, result = pcall(operation)
    if not success then
        Utils.showMessage("ERROR: " .. errorMessage, 10)
        return false, nil
    end
    return true, result
end

function Utils.getMissionOverview()
    local truckStatus = MissionState.missions.truck.samDeployed and "COMPLETED" or 
                       (MissionState.missions.truck.active and "IN PROGRESS" or "READY")
    local heloStatus = MissionState.missions.helo.samDeployed and "COMPLETED" or 
                      (MissionState.missions.helo.active and "IN PROGRESS" or "READY")
    
    return {
        truck = {
            status = truckStatus,
            spawnsRemaining = MissionState.missions.truck.spawnCount
        },
        helo = {
            status = heloStatus,
            spawnsRemaining = MissionState.missions.helo.spawnCount
        }
    }
end

function Utils.getGroundGroupsSafe()
    local currentTime = timer.getTime()
    
    -- Update cache if it's older than the update interval or empty
    if currentTime - MissionState.groupCache.lastUpdate > MissionState.groupCache.updateInterval or 
       #MissionState.groupCache.groundGroups == 0 then
        
        MissionState.groupCache.groundGroups = {}
        
        local success, allGroups = pcall(coalition.getGroups, coalition.side.RED, Group.Category.GROUND)
        if success and allGroups then
            for _, group in pairs(allGroups) do
                if group and group:isExist() then
                    table.insert(MissionState.groupCache.groundGroups, group)
                end
            end
        else
            Utils.showDebugMessage("Failed to get ground groups safely", 5)
        end
        
        MissionState.groupCache.lastUpdate = currentTime
        Utils.showDebugMessage("Updated ground groups cache: " .. #MissionState.groupCache.groundGroups .. " groups", 2,3)
    end
    
    return MissionState.groupCache.groundGroups
end

function Utils.countActiveDeployments()
    local activeCount = 0
    
    -- Count active supply groups tracked by zone
    for zoneName, supplyGroup in pairs(MissionState.vehicles.supplyGroups) do
        if supplyGroup == "DEPLOYMENT_PENDING" then
            -- Count pending deployments to prevent race condition
            activeCount = activeCount + 1
            Utils.showDebugMessage("Zone " .. zoneName .. " has pending deployment", 2, 2)
        elseif supplyGroup and supplyGroup:isExist() then
            activeCount = activeCount + 1
        else
            -- Clean up dead references (but not pending deployments)
            if supplyGroup ~= "DEPLOYMENT_PENDING" then
                MissionState.vehicles.supplyGroups[zoneName] = nil
            end
        end
    end
    
    Utils.showDebugMessage("Active deployments: " .. activeCount .. "/" .. CONFIG.ZONES.MAX_CONCURRENT_DEPLOYMENTS, 3,3)
    return activeCount
end

function Utils.getSupplyTruckUnits(coalitionId)
    if CONFIG.SUPPLY_VEHICLES.TRUCK[coalitionId] then
        return CONFIG.SUPPLY_VEHICLES.TRUCK[coalitionId]
    else
        -- Fallback to RED coalition if specific coalition not found
        Utils.showDebugMessage("Coalition " .. coalitionId .. " not found for trucks, using RED fallback", 5)
        return CONFIG.SUPPLY_VEHICLES.TRUCK[country.id.CJTF_RED] or {}
    end
end

function Utils.getSupplyHeloUnits(coalitionId)
    if CONFIG.SUPPLY_VEHICLES.HELICOPTER[coalitionId] then
        return CONFIG.SUPPLY_VEHICLES.HELICOPTER[coalitionId]
    else
        -- Fallback to RED coalition if specific coalition not found
        Utils.showDebugMessage("Coalition " .. coalitionId .. " not found for helicopters, using RED fallback", 5)
        return CONFIG.SUPPLY_VEHICLES.HELICOPTER[country.id.CJTF_RED] or {}
    end
end

-- Helicopter crash prevention utilities
function Utils.validateHeloGroupData(groupData)
    -- Comprehensive validation to prevent DCS crashes
    if not groupData then
        return false, "Group data is nil"
    end
    
    if not groupData.name or groupData.name == "" then
        return false, "Invalid group name"
    end
    
    if not groupData.units or type(groupData.units) ~= "table" or #groupData.units == 0 then
        return false, "No valid units in group"
    end
    
    if not groupData.route or not groupData.route.points or #groupData.route.points < 2 then
        return false, "Invalid route data"
    end
    
    for i, unit in ipairs(groupData.units) do
        if not unit.type or unit.type == "" then
            return false, "Unit " .. i .. " has invalid type"
        end
        
        if not unit.unitId or unit.unitId <= 0 then
            return false, "Unit " .. i .. " has invalid unitId"
        end
        
        if not unit.x or not unit.y then
            return false, "Unit " .. i .. " has invalid position"
        end
    end
    
    return true, "Valid"
end

function Utils.createSafeHeloGroupData(uniqueGroupName, spawnPoint, route, heloType)
    -- Create the safest possible helicopter group data structure
    local safeGroupData = {
        -- Core group properties
        ["name"] = uniqueGroupName,
        ["task"] = "Nothing",  -- Safest task type
        ["visible"] = false,
        ["uncontrollable"] = false,
        ["lateActivation"] = false,
        ["hidden"] = false,
        ["start_time"] = 0,
        ["groupId"] = math.random(50000, 99999),
        
        -- Position
        ["x"] = spawnPoint.x,
        ["y"] = spawnPoint.z,
        
        -- Communication
        ["communication"] = true,
        ["frequency"] = 251,
        
        -- Route (keep it simple)
        ["route"] = route,
        
        -- Units array
        ["units"] = {}
    }
    
    -- Add single unit (safest approach)
    local unitData = {
        ["type"] = heloType,
        ["unitId"] = math.random(500000, 999999),
        ["name"] = uniqueGroupName .. "_Unit_1",
        ["skill"] = "High",
        ["x"] = spawnPoint.x,
        ["y"] = spawnPoint.z,
        ["alt"] = spawnPoint.alt or 1000,
        ["alt_type"] = "BARO",
        ["heading"] = 0,
        ["speed"] = 0,
        ["playerCanDrive"] = false,
        ["onboard_num"] = "001",
        ["AddPropAircraft"] = {},
        ["parking"] = nil,
        ["parking_id"] = nil,
    }
    
    table.insert(safeGroupData.units, unitData)
    
    return safeGroupData
end

-- =====================================================================================
-- LOCAL FUNCTIONS (Forward Declaration)
-- =====================================================================================

local SAMDeployment = {}
local ZoneDiscovery = {}
local ZoneMonitoring = {}
local VehicleSpawning = {}
local RadioMenu = {}
local CargoManagement = {}

-- =====================================================================================
-- SAM DEPLOYMENT SYSTEM
-- =====================================================================================

function SAMDeployment.moveGroupToZone(group, targetZone)
    if not group or not group:isExist() or not targetZone then
        Utils.showDebugMessage("moveGroupToZone failed - invalid parameters", 5, 3)
        Utils.showDebugMessage("Group: " .. tostring(group) .. ", Zone: " .. tostring(targetZone), 5, 3)
        return false
    end
    
    Utils.showDebugMessage("Moving group '" .. group:getName() .. "' to zone", 5, 3)
    Utils.showDebugMessage("Target zone coordinates: x=" .. targetZone.point.x .. ", z=" .. targetZone.point.z, 5, 3)
    
    local routePoints = {
        {
            x = targetZone.point.x,
            y = targetZone.point.z,
            alt = 0,
            type = "Turning Point",
            ETA = 0,
            ETA_locked = false,
            speed = 0,
            speed_locked = true,
            formation_template = "",
            task = {
                id = "ComboTask",
                params = { tasks = {} }
            }
        }
    }
    
    local mission = {
        id = "Mission",
        params = {
            route = { points = routePoints }
        }
    }
    
    local controller = group:getController()
    if controller then
        Utils.showDebugMessage("Group controller found, setting task", 5, 3)
        local success = Utils.safeExecute(function()
            controller:setTask(mission)
            return true
        end, "Failed to set group movement task")
        
        if success then
            Utils.showDebugMessage("Group movement task set successfully", 5,3)
            return true
        else
            Utils.showDebugMessage("Failed to set movement task", 5)
            return false
        end
    else
        Utils.showDebugMessage("Group controller not found", 5)
        return false
    end
end

function SAMDeployment.scheduleVehicleCleanup(missionType, zoneName)
    -- Check if cleanup is enabled
    if not CONFIG.SAM.ENABLE_VEHICLE_CLEANUP then
        Utils.showDebugMessage("Vehicle cleanup disabled in configuration - vehicles will remain active", 5,3)
        return
    end
    
    local isHeloMission = (missionType == "helicopter")
    
    Utils.showDebugMessage("Scheduling ultra-safe vehicle cleanup for " .. missionType .. " mission in zone " .. (zoneName or "unknown"), 5 ,3)
   
    timer.scheduleFunction(function()
        Utils.showDebugMessage("Vehicle cleanup timer executed for " .. missionType .. " in zone " .. (zoneName or "unknown"), 8,3)
        
        if isHeloMission then
            -- Ultra-safe cleanup of helicopter for this specific zone only
            if zoneName and MissionState.vehicles.supplyGroups[zoneName] then

                local supplyGroup = MissionState.vehicles.supplyGroups[zoneName]
                if supplyGroup and supplyGroup ~= "DEPLOYMENT_PENDING" then
                    local groupName = "unknown"
                    local success, nameResult = pcall(function() return supplyGroup:getName() end)
                    if success then
                        groupName = nameResult
                    end
                    
                    -- Use simpler and more reliable cleanup approach
                    local cleanupSuccess = pcall(function()
                        if supplyGroup:isExist() then                          
                            -- Method 1: Try immediate destruction (simplest and most reliable)
                            supplyGroup:destroy()  
                        end
                    end)
                    
                    if cleanupSuccess then
                        -- Utils.showMessage("Supply helicopter '" .. groupName .. "' completed mission for zone " .. zoneName .. " and returned to base.", 8)
                    else
                        Utils.showDebugMessage("Failed to initiate helicopter cleanup: " .. groupName, 5)
                    end
                end
                
                -- Remove from supply groups tracking to free up deployment slot
                MissionState.vehicles.supplyGroups[zoneName] = nil
                Utils.showDebugMessage("Removed helicopter supply group for zone " .. zoneName .. " from tracking", 5,3)
            else
                Utils.showDebugMessage("DEBUG: No helicopter supply group found for cleanup in zone " .. (zoneName or "unknown"), 8,3)
            end
            
            -- Update zone-specific state only
            if zoneName and MissionState.missions.zoneStates[zoneName] then
                MissionState.missions.zoneStates[zoneName].heloActive = false
            end
            
            -- Only clear legacy references if this was the legacy mission (no specific zone)
            if not zoneName then
                MissionState.vehicles.helo = nil
                MissionState.missions.helo.active = false
            end
        else
            -- Ultra-safe cleanup of truck for this specific zone only
            if zoneName and MissionState.vehicles.supplyGroups[zoneName] then
                local supplyGroup = MissionState.vehicles.supplyGroups[zoneName]
                if supplyGroup and supplyGroup ~= "DEPLOYMENT_PENDING" then
                    local groupName = "unknown"
                    local success, nameResult = pcall(function() return supplyGroup:getName() end)
                    if success then
                        groupName = nameResult
                    end
                    
                    -- Use simpler and more reliable cleanup approach
                    local cleanupSuccess = pcall(function()
                        if supplyGroup:isExist() then
                            supplyGroup:destroy()
                        end
                    end)
                    
                    if cleanupSuccess then
                        -- Utils.showMessage("Supply truck '" .. groupName .. "' completed mission for zone " .. zoneName .. " and withdrew.", 8)
                    else
                        Utils.showDebugMessage("Failed to initiate truck cleanup: " .. groupName, 5, 3)
                    end
                end
                
                -- Remove from supply groups tracking to free up deployment slot
                MissionState.vehicles.supplyGroups[zoneName] = nil
                Utils.showDebugMessage("Removed truck supply group for zone " .. zoneName .. " from tracking", 5,3)
            else
                Utils.showDebugMessage("DEBUG: No truck supply group found for cleanup in zone " .. (zoneName or "unknown"), 8)
            end
            
            -- Update zone-specific state only
            if zoneName and MissionState.missions.zoneStates[zoneName] then
                MissionState.missions.zoneStates[zoneName].truckActive = false
            end
            
            -- Only clear legacy references if this was the legacy mission (no specific zone)
            if not zoneName then
                MissionState.vehicles.truck = nil
                MissionState.missions.truck.active = false
            end
        end
        
        Utils.showDebugMessage("Vehicle cleanup completed for " .. missionType .. " mission in zone " .. (zoneName or "legacy"), 5,3)
        return nil
    end, nil, timer.getTime() + CONFIG.SAM.CLEANUP_DELAY)
    
    Utils.showDebugMessage("Vehicle cleanup timer scheduled for " .. CONFIG.SAM.CLEANUP_DELAY .. " seconds", 5,3)
end

-- =====================================================================================
-- ZONE DISCOVERY SYSTEM
-- =====================================================================================

-- Discover all deployment zones with the configured prefixes
function ZoneDiscovery.discoverDeploymentZones()
    Utils.showDebugMessage("=== DISCOVERING DEPLOYMENT ZONES ===", 5,2)
    
    local srZones = {}
    local lrZones = {}
    local totalZones = 0
    
    -- Get all trigger zones in the mission
    local env = _G.env or {}
    if env.mission and env.mission.triggers and env.mission.triggers.zones then
        for _, zone in pairs(env.mission.triggers.zones) do
            if zone.name then
                local zoneName = zone.name
                
                -- Check for short range SAM zones
                if string.find(zoneName, "^" .. CONFIG.ZONES.SR_SAM_DEPLOYMENT_PREFIX) then
                    local zoneObj = trigger.misc.getZone(zoneName)
                    if zoneObj then
                        table.insert(srZones, {
                            name = zoneName,
                            zone = zoneObj,
                            type = "SHORT_RANGE",
                            active = true
                        })
                       -- Utils.showDebugMessage("Found short range SAM zone: " .. zoneName, 5)
                        totalZones = totalZones + 1
                    end
                end
                
                -- Check for long range SAM zones
                if string.find(zoneName, "^" .. CONFIG.ZONES.LR_SAM_DEPLOYMENT_PREFIX) then
                    local zoneObj = trigger.misc.getZone(zoneName)
                    if zoneObj then
                        table.insert(lrZones, {
                            name = zoneName,
                            zone = zoneObj,
                            type = "LONG_RANGE",
                            active = true
                        })
                        -- Utils.showDebugMessage("Found long range SAM zone: " .. zoneName, 5)
                        totalZones = totalZones + 1
                    end
                end
            end
        end
    end
    
    -- Fallback: Try to get zones by name pattern (less reliable but worth trying)
    if totalZones == 0 then
        Utils.showDebugMessage("No zones found via mission data, trying name-based discovery...", 8,2)
        
        -- Try common naming patterns
        for i = 0, 20 do  -- Check up to 20 numbered zones
            local suffix = (i == 0) and "" or ("-" .. i)
            
            -- Short range zones
            local srZoneName = CONFIG.ZONES.SR_SAM_DEPLOYMENT_PREFIX .. suffix
            local srZone = trigger.misc.getZone(srZoneName)
            if srZone then
                table.insert(srZones, {
                    name = srZoneName,
                    zone = srZone,
                    type = "SHORT_RANGE",
                    active = true
                })
                Utils.showDebugMessage("Found short range SAM zone: " .. srZoneName, 5)
                totalZones = totalZones + 1
            end
            
            -- Long range zones
            local lrZoneName = CONFIG.ZONES.LR_SAM_DEPLOYMENT_PREFIX .. suffix
            local lrZone = trigger.misc.getZone(lrZoneName)
            if lrZone then
                table.insert(lrZones, {
                    name = lrZoneName,
                    zone = lrZone,
                    type = "LONG_RANGE",
                    active = true
                })
                Utils.showDebugMessage("Found long range SAM zone: " .. lrZoneName, 5)
                totalZones = totalZones + 1
            end
        end
    end
    
    -- Store discovered zones
    MissionState.zones.srSamZones = srZones
    MissionState.zones.lrSamZones = lrZones
    
    -- Initialize zone states
    for _, zoneInfo in pairs(srZones) do
        MissionState.missions.zoneStates[zoneInfo.name] = {
            truckActive = false,
            heloActive = false,
            samDeployed = false,
            lastCheckTime = 0,
            unitsCount = 0
        }
    end
    
    for _, zoneInfo in pairs(lrZones) do
        MissionState.missions.zoneStates[zoneInfo.name] = {
            truckActive = false,
            heloActive = false,
            samDeployed = false,
            lastCheckTime = 0,
            unitsCount = 0
        }
    end
    
    Utils.showMessage("Discovered " .. #srZones .. " short range and " .. #lrZones .. " long range SAM zones (" .. totalZones .. " total)", 8)
    
    if totalZones == 0 then
        Utils.showMessage("ERROR: No deployment zones found! Please check zone naming.", 10)
        return false
    end
    
    return true
end

-- Get the appropriate SAM unit configuration for a zone
function ZoneDiscovery.getSAMUnitsForZone(zoneName)
    local zoneInfo = ZoneDiscovery.getZoneInfo(zoneName)
    if not zoneInfo then
        Utils.showDebugMessage("Zone info not found for: " .. zoneName, 3)
        return nil
    end
    
    local samType = zoneInfo.type
    local coalition = CONFIG.RED_COALITION
    local countryId = country.id.CJTF_RED
    
    if CONFIG.SAM_UNITS[samType] and CONFIG.SAM_UNITS[samType][countryId] then
        return CONFIG.SAM_UNITS[samType][countryId]
    end
    
    Utils.showDebugMessage("No SAM units configured for type: " .. samType .. " and coalition: " .. countryId, 3)
    return nil
end

-- Get zone information by name
function ZoneDiscovery.getZoneInfo(zoneName)
    -- Check short range zones
    for _, zoneInfo in pairs(MissionState.zones.srSamZones) do
        if zoneInfo.name == zoneName then
            return zoneInfo
        end
    end
    
    -- Check long range zones
    for _, zoneInfo in pairs(MissionState.zones.lrSamZones) do
        if zoneInfo.name == zoneName then
            return zoneInfo
        end
    end
    
    return nil
end

-- Get all active deployment zones
function ZoneDiscovery.getAllActiveZones()
    local allZones = {}
    
    for _, zoneInfo in pairs(MissionState.zones.srSamZones) do
        if zoneInfo.active then
            table.insert(allZones, zoneInfo)
        end
    end
    
    for _, zoneInfo in pairs(MissionState.zones.lrSamZones) do
        if zoneInfo.active then
            table.insert(allZones, zoneInfo)
        end
    end
    
    return allZones
end

-- =====================================================================================
-- ZONE MONITORING SYSTEM IMPLEMENTATION
-- =====================================================================================

-- Start monitoring all deployment zones
function ZoneMonitoring.startMultiZoneMonitoring()
    if MissionState.monitoring.monitoringActive then
        Utils.showMessage("Multi-zone monitoring already active!", 5)
        return
    end
    
    MissionState.monitoring.monitoringActive = true
    
    local function monitorAllZones()
        if not MissionState.monitoring.monitoringActive then
            return nil -- Stop monitoring
        end
        
        local allZones = ZoneDiscovery.getAllActiveZones()
        if #allZones == 0 then
            Utils.showDebugMessage("No active zones to monitor!", 5)
            return timer.getTime() + CONFIG.CHECK_INTERVAL
        end
        
        for _, zoneInfo in pairs(allZones) do
            ZoneMonitoring.checkSingleZone(zoneInfo)
        end
        
        return timer.getTime() + CONFIG.CHECK_INTERVAL
    end
    
    timer.scheduleFunction(monitorAllZones, nil, timer.getTime() + CONFIG.CHECK_INTERVAL + 2) -- Add 2 second delay
end

-- Check a single zone for units and dispatch vehicles if needed
function ZoneMonitoring.checkSingleZone(zoneInfo)
    if not zoneInfo or not zoneInfo.zone or not zoneInfo.name then
        return
    end
    
    local zoneName = zoneInfo.name
    local zone = zoneInfo.zone
    local zoneState = MissionState.missions.zoneStates[zoneName]
    
    if not zoneState then
        Utils.showDebugMessage("Zone state not found for: " .. zoneName, 3)
        return
    end
    
    -- Count units in zone (excluding supply vehicles) using cached groups
    local unitsInZone = {}
    local allGroups = Utils.getGroundGroupsSafe()
    
    for _, group in pairs(allGroups) do
        if group and group:isExist() then
            local groupName = group:getName()
            -- Skip supply vehicles (dynamic names pattern)
            if not string.find(groupName, "SupplyTruck_") and not string.find(groupName, "SupplyHelo_") then
                local success, units = pcall(group.getUnits, group)
                if success and units then
                    for _, unit in pairs(units) do
                        if unit and unit:isExist() then
                            local success2, unitPos = pcall(function() return unit:getPosition().p end)
                            if success2 and unitPos and Utils.isPointInZone(unitPos, zone) then
                                table.insert(unitsInZone, unit)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Utils.showDebugMessage("Zone " .. zoneName .. " check - " .. #unitsInZone .. " RED units found", 2)
    zoneState.unitsCount = #unitsInZone
    
    -- Enhanced debugging for zone clearing
    if #unitsInZone == 0 and not zoneState.samDeployed then
       -- Utils.showMessage("DEBUG: Zone " .. zoneName .. " is clear and ready for supply mission!", 8)
    end
    
    if not zoneState.samDeployed then
        -- Phase 1: Monitor for zone clearing to dispatch supply vehicle
        if #unitsInZone == 0 then
            -- Check if this zone already has a supply mission active
            local zoneHasSupplyMission = false
            if MissionState.vehicles.supplyGroups[zoneName] then
                local supplyGroup = MissionState.vehicles.supplyGroups[zoneName]
                if supplyGroup and supplyGroup:isExist() then
                    zoneHasSupplyMission = true
                    Utils.showDebugMessage("Zone " .. zoneName .. " already has active supply mission", 3,3)
                else
                    -- Clean up dead reference
                    MissionState.vehicles.supplyGroups[zoneName] = nil
                end
            end
            
            if not zoneHasSupplyMission then
                -- Check if we've reached the maximum concurrent deployments limit
                local activeDeployments = Utils.countActiveDeployments()
                if activeDeployments >= CONFIG.ZONES.MAX_CONCURRENT_DEPLOYMENTS then
                    Utils.showDebugMessage("Zone " .. zoneName .. " clear but max concurrent deployments (" .. CONFIG.ZONES.MAX_CONCURRENT_DEPLOYMENTS .. ") reached. Waiting for deployment slots...", 5,3)
                    return -- Skip this zone for now
                end
                
                -- RACE CONDITION FIX: Reserve the deployment slot immediately
                -- Create a placeholder to prevent other zones from spawning simultaneously
                MissionState.vehicles.supplyGroups[zoneName] = "DEPLOYMENT_PENDING"
                Utils.showDebugMessage("Reserved deployment slot for zone " .. zoneName, 5,2)
                
                -- Determine optimal vehicle type based on distance from deploy zones
                local optimalVehicleType = VehicleSpawning.determineOptimalVehicleType(zone)
                
                -- Check if the optimal vehicle type is available
                local canDispatchOptimal = false
                local canDispatchAlternate = false
                
                if optimalVehicleType == "truck" then
                    canDispatchOptimal = (MissionState.missions.truck.spawnCount > 0)
                    canDispatchAlternate = (MissionState.missions.helo.spawnCount > 0)
                else -- optimalVehicleType == "helo"
                    canDispatchOptimal = (MissionState.missions.helo.spawnCount > 0)
                    canDispatchAlternate = (MissionState.missions.truck.spawnCount > 0)
                end
                
                -- Dispatch based on availability and preference
                if canDispatchOptimal then
                    if optimalVehicleType == "truck" then
                        VehicleSpawning.spawnTruckForZone(zoneInfo)
                    else
                        VehicleSpawning.spawnHeloForZone(zoneInfo)
                    end
                elseif canDispatchAlternate then
                    if optimalVehicleType == "truck" then
                        VehicleSpawning.spawnHeloForZone(zoneInfo)
                    else
                        VehicleSpawning.spawnTruckForZone(zoneInfo)
                    end
                else
                    -- No spawns available - release the reserved slot
                    MissionState.vehicles.supplyGroups[zoneName] = nil
                    Utils.showDebugMessage("No spawns remaining for zone " .. zoneName .. ", released deployment slot", 5)
                end
            end
        end
    else
        -- Phase 2: Monitor for SAM destruction to enable re-deployment
        if #unitsInZone == 0 then
            Utils.showDebugMessage("SAM site in zone " .. zoneName .. " has been destroyed! Re-deployment now available.", 10,2)
            zoneState.samDeployed = false
            -- Reset spawn counts to enable continuous resupply
            MissionState.missions.truck.spawnCount = CONFIG.SPAWN_LIMITS.TRUCK
            MissionState.missions.helo.spawnCount = CONFIG.SPAWN_LIMITS.HELO
            Utils.showDebugMessage("Spawn counts replenished for zone " .. zoneName .. ". Resuming monitoring for enemy elimination...", 8,2)
        end
    end
end

function ZoneMonitoring.stopMultiZoneMonitoring()
    MissionState.monitoring.monitoringActive = false
    Utils.showMessage("Stopped multi-zone monitoring.", 5)
end

-- =====================================================================================
-- SAM DEPLOYMENT FUNCTIONS 
-- Dependancy ZoneMonitoring
-- =====================================================================================

function SAMDeployment.spawnManually(templateName, targetZone, missionType, zoneName)
    
    local isHeloMission = (missionType == "helicopter")
    
    local samUnits = {}
    
    -- Get zone-specific SAM units
    if zoneName then
        samUnits = ZoneDiscovery.getSAMUnitsForZone(zoneName) or {}
        if #samUnits > 0 then
            Utils.showDebugMessage("Using " .. #samUnits .. " zone-specific SAM units for " .. zoneName, 5, 2)
        end
    end
    
    -- Debug Message if no units found
    if #samUnits == 0 then
        Utils.showDebugMessage("No units were spawned - no SAM configuration found for zone", 5)
        return false
    end
    
    local spawnData = {
        ["visible"] = false,
        ["tasks"] = {},
        ["uncontrollable"] = false,
        ["task"] = "Ground Nothing",
        ["taskSelected"] = true,
        ["route"] = {
            ["spans"] = {},
            ["points"] = {
                [1] = {
                    ["alt"] = 0,
                    ["type"] = "Turning Point",
                    ["ETA"] = 0,
                    ["alt_type"] = "BARO",
                    ["formation_template"] = "",
                    ["y"] = targetZone.point.z,
                    ["x"] = targetZone.point.x,
                    ["ETA_locked"] = false,
                    ["speed"] = 0,
                    ["action"] = "Off Road",
                    ["task"] = {
                        ["id"] = "ComboTask",
                        ["params"] = { ["tasks"] = {} }
                    },
                    ["speed_locked"] = true,
                }
            }
        },
        ["groupId"] = math.random(1000, 9999),
        ["hidden"] = false,
        ["units"] = {},
        ["y"] = targetZone.point.z,
        ["x"] = targetZone.point.x,
        ["name"] = "SAM_Site_" .. missionType .. "_" .. math.random(100, 999),
        ["start_time"] = 0,
    }
    
    -- Add units to spawn data
    for i, samUnit in ipairs(samUnits) do
        local unitX, unitZ
        
        -- Use cached relative positions if available, otherwise use linear spacing
        if samUnit.relativeX ~= nil and samUnit.relativeZ ~= nil then
            -- Use original template formation with randomization
            unitX = targetZone.point.x + samUnit.relativeX
            unitZ = targetZone.point.z + samUnit.relativeZ
            
            Utils.showDebugMessage("Using template position for unit " .. i .. ": base offset (" .. samUnit.relativeX .. ", " .. samUnit.relativeZ .. ")", 5)
        else
            -- Fallback to circular spacing around the first unit
            if i == 1 then
                -- First unit at zone center
                unitX = targetZone.point.x
                unitZ = targetZone.point.z
            else
                -- Calculate circular position for subsequent units
                local angle = (i - 2) * (2 * math.pi / (#samUnits - 1)) -- Distribute remaining units evenly in circle
                local radius = CONFIG.SAM.UNIT_SPACING
                
                -- Add some randomization to the angle for variation
                if CONFIG.SAM.POSITION_RANDOMIZATION.ENABLED then
                    local angleVariation = (math.random() - 0.5) * 0.5 -- ±0.25 radians (~14 degrees)
                    angle = angle + angleVariation
                end
                
                unitX = targetZone.point.x + (radius * math.cos(angle))
                unitZ = targetZone.point.z + (radius * math.sin(angle))
                
                Utils.showDebugMessage("Circular position for unit " .. i .. ": angle=" .. math.deg(angle) .. "°, radius=" .. radius .. "m", 5, 3)
            end
        end
        
        -- Apply randomization if enabled
        if CONFIG.SAM.POSITION_RANDOMIZATION.ENABLED then
            local maxOffset = CONFIG.SAM.POSITION_RANDOMIZATION.MAX_OFFSET
            local randomX = (math.random() - 0.5) * 2 * maxOffset
            local randomZ = (math.random() - 0.5) * 2 * maxOffset
            
            unitX = unitX + randomX
            unitZ = unitZ + randomZ
            
            Utils.showDebugMessage("Applied randomization: +" .. randomX .. ", +" .. randomZ, 5, 3)
        end
        
        local unitData = {
            ["type"] = samUnit.type,
            ["unitId"] = math.random(10000, 99999),
            ["skill"] = samUnit.skill or "High",
            ["y"] = unitZ,
            ["x"] = unitX,
            ["name"] = (samUnit.name or ("Unit_" .. i)) .. "_" .. missionType .. "_" .. math.random(100, 999),
            ["heading"] = samUnit.originalHeading or 0,
            ["playerCanDrive"] = false,
        }
        table.insert(spawnData.units, unitData)
    end
    
    -- Spawn the group
    local success = Utils.safeExecute(function()
        coalition.addGroup(country.id.RUSSIA, Group.Category.GROUND, spawnData)
    end, "Failed to spawn SAM site")
    
    if success then
        -- Update zone-specific state
        if zoneName and MissionState.missions.zoneStates[zoneName] then
            MissionState.missions.zoneStates[zoneName].samDeployed = true
            if isHeloMission then
                MissionState.missions.zoneStates[zoneName].heloActive = false
            else
                MissionState.missions.zoneStates[zoneName].truckActive = false
            end
        end
        
        -- Update global mission state (for backward compatibility)
        if isHeloMission then
            MissionState.missions.helo.samDeployed = true
        else
            MissionState.missions.truck.samDeployed = true
        end
        
        -- Ensure zone monitoring continues for this zone
        if not MissionState.monitoring.monitoringActive then
            ZoneMonitoring.startMultiZoneMonitoring()
        end
        
        -- Schedule vehicle cleanup
        SAMDeployment.scheduleVehicleCleanup(missionType, zoneName)
        
        return true
    end
    
    return false
end

-- =====================================================================================
-- VEHICLE SPAWNING SYSTEM
-- =====================================================================================

-- Function to determine optimal vehicle type based on distance to closest supply zones
function VehicleSpawning.determineOptimalVehicleType(targetZone)
    if not targetZone or not targetZone.point then
        Utils.showDebugMessage("Invalid target zone for vehicle selection", 5)
        return "truck" -- Default to truck
    end
    
    -- Find closest supply zones for both vehicle types
    local closestTruckZone, truckDistance = Utils.getClosestSupplyZone(targetZone, "truck")
    local closestHeloZone, heloDistance = Utils.getClosestSupplyZone(targetZone, "helo")
    
    -- If no supply zones are available, fall back to legacy zones
    if not closestTruckZone and not closestHeloZone then
        Utils.showDebugMessage("No multi-zone supply zones found, using legacy method", 5, 2)
        return VehicleSpawning.determineLegacyOptimalVehicleType(targetZone)
    end
    
    local preferHelo = false
    local reason = ""
    
    -- Determine optimal vehicle based on available zones and distances
    if closestTruckZone and closestHeloZone then
        -- Both types available - choose based on distance and max range
        if truckDistance > CONFIG.ZONES.MAX_DISTANCE_FROM_DEPLOY then
            if heloDistance <= CONFIG.ZONES.MAX_DISTANCE_FROM_DEPLOY * 2 then -- Allow helicopters longer range
                preferHelo = true
                reason = "truck exceeds max range (" .. math.floor(truckDistance) .. "m > " .. CONFIG.ZONES.MAX_DISTANCE_FROM_DEPLOY .. "m), helicopter within extended range"
            else
                -- Both exceed reasonable range, choose closer one
                preferHelo = (heloDistance < truckDistance)
                reason = "both exceed optimal range, choosing closer option (" .. (preferHelo and "helo: " .. math.floor(heloDistance) or "truck: " .. math.floor(truckDistance)) .. "m)"
            end
        else
            -- Truck is within range, choose based on efficiency (trucks for short range, helos for long range)
            if truckDistance <= heloDistance * 0.8 then -- Prefer trucks if significantly closer
                preferHelo = false
                reason = "truck significantly closer (" .. math.floor(truckDistance) .. "m vs " .. math.floor(heloDistance) .. "m)"
            else
                preferHelo = (heloDistance < truckDistance)
                reason = "choosing closer option (" .. (preferHelo and "helo: " .. math.floor(heloDistance) or "truck: " .. math.floor(truckDistance)) .. "m)"
            end
        end
    elseif closestTruckZone then
        -- Only truck zones available
        preferHelo = false
        reason = "only truck supply zones available (distance: " .. math.floor(truckDistance) .. "m)"
    elseif closestHeloZone then
        -- Only helo zones available  
        preferHelo = true
        reason = "only helicopter supply zones available (distance: " .. math.floor(heloDistance) .. "m)"
    end
    
    local vehicleType = preferHelo and "helo" or "truck"
    Utils.showDebugMessage("Vehicle selection: " .. vehicleType .. " - " .. reason, 5, 2)
    
    return vehicleType
end

-- Legacy function for backward compatibility when no multi-zone support is available
function VehicleSpawning.determineLegacyOptimalVehicleType(targetZone)
    -- Get the truck and helo deploy zones
    local truckDeployZone = trigger.misc.getZone(CONFIG.ZONES.SUPPORT_TRUCK_DEPLOY)
    local heloDeployZone = trigger.misc.getZone(CONFIG.ZONES.SUPPORT_HELO_DEPLOY)
    
    if not targetZone or not targetZone.point then
        Utils.showDebugMessage("Invalid target zone for legacy vehicle selection", 5)
        return "truck" -- Default to truck
    end
    
    local targetPoint = {x = targetZone.point.x, z = targetZone.point.z}
    local preferHelo = false
    local distanceToTarget = 0
    
    -- Check distance from truck deploy zone if it exists
    if truckDeployZone and truckDeployZone.point then
        local truckDeployPoint = {x = truckDeployZone.point.x, z = truckDeployZone.point.z}
        distanceToTarget = Utils.getDistance(targetPoint, truckDeployPoint)
        
        Utils.showDebugMessage("Distance from legacy truck deploy to target: " .. math.floor(distanceToTarget) .. "m (max: " .. CONFIG.ZONES.MAX_DISTANCE_FROM_DEPLOY .. "m)", 5)
        
        if distanceToTarget > CONFIG.ZONES.MAX_DISTANCE_FROM_DEPLOY then
            preferHelo = true
            Utils.showDebugMessage("Target zone exceeds legacy truck range, preferring helicopter deployment", 5)
        else
            Utils.showDebugMessage("Target zone within legacy truck range, truck deployment preferred", 5)
        end
    else
        Utils.showDebugMessage("Legacy truck deploy zone not found, defaulting to helicopter", 5)
        preferHelo = true
    end
    
    -- Return the preferred vehicle type
    if preferHelo then
        return "helo"
    else
        return "truck"
    end
end

-- New zone-specific spawning functions that create unique groups
function VehicleSpawning.spawnNewTruckForZone(zoneName, uniqueGroupName, targetZone)
    Utils.showDebugMessage("Creating new supply truck group for zone " .. zoneName .. "...", 5,2)
    
    -- Find the closest truck supply zone to the target
    local closestSupplyZone, distance = Utils.getClosestSupplyZone(targetZone, "truck")
    local spawnPoint
    
    if closestSupplyZone and closestSupplyZone.zone then
        -- Spawn at the closest truck supply zone
        spawnPoint = {
            x = closestSupplyZone.zone.point.x,
            z = closestSupplyZone.zone.point.z
        }
        Utils.showDebugMessage("Using closest truck spawn zone: " .. closestSupplyZone.name .. " at (" .. spawnPoint.x .. ", " .. spawnPoint.z .. ") - " .. math.floor(distance) .. "m away", 5, 2)
    elseif MissionState.zones.truckSpawn then
        -- Fallback to legacy truck spawn zone
        spawnPoint = {
            x = MissionState.zones.truckSpawn.point.x,
            z = MissionState.zones.truckSpawn.point.z
        }
        Utils.showDebugMessage("Using legacy truck spawn zone at (" .. spawnPoint.x .. ", " .. spawnPoint.z .. ")", 5)
    else
        -- Final fallback spawn point
        spawnPoint = {x = 0, z = 0}
        Utils.showDebugMessage("Using emergency fallback spawn point", 5)
    end
    
    -- Create truck group data with unique name
    local truckGroupData = {
        ["visible"] = false,
        ["tasks"] = {},
        ["uncontrollable"] = false,
        ["task"] = "Ground Nothing",
        ["taskSelected"] = true,
        ["route"] = {
            ["spans"] = {},
            ["points"] = {
                [1] = {
                    ["alt"] = 0,
                    ["type"] = "Turning Point",
                    ["ETA"] = 0,
                    ["alt_type"] = "BARO",
                    ["formation_template"] = "",
                    ["y"] = spawnPoint.z,
                    ["x"] = spawnPoint.x,
                    ["ETA_locked"] = false,
                    ["speed"] = CONFIG.VEHICLE.TRUCK_SPEED,
                    ["action"] = "Off Road",
                    ["task"] = {
                        ["id"] = "ComboTask",
                        ["params"] = { ["tasks"] = {} }
                    },
                    ["speed_locked"] = true,
                }
            }
        },
        ["groupId"] = math.random(1000, 9999),
        ["hidden"] = false,
        ["units"] = {},
        ["y"] = spawnPoint.z,
        ["x"] = spawnPoint.x,
        ["name"] = uniqueGroupName,
        ["start_time"] = 0,
    }
    
    -- Get supply truck units from configuration and populate them
    local truckUnits = Utils.getSupplyTruckUnits(country.id.CJTF_RED)
    for i, truckUnit in ipairs(truckUnits) do
        local unitData = {
            ["type"] = truckUnit.type,
            ["unitId"] = math.random(10000, 99999),
            ["skill"] = truckUnit.skill or "High",
            ["y"] = spawnPoint.z + (i * 10), -- Space units 10m apart
            ["x"] = spawnPoint.x + (i * 10),
            ["name"] = uniqueGroupName .. "_Unit_" .. i,
            ["heading"] = 0,
            ["playerCanDrive"] = false,
        }
        table.insert(truckGroupData.units, unitData)
    end
    
    -- Spawn the new truck group
    local success = Utils.safeExecute(function()
        coalition.addGroup(country.id.RUSSIA, Group.Category.GROUND, truckGroupData)
    end, "Failed to spawn new truck group for zone " .. zoneName)
    
    if success then
        timer.scheduleFunction(function()
            local newGroup = Group.getByName(uniqueGroupName)
            if newGroup and newGroup:isExist() then
                local units = newGroup:getUnits()
                if units and #units > 0 then
                    Utils.showDebugMessage("Supply truck spawned successfully for zone " .. zoneName .. " with " .. #units .. " units!", 8,3)
                    -- Store the group reference for this zone
                    MissionState.vehicles.supplyGroups[zoneName] = newGroup
                    -- Update legacy reference for compatibility
                    MissionState.vehicles.truck = newGroup
                    -- Decrement spawn count
                    MissionState.missions.truck.spawnCount = MissionState.missions.truck.spawnCount - 1
                    MissionState.missions.truck.active = true
                    return true
                end
            end
            Utils.showMessage("Failed to verify truck spawn for zone " .. zoneName, 5)
            return false
        end, nil, timer.getTime() + 3)
        
        return true
    end
    
    return false
end

function VehicleSpawning.spawnNewHeloForZone(zoneName, uniqueGroupName, targetZone)
    -- Safety check: don't spawn helicopters if disabled
    if not CONFIG.VEHICLE.ENABLE_HELICOPTER_SPAWNING then
        Utils.showDebugMessage("Helicopter spawning disabled in CONFIG.VEHICLE.ENABLE_HELICOPTER_SPAWNING", 5)
        return false
    end
    
    Utils.showDebugMessage("Creating crash-safe helicopter group for zone " .. zoneName .. "...", 5,2)
    
    -- Find the closest helicopter supply zone to the target
    local closestSupplyZone, distance = Utils.getClosestSupplyZone(targetZone, "helo")
    local spawnPoint
    
    if closestSupplyZone and closestSupplyZone.zone then
        -- Spawn at the closest helicopter supply zone
        spawnPoint = {
            x = closestSupplyZone.zone.point.x,
            z = closestSupplyZone.zone.point.z
        }
        Utils.showDebugMessage("Using closest helo spawn zone: " .. closestSupplyZone.name .. " at (" .. spawnPoint.x .. ", " .. spawnPoint.z .. ") - " .. math.floor(distance) .. "m away", 5)
    elseif MissionState.zones.heloSpawn then
        -- Fallback to legacy helo spawn zone
        spawnPoint = {
            x = MissionState.zones.heloSpawn.point.x,
            z = MissionState.zones.heloSpawn.point.z
        }
        Utils.showDebugMessage("Using legacy helo spawn zone at (" .. spawnPoint.x .. ", " .. spawnPoint.z .. ")", 5)
    else
        -- Final fallback spawn point (elevated for helicopters)
        spawnPoint = {x = 0, z = 0}
        Utils.showDebugMessage("Using emergency fallback spawn point", 5)
    end
    
    -- Get ground height for spawn and target zones
    local spawnGroundHeight = land.getHeight({x = spawnPoint.x, y = spawnPoint.z})
    local targetGroundHeight = land.getHeight({x = targetZone.point.x, y = targetZone.point.z})
    local spawnAlt = spawnGroundHeight + CONFIG.VEHICLE.HELO_ALTITUDE
    local targetAlt = targetGroundHeight + 100  -- Safe approach altitude
    local lowAlt = targetGroundHeight + 20      -- Final approach altitude
    
    -- Add altitude to spawn point
    spawnPoint.alt = spawnAlt
    
    -- Get supply helicopter units from configuration
    local heloUnits = Utils.getSupplyHeloUnits(country.id.CJTF_RED)
    if not heloUnits or #heloUnits == 0 then
        Utils.showMessage("No helicopter units configured for spawning!", 5)
        return false
    end
    
    -- Use the first (safest) helicopter type
    local heloType = heloUnits[1].type
    
    -- Create simplified route structure with spawn and target waypoints (minimum for DCS)
    local safeRoute = {
        ["points"] = {
            [1] = {
                ["alt"] = spawnAlt,
                ["type"] = "Turning Point",
                ["y"] = spawnPoint.z,
                ["x"] = spawnPoint.x,
                ["speed"] = CONFIG.VEHICLE.HELO_SPEED,
                ["ETA"] = 0,
                ["ETA_locked"] = false,
                ["speed_locked"] = true,
                ["action"] = "Turning Point",
                ["task"] = {
                    ["id"] = "ComboTask",
                    ["params"] = { ["tasks"] = {} }
                }
            },
            [2] = {
                ["alt"] = targetAlt,
                ["type"] = "Turning Point",
                ["alt_type"] = "BARO",
                ["y"] = targetZone.point.z,
                ["x"] = targetZone.point.x,
                ["speed"] = CONFIG.VEHICLE.HELO_SPEED * 0.6, -- Slower approach speed
                ["ETA"] = 0,
                ["ETA_locked"] = false,
                ["speed_locked"] = true,
                ["action"] = "Turning Point",
                ["task"] = {
                    ["id"] = "ComboTask",
                    ["params"] = { 
                        ["tasks"] = {
                            -- Add immediate HOLD task when reaching waypoint
                            {
                                ["enabled"] = true,
                                ["auto"] = true,
                                ["id"] = "Hold",
                                ["number"] = 1,
                                ["params"] = {}
                            }
                        }
                    }
                }
            }
        }
    }
    
    -- Create crash-safe helicopter group data
    local heloGroupData = Utils.createSafeHeloGroupData(uniqueGroupName, spawnPoint, safeRoute, heloType)
    
    -- Validate group data before spawning
    local isValid, errorMsg = Utils.validateHeloGroupData(heloGroupData)
    if not isValid then
        Utils.showMessage("Invalid helicopter group data: " .. errorMsg, 8)
        Utils.showDebugMessage("Helicopter validation failed: " .. errorMsg, 5)
        return false
    end
    
    -- Use safest spawning method with extensive error handling
    local success = false
    
    Utils.showDebugMessage("Attempting to spawn validated helicopter group...", 5, 3)
    
    -- Try spawning with multiple safety checks
    success = Utils.safeExecute(function()
        -- Additional safety: Check if group name already exists
        local existingGroup = Group.getByName(uniqueGroupName)
        if existingGroup and existingGroup:isExist() then
            Utils.showDebugMessage("Group name already exists, destroying old group first", 5)
            existingGroup:destroy()
            -- Wait a moment before spawning new group
            timer.scheduleFunction(function()
                coalition.addGroup(country.id.RUSSIA, Group.Category.HELICOPTER, heloGroupData)
            end, nil, timer.getTime() + 1)
            return true
        else
            coalition.addGroup(country.id.RUSSIA, Group.Category.HELICOPTER, heloGroupData)
            return true
        end
    end, "Failed to spawn helicopter group for zone " .. zoneName)
    
    if not success then
        Utils.showDebugMessage("Failed to spawn helicopter for zone " .. zoneName, 5)
        return false
    end
    
    Utils.showDebugMessage("Helicopter spawn command executed, verifying...", 5)
    
    -- Verify spawn after a delay with retries
    local verifyAttempts = 0
    local function verifySpawn()
        verifyAttempts = verifyAttempts + 1
        local newGroup = Group.getByName(uniqueGroupName)
        
        if newGroup and newGroup:isExist() then
            local units = newGroup:getUnits()
            if units and #units > 0 then
                Utils.showMessage("Supply helicopter spawned successfully for zone " .. zoneName .. " and is flying to target!", 8)
                -- Store the group reference for this zone
                MissionState.vehicles.supplyGroups[zoneName] = newGroup
                -- Update legacy reference for compatibility
                MissionState.vehicles.helo = newGroup
                -- Decrement spawn count
                MissionState.missions.helo.spawnCount = MissionState.missions.helo.spawnCount - 1
                MissionState.missions.helo.active = true
                return true
            end
        end
        
        -- Retry verification up to 3 times
        if verifyAttempts < 3 then
            Utils.showDebugMessage("Helicopter verification attempt " .. verifyAttempts .. " failed, retrying...", 5)
            timer.scheduleFunction(verifySpawn, nil, timer.getTime() + 2)
            return false
        else
            Utils.showMessage("Failed to verify helicopter spawn for zone " .. zoneName .. " after 3 attempts", 5)
            Utils.showDebugMessage("Helicopter verification completely failed for " .. uniqueGroupName, 5)
            return false
        end
    end
    
    timer.scheduleFunction(verifySpawn, nil, timer.getTime() + 2)
    
    return true
end

-- Zone-specific vehicle spawning functions
function VehicleSpawning.spawnTruckForZone(zoneInfo)
    if MissionState.missions.truck.spawnCount <= 0 then
        Utils.showMessage("No more truck spawns available for zone " .. zoneInfo.name .. "!", 5)
        return false
    end
    
    local zoneName = zoneInfo.name
    local targetZone = zoneInfo.zone
    
    Utils.showDebugMessage("Attempting to spawn supply truck for zone " .. zoneName .. "...", 5, 3)
    
    -- Mark zone as having truck mission active
    if MissionState.missions.zoneStates[zoneName] then
        MissionState.missions.zoneStates[zoneName].truckActive = true
    end
    
    -- Create unique group name for this zone
    local uniqueGroupName = "SupplyTruck_" .. zoneName .. "_" .. timer.getTime()
    
    -- Try to spawn unique truck for this zone
    local success = VehicleSpawning.spawnNewTruckForZone(zoneName, uniqueGroupName, targetZone)
    if success then
        -- Set up route to the specific zone
        timer.scheduleFunction(function()
            local supplyGroup = MissionState.vehicles.supplyGroups[zoneName]
            if supplyGroup and supplyGroup ~= "DEPLOYMENT_PENDING" and supplyGroup:isExist() then
                VehicleSpawning.setupTruckRouteToZone(targetZone, supplyGroup)
                VehicleSpawning.startTruckPositionMonitoringForZone(zoneInfo, supplyGroup)
            else
                Utils.showDebugMessage("Failed to setup truck route for zone " .. zoneName .. " - group not found", 5)
                -- Release the deployment slot if spawn ultimately failed
                if MissionState.vehicles.supplyGroups[zoneName] == "DEPLOYMENT_PENDING" then
                    MissionState.vehicles.supplyGroups[zoneName] = nil
                    Utils.showDebugMessage("Released deployment slot for failed truck spawn in zone " .. zoneName, 5, 3)
                end
            end
            return nil
        end, nil, timer.getTime() + 3)
    else
        -- Release the deployment slot if spawn failed immediately
        if MissionState.vehicles.supplyGroups[zoneName] == "DEPLOYMENT_PENDING" then
            MissionState.vehicles.supplyGroups[zoneName] = nil
            Utils.showDebugMessage("Released deployment slot for failed truck spawn in zone " .. zoneName, 5,3)
        end
    end
    
    return success
end

function VehicleSpawning.spawnHeloForZone(zoneInfo)
    -- Safety check: don't spawn helicopters if disabled
    if not CONFIG.VEHICLE.ENABLE_HELICOPTER_SPAWNING then
        return VehicleSpawning.spawnTruckForZone(zoneInfo)
    end
    
    if MissionState.missions.helo.spawnCount <= 0 then
        Utils.showMessage("No more helicopter spawns available for zone " .. zoneInfo.name .. "!", 5)
        return false
    end
    
    local zoneName = zoneInfo.name
    local targetZone = zoneInfo.zone

    Utils.showDebugMessage("Attempting to spawn supply helicopter for zone " .. zoneName .. "...", 5,2)
    
    -- Mark zone as having helo mission active
    if MissionState.missions.zoneStates[zoneName] then
        MissionState.missions.zoneStates[zoneName].heloActive = true
    end
    
    -- Create unique group name for this zone
    local uniqueGroupName = "SupplyHelo_" .. zoneName .. "_" .. timer.getTime()
    
    -- Try to spawn unique helicopter for this zone
    local success = VehicleSpawning.spawnNewHeloForZone(zoneName, uniqueGroupName, targetZone)
    if success then
        -- Start monitoring helicopter position (no separate route setup needed)
        timer.scheduleFunction(function()
            local supplyGroup = MissionState.vehicles.supplyGroups[zoneName]
            if supplyGroup and supplyGroup ~= "DEPLOYMENT_PENDING" and supplyGroup:isExist() then
                VehicleSpawning.startHeloPositionMonitoringForZone(zoneInfo, supplyGroup)
            else
                -- Release the deployment slot if spawn ultimately failed
                if MissionState.vehicles.supplyGroups[zoneName] == "DEPLOYMENT_PENDING" then
                    MissionState.vehicles.supplyGroups[zoneName] = nil
                end
            end
            return nil
        end, nil, timer.getTime() + 2)
    else
        Utils.showDebugMessage("Helicopter spawn failed for zone " .. zoneName, 8,1)
        -- Release the deployment slot if spawn failed immediately
        if MissionState.vehicles.supplyGroups[zoneName] == "DEPLOYMENT_PENDING" then
            MissionState.vehicles.supplyGroups[zoneName] = nil
            Utils.showDebugMessage("Released deployment slot for failed helicopter spawn in zone " .. zoneName, 5, 1)
        end
    end
    
    return success
end

function VehicleSpawning.setupTruckRouteToZone(targetZone, supplyGroup)
    -- Use provided group or fall back to legacy reference
    local truckGroup = supplyGroup or MissionState.vehicles.truck
    
    if not truckGroup or not truckGroup:isExist() then
        Utils.showDebugMessage("ERROR: Cannot setup truck route - truck group not found!", 10,1)
        return false
    end
    
    local truckUnits = truckGroup:getUnits()
    if not truckUnits or #truckUnits == 0 then
        Utils.showDebugMessage("ERROR: No truck units found!", 10,1)
        return false
    end
    
    local leadUnit = truckUnits[1]
    if not leadUnit or not leadUnit:isExist() then
        Utils.showDebugMessage("ERROR: Lead truck unit not found!", 10,1)
        return false
    end
    
    local currentPos = leadUnit:getPosition().p
    if not currentPos then
        Utils.showDebugMessage("ERROR: Could not get truck position!", 10,1)
        return false
    end
    
    -- Create route to destination
    local routePoints = {
        -- Starting position
        {
            x = currentPos.x,
            y = currentPos.z,
            alt = 0,
            type = "Turning Point",
            ETA = 0,
            ETA_locked = false,
            speed = CONFIG.VEHICLE.TRUCK_SPEED,
            speed_locked = true,
            formation_template = "",
            task = {
                id = "ComboTask",
                params = { tasks = {} }
            }
        },
        -- Destination
        {
            x = targetZone.point.x,
            y = targetZone.point.z,
            alt = 0,
            type = "Turning Point",
            ETA = 0,
            ETA_locked = false,
            speed = CONFIG.VEHICLE.TRUCK_SPEED,
            speed_locked = true,
            formation_template = "",
            task = {
                id = "ComboTask",
                params = { tasks = {} }
            }
        }
    }
    
    local mission = {
        id = "Mission",
        params = {
            route = { points = routePoints }
        }
    }
    
    local controller = truckGroup:getController()
    if controller then
        controller:setTask(mission)
        Utils.showDebugMessage("Supply truck is en route to deployment zone!", 10,2)
        return true
    end
    
    return false
end

function VehicleSpawning.startTruckPositionMonitoringForZone(zoneInfo, supplyGroup)
    local zoneName = zoneInfo.name
    local targetZone = zoneInfo.zone
    -- Use provided group or fall back to legacy reference
    local truckGroup = supplyGroup or MissionState.vehicles.truck
    
    local function checkTruckPosition()
        local zoneState = MissionState.missions.zoneStates[zoneName]
        if not zoneState or not zoneState.truckActive or zoneState.samDeployed then
            return nil -- Stop checking
        end
        
        if not truckGroup or not truckGroup:isExist() then
            Utils.showMessage("Supply truck has been destroyed! Mission failed for zone " .. zoneName .. ".", 10)
            if zoneState then
                zoneState.truckActive = false
            end
            -- Clean up the supply group reference
            if MissionState.vehicles.supplyGroups[zoneName] == truckGroup then
                MissionState.vehicles.supplyGroups[zoneName] = nil
            end
            return nil
        end
        
        local truckUnits = truckGroup:getUnits()
        if not truckUnits or #truckUnits == 0 then
            Utils.showMessage("No truck units remaining! Mission failed for zone " .. zoneName .. ".", 10)
            if zoneState then
                zoneState.truckActive = false
            end
            -- Clean up the supply group reference
            if MissionState.vehicles.supplyGroups[zoneName] == truckGroup then
                MissionState.vehicles.supplyGroups[zoneName] = nil
            end
            return nil
        end
        
        local leadUnit = truckUnits[1]
        if leadUnit and leadUnit:isExist() then
            local truckPos = leadUnit:getPosition().p
            if truckPos and Utils.isPointInZone(truckPos, targetZone) then
                SAMDeployment.spawnManually(nil, targetZone, "truck", zoneName)
                return nil -- Stop checking
            end
        end
        
        return timer.getTime() + CONFIG.CHECK_INTERVAL
    end
    
    timer.scheduleFunction(checkTruckPosition, nil, timer.getTime() + CONFIG.CHECK_INTERVAL)
end

function VehicleSpawning.startHeloPositionMonitoringForZone(zoneInfo, supplyGroup)
    local zoneName = zoneInfo.name
    local targetZone = zoneInfo.zone
    -- Use provided group or fall back to legacy reference
    local heloGroup = supplyGroup or MissionState.vehicles.helo
    
    Utils.showMessage("Starting helicopter position monitoring for zone " .. zoneName, 8)
    Utils.showMessage("DEBUG: Helicopter group: " .. (heloGroup and heloGroup:getName() or "nil"), 8)
    Utils.showMessage("DEBUG: Target zone: " .. zoneName .. " at (" .. targetZone.point.x .. ", " .. targetZone.point.z .. ") radius: " .. targetZone.radius, 8)
    Utils.showDebugMessage("Helicopter group: " .. (heloGroup and heloGroup:getName() or "nil"), 5)
    
    local timeInZone = 0 -- Track how long helicopter has been in zone
    local lastInZone = false
    local monitoringCount = 0 -- Track how many monitoring cycles we've done
    local lastPosition = nil -- Track previous position for velocity calculation
    local stopCommandSent = false -- Track if we already sent stop commands
    local approachingZone = false -- Track if helicopter is approaching the zone
    
    local function checkHeloPosition()
        monitoringCount = monitoringCount + 1
        local zoneState = MissionState.missions.zoneStates[zoneName]
        if not zoneState or not zoneState.heloActive or zoneState.samDeployed then
            Utils.showMessage("DEBUG: Stopping helicopter monitoring for zone " .. zoneName .. " (mission complete or inactive)", 8)
            return nil -- Stop checking
        end
        
        if not heloGroup or not heloGroup:isExist() then
            Utils.showMessage("Supply helicopter has been destroyed! Mission failed for zone " .. zoneName .. ".", 10)
            if zoneState then
                zoneState.heloActive = false
            end
            -- Clean up the supply group reference
            if MissionState.vehicles.supplyGroups[zoneName] == heloGroup then
                MissionState.vehicles.supplyGroups[zoneName] = nil
            end
            return nil
        end
        
        local heloUnits = heloGroup:getUnits()
        if not heloUnits or #heloUnits == 0 then
            Utils.showMessage("No helicopter units remaining! Mission failed for zone " .. zoneName .. ".", 10)
            if zoneState then
                zoneState.heloActive = false
            end
            -- Clean up the supply group reference
            if MissionState.vehicles.supplyGroups[zoneName] == heloGroup then
                MissionState.vehicles.supplyGroups[zoneName] = nil
            end
            return nil
        end
        
        local leadUnit = heloUnits[1]
        if leadUnit and leadUnit:isExist() then
            local heloPos = leadUnit:getPosition().p
            if heloPos then
                local distance = Utils.getDistance(heloPos, {x = targetZone.point.x, z = targetZone.point.z})
                local altitude = heloPos.y
                local groundHeight = land.getHeight({x = heloPos.x, y = heloPos.z})
                local heightAboveGround = altitude - groundHeight
                local currentlyInZone = Utils.isPointInZone(heloPos, targetZone)
                
                -- Calculate velocity if we have a previous position
                local velocity = nil
                local eta = nil
                if lastPosition then
                    local deltaTime = CONFIG.HELICOPTER_CHECK_INTERVAL
                    local deltaX = heloPos.x - lastPosition.x
                    local deltaZ = heloPos.z - lastPosition.z
                    local speed = math.sqrt(deltaX^2 + deltaZ^2) / deltaTime
                    velocity = {x = deltaX / deltaTime, z = deltaZ / deltaTime, speed = speed}
                    
                    -- Calculate estimated time to reach zone if moving toward it
                    if velocity.speed > 2 and distance > targetZone.radius then
                        -- Vector from helicopter to zone center
                        local toZoneX = targetZone.point.x - heloPos.x
                        local toZoneZ = targetZone.point.z - heloPos.z
                        local toZoneLength = math.sqrt(toZoneX^2 + toZoneZ^2)
                        
                        -- Dot product to see if helicopter is moving toward zone
                        local dotProduct = (velocity.x * toZoneX + velocity.z * toZoneZ) / toZoneLength
                        if dotProduct > 0 then -- Moving toward zone
                            eta = (distance - targetZone.radius) / velocity.speed
                        end
                    end
                end
                lastPosition = {x = heloPos.x, z = heloPos.z}
            

                -- PREDICTIVE APPROACH DETECTION - Stop helicopter before it enters small zones
                local approachDistance = math.max(targetZone.radius * 2, 200) -- Detection radius (at least 200m or 2x zone radius)
                local nowApproaching = distance <= approachDistance and not currentlyInZone
                
                if nowApproaching and not approachingZone and not stopCommandSent then
                    approachingZone = true
                    -- Send direct route command to zone center instead of orbit command
                    local controller = heloGroup:getController()
                    if controller then
                        -- Create a direct route to the zone center with slower speed
                        local directRouteTask = {
                            id = "Mission",
                            params = {
                                route = {
                                    points = {
                                        [1] = {
                                            x = targetZone.point.x,
                                            y = targetZone.point.z,
                                            alt = math.max(groundHeight + 30, 100),
                                            type = "Turning Point",
                                            ETA = 0,
                                            ETA_locked = false,
                                            speed = 10, -- Slower approach speed (reduced from 15)
                                            speed_locked = true,
                                            formation_template = "",
                                            task = {
                                                id = "ComboTask",
                                                params = {
                                                    tasks = {
                                                        [1] = {
                                                            id = "Hold",
                                                            params = {}
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        controller:setTask(directRouteTask)
                        Utils.showDebugMessage("Set DIRECT APPROACH route to zone center " .. zoneName .. " (distance: " .. math.floor(distance) .. "m)", 5,3)
                    end
                end
                
                -- Enhanced debug logging every 3 monitoring cycles (roughly every 9 seconds)
                if monitoringCount % 3 == 0 then
                    Utils.showDebugMessage("Helicopter " .. heloGroup:getName() .. " monitoring cycle " .. monitoringCount, 8, 3)
                    Utils.showDebugMessage("Position (" .. math.floor(heloPos.x) .. ", " .. math.floor(heloPos.z) .. "), Distance: " .. math.floor(distance) .. "m", 8,3)
                    Utils.showDebugMessage("Currently in zone: " .. tostring(currentlyInZone) .. ", Time in zone: " .. math.floor(timeInZone) .. "s", 8,3)
                    if velocity then
                        Utils.showDebugMessage("Speed: " .. math.floor(velocity.speed) .. " m/s" .. (eta and (", ETA: " .. math.floor(eta) .. "s") or ""), 8,3)
                    end
                end
                
                -- Track time in zone (fixed logic)
                if currentlyInZone then
                    -- Helicopter is in zone - accumulate time
                    timeInZone = timeInZone + CONFIG.HELICOPTER_CHECK_INTERVAL
                    
                    -- If this is the first time entering the zone, IMMEDIATELY stop the helicopter
                    if not lastInZone then
                        stopCommandSent = true
                        
                        -- Force helicopter to STOP immediately in the zone (multiple methods for reliability)
                        local controller = heloGroup:getController()
                        if controller then
                            -- Method 1: Immediate HOLD command (replaces all tasks)
                            local holdTask = {
                                id = "Hold",
                                params = {}
                            }
                            controller:setTask(holdTask)
                            Utils.showDebugMessage("Set HOLD task - helicopter should stop immediately in zone " .. zoneName, 5,3)
                            
                            -- Method 2: Follow up with Land task to force full stop
                            timer.scheduleFunction(function()
                                if heloGroup and heloGroup:isExist() then
                                    local controller2 = heloGroup:getController()
                                    if controller2 then
                                        local landTask = {
                                            id = "Land",
                                            params = {
                                                point = {
                                                    x = heloPos.x,
                                                    y = heloPos.z
                                                },
                                                durationFlag = false,
                                                duration = 300  -- Land for 5 minutes (effectively permanent)
                                            }
                                        }
                                        controller2:setTask(landTask)
                                        Utils.showDebugMessage("Set LAND task - helicopter should land and stay in zone " .. zoneName, 5, 3)
                                    end
                                end
                                return nil
                            end, nil, timer.getTime() + 1)
                            
                            -- Method 3: Backup orbit at current position with minimal speed
                            timer.scheduleFunction(function()
                                if heloGroup and heloGroup:isExist() then
                                    local controller3 = heloGroup:getController()
                                    if controller3 then
                                        local hoverTask = {
                                            id = "Orbit",
                                            params = {
                                                pattern = "Circle",
                                                point = {
                                                    x = heloPos.x,
                                                    y = heloPos.z
                                                },
                                                speed = 5, -- Very slow speed for hovering
                                                altitude = math.max(groundHeight + 10, altitude - 10) -- Lower altitude
                                            }
                                        }
                                        controller3:setTask(hoverTask)
                                        Utils.showDebugMessage("Set BACKUP HOVER task with minimal speed", 5,3)
                                    end
                                end
                                return nil
                            end, nil, timer.getTime() + 5)
                        end
                    end
                else
                    -- Helicopter left zone - reset timer and flags
                    if lastInZone then
                        Utils.showMessage("Helicopter left zone " .. zoneName .. " - resetting deployment timer", 8)
                        stopCommandSent = false -- Allow stop commands again if it re-enters
                    end
                    timeInZone = 0
                    approachingZone = false
                end
                lastInZone = currentlyInZone
                
                Utils.showDebugMessage("Helicopter distance to zone " .. zoneName .. ": " .. math.floor(distance) .. "m, AGL: " .. math.floor(heightAboveGround) .. "m, Time in zone: " .. math.floor(timeInZone) .. "s", 3,3)
                
                -- Deploy SAM based on more forgiving conditions (faster deployment)
                if currentlyInZone and (heightAboveGround < 80 or timeInZone >= 10) then
                    local deployReason = ""
                    if heightAboveGround < 80 then
                        deployReason = "reasonable altitude (" .. math.floor(heightAboveGround) .. "m AGL)"
                    else
                        deployReason = "10-second timeout in zone"
                    end
                    
                    Utils.showDebugMessage("Supply helicopter deploying SAM in zone " .. zoneName .. " due to " .. deployReason .. "!", 10, 2)
                    
                    -- Schedule SAM deployment
                    timer.scheduleFunction(function()
                        SAMDeployment.spawnManually(nil, targetZone, "helicopter", zoneName)
                    end, nil, timer.getTime() + 1)
                    
                    return nil -- Stop checking
                elseif currentlyInZone then
                    -- Helicopter is in zone but waiting for deployment conditions
                    Utils.showDebugMessage("Helicopter in zone " .. zoneName .. " - AGL: " .. math.floor(heightAboveGround) .. "m, Time: " .. math.floor(timeInZone) .. "s (deployment pending)", 5, 3)
                    
                    -- Force descent and full stop if helicopter has been in zone for a while
                    if timeInZone > 6 and heightAboveGround > 40 then
                        local controller = heloGroup:getController()
                        if controller then
                            -- Try both Land and low Orbit tasks for maximum effect
                            local landTask = {
                                id = "Land",
                                params = {
                                    point = {
                                        x = targetZone.point.x,
                                        y = targetZone.point.z
                                    },
                                    durationFlag = false,
                                    duration = 300
                                }
                            }
                            controller:setTask(landTask)
                            Utils.showDebugMessage("Forcing helicopter to LAND in zone " .. zoneName .. " after 6 seconds", 5)
                        end
                    end
                end
            end
        end
        
        return timer.getTime() + CONFIG.HELICOPTER_CHECK_INTERVAL
    end
    
    timer.scheduleFunction(checkHeloPosition, nil, timer.getTime() + CONFIG.HELICOPTER_CHECK_INTERVAL)
end

-- =====================================================================================
-- CARGO MANAGEMENT SYSTEM
-- =====================================================================================

-- Initialize the cargo management system and spawn initial supply objects
function CargoManagement.initialize()
    Utils.showDebugMessage("=== INITIALIZING CARGO MANAGEMENT SYSTEM ===", 5, 2)
    
    -- Discover multiple ammo supply zones
    CargoManagement.discoverAmmoSupplyZones()
    
    if not MissionState.zones.ammoSpawnZones or #MissionState.zones.ammoSpawnZones == 0 then
        Utils.showDebugMessage("WARNING: No ammo supply zones found! Cargo spawning disabled.", 10, 1)
        return false
    end
    
    Utils.showDebugMessage("Found " .. #MissionState.zones.ammoSpawnZones .. " ammo supply zones", 8, 1)
    
    -- Spawn initial supply objects
    CargoManagement.spawnInitialSupplyObjects()
    
    return true
end

-- Discover all ammo supply zones (similar to other zone discovery functions)
function CargoManagement.discoverAmmoSupplyZones()
    local ammoZones = {}
    
    Utils.showDebugMessage("Discovering ammo supply zones...", 5, 2)
    
    -- Try to discover zones using mission data first
    local env = _G.env or {}
    if env.mission and env.mission.triggers and env.mission.triggers.zones then
        for _, zone in pairs(env.mission.triggers.zones) do
            if zone.name then
                local zoneName = zone.name
                
                -- Check for ammo supply zones
                if string.find(zoneName, "^" .. CONFIG.ZONES.SUPPORT_AMMO_SUPPLY) then
                    local zoneObj = trigger.misc.getZone(zoneName)
                    if zoneObj then
                        table.insert(ammoZones, {
                            name = zoneName,
                            zone = zoneObj
                        })
                        Utils.showDebugMessage("Found ammo supply zone: " .. zoneName, 5, 2)
                    end
                end
            end
        end
    end
    
    -- Fallback: Try to get zones by name pattern
    if #ammoZones == 0 then
        Utils.showDebugMessage("No ammo zones found via mission data, trying name-based discovery...", 5, 2)
        
        -- Try common naming patterns for ammo zones
        for i = 0, 20 do  -- Check up to 20 numbered zones
            local suffix = (i == 0) and "" or ("-" .. i)
            
            local ammoZoneName = CONFIG.ZONES.SUPPORT_AMMO_SUPPLY .. suffix
            local ammoZone = trigger.misc.getZone(ammoZoneName)
            if ammoZone then
                table.insert(ammoZones, {
                    name = ammoZoneName,
                    zone = ammoZone
                })
                Utils.showDebugMessage("Found ammo supply zone: " .. ammoZoneName, 5, 2)
            end
        end
    end
    
    -- Store discovered zones
    MissionState.zones.ammoSpawnZones = ammoZones
    
    Utils.showMessage("Discovered " .. #ammoZones .. " ammo supply zones", 8)
    
    return #ammoZones > 0
end

-- Spawn the initial supply objects distributed evenly across all ammo supply zones
function CargoManagement.spawnInitialSupplyObjects()
    if not MissionState.zones.ammoSpawnZones or #MissionState.zones.ammoSpawnZones == 0 then
        Utils.showDebugMessage("Cannot spawn initial supply objects - no ammo supply zones available", 5)
        return false
    end
    
    if not CONFIG.AVAILABLE_SUPPLY_OBJECT_TYPES or #CONFIG.AVAILABLE_SUPPLY_OBJECT_TYPES == 0 then
        Utils.showDebugMessage("ERROR: No supply object types configured in AVAILABLE_SUPPLY_OBJECT_TYPES!", 10)
        return false
    end
    
    local objectsToSpawn = CONFIG.STARTING_SUPPLY_OBJECTS or 10
    local numZones = #MissionState.zones.ammoSpawnZones
    local objectsPerZone = math.floor(objectsToSpawn / numZones)
    local remainingObjects = objectsToSpawn % numZones
    
    Utils.showDebugMessage("Distributing " .. objectsToSpawn .. " initial supply objects across " .. numZones .. " ammo supply zones (" .. objectsPerZone .. " per zone + " .. remainingObjects .. " extra)...", 8, 1)
    
    local successCount = 0
    local failureCount = 0
    
    -- Spawn objects in each zone
    for zoneIndex, zoneInfo in ipairs(MissionState.zones.ammoSpawnZones) do
        local objectsForThisZone = objectsPerZone
        
        -- Distribute remaining objects to first zones
        if zoneIndex <= remainingObjects then
            objectsForThisZone = objectsForThisZone + 1
        end
        
        Utils.showDebugMessage("Spawning " .. objectsForThisZone .. " objects in zone: " .. zoneInfo.name, 8, 2)
        
        -- Reset grid for each zone
        MissionState.gridStates = MissionState.gridStates or {}
        MissionState.gridStates[zoneInfo.name] = {
            currentGrid = 1,
            currentRow = 1,
            currentCol = 1
        }
        
        for i = 1, objectsForThisZone do
            local success = CargoManagement.spawnRandomSupplyObject(zoneInfo.zone)
            if success then
                successCount = successCount + 1
            else
                failureCount = failureCount + 1
            end
            
            -- Small delay between spawns to prevent issues
            if i < objectsForThisZone then
                timer.scheduleFunction(function()
                    return nil
                end, nil, timer.getTime() + 0.1)
            end
        end
    end
    
    Utils.showDebugMessage("Initial supply spawn completed: " .. successCount .. " objects spawned successfully, " .. failureCount .. " failed", 10)
    Utils.showDebugMessage("Current cargo count: " .. #MissionState.spawnedCargo, 5, 2)
    
    return successCount > 0
end

-- Spawn a random supply object in a specific zone using 6x6 grid pattern
function CargoManagement.spawnRandomSupplyObject(targetZone)
    -- If no zone specified, use the first available zone (backward compatibility)
    if not targetZone then
        if not MissionState.zones.ammoSpawnZones or #MissionState.zones.ammoSpawnZones == 0 then
            Utils.showDebugMessage("Cannot spawn supply object - no ammo supply zones available", 5, 3)
            return false
        end
        targetZone = MissionState.zones.ammoSpawnZones[1].zone
    end
    
    -- Select random supply object type
    local objectTypes = CONFIG.AVAILABLE_SUPPLY_OBJECT_TYPES
    local randomIndex = math.random(1, #objectTypes)
    local selectedType = objectTypes[randomIndex]
    
    -- Generate position within the specified zone using 6x6 grid
    local spawnPos = CargoManagement.getGridPositionInZone(targetZone)
    if not spawnPos then
        Utils.showDebugMessage("Failed to generate grid position in target zone", 5)
        return false
    end
    
    -- Create unique cargo name
    MissionState.cargoSpawnCount = MissionState.cargoSpawnCount + 1
    local cargoName = "SupplyCargo_" .. selectedType.type .. "_" .. MissionState.cargoSpawnCount
    
    Utils.showDebugMessage("Spawning cargo: " .. cargoName .. " at (" .. spawnPos.x .. ", " .. spawnPos.z .. ")", 5, 2)
    
    -- Create cargo spawn data
    local cargoData = {
        ["visible"] = true,
        ["lateActivation"] = false,
        ["hidden"] = false,
        ["name"] = cargoName,
        ["x"] = spawnPos.x,
        ["y"] = spawnPos.z,
        ["type"] = selectedType.type,
        ["mass"] = 1000, -- Default mass in kg
        ["canCargo"] = true,
        ["shape_name"] = selectedType.type,
        ["heading"] = math.random(0, 359),
    }
    
    -- Spawn the cargo object
    local success = Utils.safeExecute(function()
        coalition.addStaticObject(country.id.CJTF_RED, cargoData)
        return true
    end, "Failed to spawn supply cargo: " .. cargoName)
    
    if success then
        -- Track the spawned cargo
        table.insert(MissionState.spawnedCargo, {
            name = cargoName,
            type = selectedType.type,
            typeName = selectedType.name,
            position = spawnPos,
            spawnTime = timer.getTime()
        })
        
        Utils.showDebugMessage("Successfully spawned cargo: " .. selectedType.name, 5, 2)
        return true
    else
        Utils.showDebugMessage("Failed to spawn cargo: " .. selectedType.name, 5)
        return false
    end
end

-- Generate a position within a zone using 6x6 grid pattern, expanding to new grids as needed
function CargoManagement.getGridPositionInZone(zone)
    if not zone or not zone.point or not zone.radius then
        Utils.showDebugMessage("Invalid zone data for grid position generation", 5, 3)
        return nil
    end
    
    -- Find zone name for grid state tracking
    local zoneName = nil
    for _, zoneInfo in pairs(MissionState.zones.ammoSpawnZones or {}) do
        if zoneInfo.zone == zone then
            zoneName = zoneInfo.name
            break
        end
    end
    
    if not zoneName then
        zoneName = "unknown_zone"
    end
    
    -- Initialize grid state for this zone if not exists
    MissionState.gridStates = MissionState.gridStates or {}
    if not MissionState.gridStates[zoneName] then
        MissionState.gridStates[zoneName] = {
            currentGrid = 1,
            currentRow = 1,
            currentCol = 1
        }
    end
    
    local gridState = MissionState.gridStates[zoneName]
    local gridSize = 6  -- 6x6 grid
    local objectSpacing = 8  -- 8 meters between objects
    local gridSpacing = gridSize * objectSpacing + 20  -- Space between grids (20m buffer)
    
    -- Calculate grid offset (grids expand southward)
    local gridRow = gridState.currentGrid - 1
    local gridOffsetZ = gridRow * gridSpacing
    
    -- Calculate position within current grid
    local row = gridState.currentRow - 1  -- 0-based for calculation
    local col = gridState.currentCol - 1  -- 0-based for calculation
    
    -- Position relative to zone center
    local startX = -(gridSize - 1) * objectSpacing / 2  -- Center the grid on zone
    local startZ = -(gridSize - 1) * objectSpacing / 2 + gridOffsetZ  -- Apply grid offset
    
    local x = zone.point.x + startX + (col * objectSpacing)
    local z = zone.point.z + startZ + (row * objectSpacing)
    
    Utils.showDebugMessage("Grid position for " .. zoneName .. " - Grid:" .. gridState.currentGrid .. " Row:" .. gridState.currentRow .. " Col:" .. gridState.currentCol .. " at (" .. x .. ", " .. z .. ")", 5, 3)
    
    -- Advance to next position
    gridState.currentCol = gridState.currentCol + 1
    if gridState.currentCol > gridSize then
        gridState.currentCol = 1
        gridState.currentRow = gridState.currentRow + 1
        if gridState.currentRow > gridSize then
            gridState.currentRow = 1
            gridState.currentGrid = gridState.currentGrid + 1
            Utils.showDebugMessage("Starting new grid " .. gridState.currentGrid .. " for zone " .. zoneName, 5, 2)
        end
    end
    
    return {x = x, z = z}
end

-- Helper function to get a specific ammo supply zone (for backward compatibility and specific zone access)
function CargoManagement.getAmmoSupplyZone(zoneIndex)
    if not MissionState.zones.ammoSpawnZones or #MissionState.zones.ammoSpawnZones == 0 then
        return nil
    end
    
    zoneIndex = zoneIndex or 1  -- Default to first zone
    if zoneIndex <= #MissionState.zones.ammoSpawnZones then
        return MissionState.zones.ammoSpawnZones[zoneIndex].zone
    end
    
    return nil
end

-- Get all ammo supply zones
function CargoManagement.getAllAmmoSupplyZones()
    return MissionState.zones.ammoSpawnZones or {}
end

-- =====================================================================================
-- RADIO MENU SYSTEM
-- =====================================================================================

function RadioMenu.checkTruckStatus()
    if not MissionState.vehicles.truck or not MissionState.vehicles.truck:isExist() then
        Utils.showMessage("Supply truck is not available.", 5)
        return
    end
    
    local truckUnits = MissionState.vehicles.truck:getUnits()
    if not truckUnits or #truckUnits == 0 then
        Utils.showMessage("No truck units remaining.", 5)
        return
    end
    
    local leadUnit = truckUnits[1]
    if leadUnit and leadUnit:isExist() then
        local truckPos = leadUnit:getPosition().p
        if truckPos and MissionState.zones.truck then
            local distance = Utils.getDistance(truckPos, MissionState.zones.truck.point)
            Utils.showMessage(string.format("Supply truck is %.0f meters from truck deployment zone.", distance), 8)
        else
            Utils.showMessage("Could not get truck position or zone not found.", 5)
        end
    else
        Utils.showMessage("Supply truck status unknown.", 5)
    end
end

function RadioMenu.checkHeloStatus()
    if not MissionState.vehicles.helo or not MissionState.vehicles.helo:isExist() then
        Utils.showMessage("Supply helicopter is not available.", 5)
        return
    end
    
    local heloUnits = MissionState.vehicles.helo:getUnits()
    if not heloUnits or #heloUnits == 0 then
        Utils.showMessage("No helicopter units remaining.", 5)
        return
    end
    
    local leadUnit = heloUnits[1]
    if leadUnit and leadUnit:isExist() then
        local heloPos = leadUnit:getPosition().p
        if heloPos and MissionState.zones.helo then
            local distance = Utils.getDistance(heloPos, MissionState.zones.helo.point)
            Utils.showMessage(string.format("Supply helicopter is %.0f meters from helicopter deployment zone.", distance), 8)
        else
            Utils.showMessage("Could not get helicopter position or zone not found.", 5)
        end
    else
        Utils.showMessage("Supply helicopter status unknown.", 5)
    end
end

-- Obsolete manual start functions removed - system now operates automatically via zone monitoring
-- Use "Start Zone Monitoring" from the radio menu to enable automatic multi-zone resupply

function RadioMenu.getMissionStatus()
    local overview = Utils.getMissionOverview()
    local allZones = ZoneDiscovery.getAllActiveZones()
    
    local message = string.format(
        "MISSION STATUS:\nTruck Spawns: %d | Helo Spawns: %d\n\nDEPLOYMENT ZONES:",
        overview.truck.spawnsRemaining,
        overview.helo.spawnsRemaining
    )
    
    if #allZones > 0 then
        for _, zoneInfo in pairs(allZones) do
            local zoneName = zoneInfo.name
            local zoneType = zoneInfo.type
            local zoneState = MissionState.missions.zoneStates[zoneName]
            
            if zoneState then
                local status = "CLEAR"
                if zoneState.samDeployed then
                    status = "SAM ACTIVE"
                elseif zoneState.unitsCount > 0 then
                   
                    status = "ENEMIES (" .. zoneState.unitsCount .. ")"
                elseif zoneState.truckActive or zoneState.heloActive then
                    status = "RESUPPLY EN ROUTE"
                end
                
                message = message .. string.format("\n%s (%s): %s", zoneName, zoneType, status)
            end
        end
    else
        message = message .. "\nNo deployment zones found!"
    end
    
    Utils.showMessage(message, 15)
end

function RadioMenu.resetSpawnCounts()
    MissionState.missions.truck.spawnCount = CONFIG.SPAWN_LIMITS.TRUCK
    MissionState.missions.helo.spawnCount = CONFIG.SPAWN_LIMITS.HELO
    Utils.showMessage("Spawn counts reset to maximum values.", 8)
end

function RadioMenu.resetMissions()
    -- Reset mission states
    MissionState.missions.truck.spawnCount = CONFIG.SPAWN_LIMITS.TRUCK
    MissionState.missions.helo.spawnCount = CONFIG.SPAWN_LIMITS.HELO
    
    -- Reset all zone states
    for zoneName, zoneState in pairs(MissionState.missions.zoneStates) do
        zoneState.truckActive = false
        zoneState.heloActive = false
        zoneState.samDeployed = false
        zoneState.unitsCount = 0
    end
    
    -- Stop monitoring
    MissionState.monitoring.monitoringActive = false
    
    Utils.showMessage("All missions and spawn counts reset. Ready for fresh start.", 10)
    
    -- Restart monitoring
    timer.scheduleFunction(function()
        ZoneMonitoring.startMultiZoneMonitoring()
        return nil
    end, nil, timer.getTime() + 2)
end

-- Manual cleanup function for testing
function RadioMenu.manualCleanupVehicles()
    Utils.showMessage("=== MANUAL VEHICLE CLEANUP ===", 5)
    
    local cleanedCount = 0
    
    -- Clean up all tracked supply groups
    for zoneName, supplyGroup in pairs(MissionState.vehicles.supplyGroups) do
        if supplyGroup and supplyGroup ~= "DEPLOYMENT_PENDING" then
            if supplyGroup:isExist() then
                local groupName = supplyGroup:getName()
                Utils.showMessage("Manually cleaning up supply group: " .. groupName .. " in zone " .. zoneName, 8)
                
                -- Simple immediate cleanup
                local success = pcall(function()
                    supplyGroup:destroy()
                end)
                
                if success then
                    Utils.showMessage("Successfully destroyed supply group: " .. groupName, 8)
                    cleanedCount = cleanedCount + 1
                else
                    Utils.showMessage("Failed to destroy supply group: " .. groupName, 8)
                end
                
                -- Remove from tracking
                MissionState.vehicles.supplyGroups[zoneName] = nil
            else
                Utils.showMessage("Supply group in zone " .. zoneName .. " no longer exists, removing from tracking", 8)
                MissionState.vehicles.supplyGroups[zoneName] = nil
                cleanedCount = cleanedCount + 1
            end
        end
    end
    
    Utils.showMessage("Manual cleanup complete. Cleaned " .. cleanedCount .. " supply groups.", 10)
end

function RadioMenu.checkZoneStatus()
    local allZones = ZoneDiscovery.getAllActiveZones()
    local message = "DETAILED ZONE STATUS:\n"
    
    if #allZones > 0 then
        for _, zoneInfo in pairs(allZones) do
            local zoneName = zoneInfo.name
            local zoneType = zoneInfo.type
            local zoneState = MissionState.missions.zoneStates[zoneName]
            
            message = message .. string.format("\n=== %s (%s) ===", zoneName, zoneType)
            
            if zoneState then
                message = message .. string.format("\nUnits in Zone: %d", zoneState.unitsCount)
                message = message .. string.format("\nSAM Deployed: %s", zoneState.samDeployed and "YES" or "NO")
                message = message .. string.format("\nTruck Active: %s", zoneState.truckActive and "YES" or "NO")
                message = message .. string.format("\nHelo Active: %s", zoneState.heloActive and "YES" or "NO")
            else
                message = message .. "\nStatus: UNKNOWN"
            end
        end
        
        message = message .. string.format("\n\nSPAWN COUNTS:\nTruck: %d | Helo: %d", 
                                          MissionState.missions.truck.spawnCount,
                                          MissionState.missions.helo.spawnCount)
    else
        message = message .. "No deployment zones found!"

    end
    
    -- Check spawn zones
    message = message .. "\n\nSPAWN ZONES:"
    if MissionState.zones.truckSpawn then
        message = message .. "\n✓ Truck Spawn Zone: LOADED"
    else
        message = message .. "\n✗ Truck Spawn Zone: MISSING (will use fallback)"
    end
    
    if MissionState.zones.heloSpawn then
        message = message .. "\n✓ Helicopter Spawn Zone: LOADED"
    else
        message = message .. "\n✗ Helicopter Spawn Zone: MISSING (will use fallback)"
    end
    
    Utils.showMessage(message, 15)
end

function RadioMenu.initialize()    
    -- Create main menu
    local mainMenu = missionCommands.addSubMenu("Auto-Resupply System")
    
    -- Add commands for both coalitions
    for _, coalitionSide in pairs({coalition.side.RED, coalition.side.BLUE}) do
        missionCommands.addCommandForCoalition(coalitionSide, "Mission Status", mainMenu, RadioMenu.getMissionStatus)
        missionCommands.addCommandForCoalition(coalitionSide, "Check Zone Status", mainMenu, RadioMenu.checkZoneStatus)
        missionCommands.addCommandForCoalition(coalitionSide, "Check Truck Status", mainMenu, RadioMenu.checkTruckStatus)
        missionCommands.addCommandForCoalition(coalitionSide, "Check Helicopter Status", mainMenu, RadioMenu.checkHeloStatus)
        missionCommands.addCommandForCoalition(coalitionSide, "Start Zone Monitoring", mainMenu, ZoneMonitoring.startMultiZoneMonitoring)
        missionCommands.addCommandForCoalition(coalitionSide, "Stop Zone Monitoring", mainMenu, ZoneMonitoring.stopMultiZoneMonitoring)
        missionCommands.addCommandForCoalition(coalitionSide, "Manual Vehicle Cleanup", mainMenu, RadioMenu.manualCleanupVehicles)
        missionCommands.addCommandForCoalition(coalitionSide, "Reset Spawn Counts", mainMenu, RadioMenu.resetSpawnCounts)
        missionCommands.addCommandForCoalition(coalitionSide, "Reset All Missions", mainMenu, RadioMenu.resetMissions)
    end
    
end

-- =====================================================================================
-- EVENT HANDLING
-- =====================================================================================

local EventHandler = {}

function EventHandler.onEvent(event)
    if event.id == world.event.S_EVENT_UNIT_LOST then
        if event.initiator then
            local lostUnit = event.initiator
            
            -- Safely get the group
            local success, lostGroup = Utils.safeExecute(function()
                return lostUnit:getGroup()
            end, "Failed to get group for lost unit")
            
            if success and lostGroup then
                local groupName = lostGroup:getName()
                
                -- Check if lost unit belongs to our supply vehicles (using dynamic naming pattern)
                if string.find(groupName, "SupplyTruck_") then
                    Utils.showMessage("Supply truck unit lost!", 8)
                    -- Could implement respawn logic here
                elseif string.find(groupName, "SupplyHelo_") then
                    Utils.showMessage("Supply helicopter unit lost!", 8)
                    -- Could implement respawn logic here
                end
            end
        end
    end
end

function EventHandler.initialize()
    world.addEventHandler(EventHandler)
end

-- =====================================================================================
-- MISSION INITIALIZATION
-- =====================================================================================

local function initializeSupplyMission()
    Utils.showMessage("=== INITIALIZING AUTO-RESUPPLY SYSTEM ===", 5)
    
    -- Discover all deployment zones
    if not ZoneDiscovery.discoverDeploymentZones() then
        Utils.showMessage("ERROR: Failed to discover deployment zones!", 10)
        return false
    end
    
    -- Discover all supply zones (truck and helicopter spawn zones)
    if not Utils.discoverSupplyZones() then
        Utils.showMessage("WARNING: No supply zones found! Will use legacy zone configuration.", 8)
    end
    
    -- Initialize legacy spawn zones for backward compatibility
    MissionState.zones.truckSpawn = Utils.getZoneByName(CONFIG.ZONES.SUPPORT_TRUCK_DEPLOY)
    if not MissionState.zones.truckSpawn then
        Utils.showMessage("WARNING: Legacy truck spawn zone '" .. CONFIG.ZONES.SUPPORT_TRUCK_DEPLOY .. "' not found! Will use multi-zone system only.", 8)
    end
    
    MissionState.zones.heloSpawn = Utils.getZoneByName(CONFIG.ZONES.SUPPORT_HELO_DEPLOY)
    if not MissionState.zones.heloSpawn then
        Utils.showMessage("WARNING: Legacy helicopter spawn zone '" .. CONFIG.ZONES.SUPPORT_HELO_DEPLOY .. "' not found! Will use multi-zone system only.", 8)
    end
    
    -- Initialize subsystems
    EventHandler.initialize()
    RadioMenu.initialize()
    CargoManagement.initialize()
    
    -- Display distance-based deployment configuration
    Utils.showMessage("Distance-based vehicle selection: Trucks for targets within " .. CONFIG.ZONES.MAX_DISTANCE_FROM_DEPLOY .. "m, helicopters for longer distances.", 8)
    
    -- Display concurrent deployment limit
    Utils.showMessage("Maximum concurrent deployments: " .. CONFIG.ZONES.MAX_CONCURRENT_DEPLOYMENTS, 8)
    
    -- Perform initial zone analysis
    
    local allGroups = Utils.getGroundGroupsSafe()
    local allZones = ZoneDiscovery.getAllActiveZones()
    
    if #allZones > 0 then
        for _, zoneInfo in pairs(allZones) do
            local zoneName = zoneInfo.name
            local zone = zoneInfo.zone
            local unitsCount = 0
            
            for _, group in pairs(allGroups) do
                if group and group:isExist() then
                    local groupName = group:getName()
                    -- Skip supply vehicles (using dynamic naming pattern)
                    if not string.find(groupName, "SupplyTruck_") and not string.find(groupName, "SupplyHelo_") then
                        local success, units = pcall(group.getUnits, group)
                        if success and units then
                            for _, unit in pairs(units) do
                                if unit and unit:isExist() then
                                    local success2, unitPos = pcall(function() return unit:getPosition().p end)
                                    if success2 and unitPos and Utils.isPointInZone(unitPos, zone) then
                                        unitsCount = unitsCount + 1
                                    end
                                end
                            end
                        end
                    end
                end
            end
            
            Utils.showDebugMessage("Zone " .. zoneName .. " (" .. zoneInfo.type .. ") has " .. unitsCount .. " RED ground units at mission start", 8, 3 )
            
            -- Update zone state
            if MissionState.missions.zoneStates[zoneName] then
                MissionState.missions.zoneStates[zoneName].unitsCount = unitsCount
            end
        end
    else
        Utils.showMessage("No deployment zones discovered for monitoring!", 8)
    end
        
    -- Start zone monitoring with delay to prevent initialization race conditions
    timer.scheduleFunction(function()
        ZoneMonitoring.startMultiZoneMonitoring()
        Utils.showMessage("Zone monitoring started successfully!", 8)
        return nil
    end, nil, timer.getTime() + 10) -- 10 second delay to allow DCS to stabilize
    
    MissionState.initialized = true
    Utils.showMessage("System will automatically dispatch vehicles when zones are cleared.", 8)
    
    return true
end

-- Discover all supply zones (truck and helicopter spawn zones)
function Utils.discoverSupplyZones()
    local truckZones = {}
    local heloZones = {}
    local ammoZones = {}
    
    Utils.showDebugMessage("Discovering supply zones...", 5, 2)
    
    -- Try to discover zones using mission data first
    local env = _G.env or {}
    if env.mission and env.mission.triggers and env.mission.triggers.zones then
        for _, zone in pairs(env.mission.triggers.zones) do
            if zone.name then
                local zoneName = zone.name
                
                -- Check for truck deploy zones
                if string.find(zoneName, "^" .. CONFIG.ZONES.SUPPORT_TRUCK_DEPLOY) then
                    local zoneObj = trigger.misc.getZone(zoneName)
                    if zoneObj then
                        table.insert(truckZones, {
                            name = zoneName,
                            zone = zoneObj
                        })
                        Utils.showDebugMessage("Found truck spawn zone: " .. zoneName, 5, 2)
                    end
                end
                
                -- Check for helo deploy zones
                if string.find(zoneName, "^" .. CONFIG.ZONES.SUPPORT_HELO_DEPLOY) then
                    local zoneObj = trigger.misc.getZone(zoneName)
                    if zoneObj then
                        table.insert(heloZones, {
                            name = zoneName,
                            zone = zoneObj
                        })
                        Utils.showDebugMessage("Found helo spawn zone: " .. zoneName, 5, 2)
                    end
                end

                -- Check for ammo supply zones
                if string.find(zoneName, "^" .. CONFIG.ZONES.SUPPORT_AMMO_SUPPLY) then
                    local zoneObj = trigger.misc.getZone(zoneName)
                    if zoneObj then
                        table.insert(ammoZones, {
                            name = zoneName,
                            zone = zoneObj
                        })
                        Utils.showDebugMessage("Found ammo supply zone: " .. zoneName, 5, 2)
                    end
                end
            end
        end
    end
    
    -- Fallback: Try to get zones by name pattern
    if #truckZones == 0 and #heloZones == 0 and #ammoZones == 0 then
        Utils.showDebugMessage("No supply zones found via mission data, trying name-based discovery...", 5, 2)
        
        -- Try common naming patterns for truck zones
        for i = 0, 20 do  -- Check up to 20 numbered zones
            local suffix = (i == 0) and "" or ("-" .. i)
            
            -- Truck zones
            local truckZoneName = CONFIG.ZONES.SUPPORT_TRUCK_DEPLOY .. suffix
            local truckZone = trigger.misc.getZone(truckZoneName)
            if truckZone then
                table.insert(truckZones, {
                    name = truckZoneName,
                    zone = truckZone
                })
                Utils.showDebugMessage("Found truck spawn zone: " .. truckZoneName, 5, 2)
            end
            
            -- Helo zones
            local heloZoneName = CONFIG.ZONES.SUPPORT_HELO_DEPLOY .. suffix
            local heloZone = trigger.misc.getZone(heloZoneName)
            if heloZone then
                table.insert(heloZones, {
                    name = heloZoneName,
                    zone = heloZone
                })
                Utils.showDebugMessage("Found helo spawn zone: " .. heloZoneName, 5, 2)
            end

            -- ammoZones zones
            local ammoZoneName = CONFIG.ZONES.SUPPORT_AMMO_SUPPLY .. suffix
            local ammoZone = trigger.misc.getZone(ammoZoneName)
            if ammoZone then
                table.insert(ammoZone, {
                    name = ammoZoneName,
                    zone = ammoZone
                })
                Utils.showDebugMessage("Found ammo spawn zone: " .. ammoZoneName, 5, 2)
            end
        end
    end
    
    -- Store discovered zones
    MissionState.zones.truckSpawnZones = truckZones
    MissionState.zones.heloSpawnZones = heloZones
    MissionState.zones.ammoSpawnZones = ammoZones
    
    Utils.showMessage("Discovered " .. #truckZones .. " truck spawn zones and " .. #heloZones .. " helo spawn zones", 8)
    
    -- Set legacy references if base zones exist
    for _, zoneInfo in pairs(truckZones) do
        if zoneInfo.name == CONFIG.ZONES.SUPPORT_TRUCK_DEPLOY then
            MissionState.zones.truckSpawn = zoneInfo.zone
            break
        end
    end
    
    for _, zoneInfo in pairs(heloZones) do
        if zoneInfo.name == CONFIG.ZONES.SUPPORT_HELO_DEPLOY then
            MissionState.zones.heloSpawn = zoneInfo.zone
            break
        end
    end

    for _, zoneInfo in pairs(ammoZones) do
        if zoneInfo.name == CONFIG.ZONES.SUPPORT_AMMO_SUPPLY then
            MissionState.zones.ammoSpawnZone = zoneInfo.zone
            break
        end
    end
    
    return #truckZones > 0 or #heloZones > 0 or #ammoZones > 0
end

-- Find the closest supply zone of specified type to a target zone
function Utils.getClosestSupplyZone(targetZone, vehicleType)
    if not targetZone or not targetZone.point then
        Utils.showDebugMessage("Invalid target zone for closest supply zone search", 5, 3)
        return nil
    end
    
    local targetPoint = {x = targetZone.point.x, z = targetZone.point.z}
    local supplyZones = {}
    
    -- Get appropriate supply zones based on vehicle type
    if vehicleType == "truck" then
        supplyZones = MissionState.zones.truckSpawnZones
    elseif vehicleType == "helo" then
        supplyZones = MissionState.zones.heloSpawnZones
    else
        Utils.showDebugMessage("Invalid vehicle type for supply zone search: " .. tostring(vehicleType), 5, 3)
        return nil
    end
    
    if #supplyZones == 0 then
        Utils.showDebugMessage("No " .. vehicleType .. " supply zones available", 5, 3)
        return nil
    end
    
    local closestZone = nil
    local shortestDistance = math.huge
    
    -- Find the closest supply zone
    for _, zoneInfo in pairs(supplyZones) do
        if zoneInfo.zone and zoneInfo.zone.point then
            local supplyPoint = {x = zoneInfo.zone.point.x, z = zoneInfo.zone.point.z}
            local distance = Utils.getDistance(targetPoint, supplyPoint)
            
            Utils.showDebugMessage("Distance from " .. zoneInfo.name .. " to target: " .. math.floor(distance) .. "m", 5, 3)
            
            if distance < shortestDistance then
                shortestDistance = distance
                closestZone = zoneInfo
            end
        end
    end
    
    if closestZone then
        Utils.showDebugMessage("Closest " .. vehicleType .. " supply zone: " .. closestZone.name .. " (" .. math.floor(shortestDistance) .. "m away)", 5, 2)
    end
    
    return closestZone, shortestDistance
end

-- =====================================================================================
-- SCRIPT INITIALIZATION
-- =====================================================================================

-- Initialize the mission when script loads
timer.scheduleFunction(function()
    initializeSupplyMission()
    return nil
end, nil, timer.getTime() + 1)