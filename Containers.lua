-- =====================================================================================
-- DCS AUTO-RESUPPLY MISSION SCRIPT - COMPLETE VERSION
-- Description: Automated supply truck and helicopter missions for local SAM site replacement
-- Author: MythNZ
-- Version: 0.3.24 Supply Management
-- =====================================================================================

-- =====================================================================================
-- CONFIGURATION SECTION
-- =====================================================================================

local CONFIG = {
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
    
    -- Mission Parameters
    RED_COALITION = coalition.side.RED,
    BLUE_COALITION = coalition.side.BLUE,
    CHECK_INTERVAL = 10, -- Interval for checking zones and units (in seconds)
    HELICOPTER_CHECK_INTERVAL = 3, -- Faster interval for helicopter monitoring (in seconds)
    DEBUG_MODE = 1, -- Debug levels: 0=off, 1=basic, 2=detailed, 3=verbose
    
    -- Spawn Limits the sum will be the starting
    SPAWN_LIMITS = {
        TRUCK = 5,
        HELO = 5
    },

    STARTING_SUPPLY_OBJECTS = 10, -- Number of initial supply objects to spawn in the SUPPORT_AMMO_SUPPLY zone
    
    -- SAM Deployment Settings
    SAM = {
        ACTIVATION_ATTEMPTS = 3,
        RETRY_DELAY = 2,
        UNIT_SPACING = 30,
        CLEANUP_DELAY = 15, -- Increased to 15 seconds for ultra-safe vehicle cleanup after SAM deployment (especially for helicopters)
        ENABLE_VEHICLE_CLEANUP = true, -- Re-enabled with safer cleanup method
        -- Position randomization settings
        POSITION_RANDOMIZATION = {
            ENABLED = true,
            MAX_OFFSET = 15, -- Maximum random offset in meters
            MIN_DISTANCE = 8  -- Minimum distance between units
        },
        -- Safe cleanup position (not used in ultra-safe mode, but kept for reference)
        SAFE_CLEANUP_POSITION = {x = -50000, y = 0, z = -50000}
    },
    
    -- Vehicle Route Settings
    VEHICLE = {
        TRUCK_SPEED = 20,
        HELO_SPEED = 50,
        HELO_ALTITUDE = 500,
        ENABLE_HELICOPTER_SPAWNING = true -- IMPORTANT: Disabled by default due to potential crash issues
        -- CRASH SAFETY: Set to true ONLY if you're confident in your DCS stability
        -- Helicopters may cause crashes due to complex spawning requirements and DCS engine limitations
        -- v0.3.16: Added comprehensive crash prevention, but keep disabled until thoroughly tested
    },

    SAM_UNITS = {
        SHORT_RANGE = {
            [country.id.CJTF_BLUE] = {
                { type = "NASAMS_Command_Post", skill = "High" },
                { type = "NASAMS_Radar_MPQ64F1", skill = "High" },
                { type = "M 818", skill = "High" },
                { type = "NASAMS_LN_B", skill = "High" }
            },
            [country.id.CJTF_RED] = {
                { type = "snr s-125 tr", skill = "High" },  -- Short range radar unit
                -- { type = "5p73 s-125 ln", skill = "High" },  -- Short range launcher unit
                -- { type = "5p73 s-125 ln", skill = "High" },  -- Short range launcher unit
                { type = "p-19 s-125 sr", skill = "High" },  -- Short range command post unit
                { type = "Ural-4320-31", skill = "High" }

            }
        },
        LONG_RANGE = {
            [country.id.CJTF_BLUE] = {
                { type = "Hawk cwar", skill = "High" },
                { type = "Hawk ln", skill = "High" },
                { type = "Hawk ln", skill = "High" },
                { type = "Hawk pcp", skill = "High" },
                { type = "Hawk sr", skill = "High" },
                { type = "Hawk tr", skill = "High" },
                { type = "M 818", skill = "High" }
            },
            [country.id.CJTF_RED] = {
                { type = "Kub 2P25 ln", skill = "High" },  -- Medium range launcher unit
                -- { type = "Kub 2P25 ln", skill = "High" },  -- Medium range launcher unit
                -- { type = "Kub 2P25 ln", skill = "High" }  -- Medium range launcher unit
                { type = "Kub 1S91 str", skill = "High" },  -- Medium range Search Track Radar unit
                { type = "Kub 1S91 str", skill = "High" },  -- Medium range Search Track Radar unit
                { type = "Ural-4320-31", skill = "High" }, 
            }
        },
    },

    -- Supply Vehicle Configurations
    SUPPLY_VEHICLES = {
        TRUCK = {
            [country.id.CJTF_BLUE] = {
                { type = "M 818", skill = "High" },
                { type = "Hummer", skill = "High" },
                { type = "M1043 HMMWV Armament", skill = "High" }
            },
            [country.id.CJTF_RED] = {
                { type = "Ural-375", skill = "High" },
                -- { type = "UAZ-469", skill = "High" },
                -- { type = "Ural-4320-31", skill = "High" }
            }
        },
        HELICOPTER = {
            [country.id.CJTF_BLUE] = {
                { type = "UH-1H", skill = "High", livery = nil },
                { type = "Mi-8MT", skill = "High", livery = nil }
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
    },
}

-- =====================================================================================
-- STATE MANAGEMENT
-- =====================================================================================

local MissionState = {
    -- Vehicle Groups - Now supports multiple supply groups
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
        truckSpawn = nil,  -- Legacy single truck spawn zone
        heloSpawn = nil,   -- Legacy single helo spawn zone
        ammoSupplyZone = nil  -- Ammo supply zone for cargo spawning
    },
    
    -- Mission Status - Now per zone
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
    
    -- Cargo Management
    spawnedCargo = {},  -- Track currently spawned cargo objects
    cargoSpawnCount = 0, -- Counter for unique cargo naming
    
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
    if CONFIG.DEBUG_MODE <= level then
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
    
    Utils.showDebugMessage("Active deployments: " .. activeCount .. "/" .. CONFIG.ZONES.MAX_CONCURRENT_DEPLOYMENTS, 3)
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
            Utils.showMessage("SAM group repositioned to deployment zone.", 8)
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
        Utils.showMessage("Supply vehicles will remain in the field (cleanup disabled for crash prevention)", 8)
        return
    end
    
    local isHeloMission = (missionType == "helicopter")
    
    Utils.showDebugMessage("Scheduling ultra-safe vehicle cleanup for " .. missionType .. " mission in zone " .. (zoneName or "unknown"), 5 ,3)
   
    timer.scheduleFunction(function()
        Utils.showMessage("DEBUG: Vehicle cleanup timer executed for " .. missionType .. " in zone " .. (zoneName or "unknown"), 8,3)
        
        if isHeloMission then
            -- Ultra-safe cleanup of helicopter for this specific zone only
            if zoneName and MissionState.vehicles.supplyGroups[zoneName] then
                Utils.showMessage("DEBUG: Found helicopter supply group for cleanup in zone " .. zoneName, 8)
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
                            Utils.showMessage("Cleaning up helicopter: " .. groupName .. " in zone " .. zoneName, 8)
                            
                            -- Method 1: Try immediate destruction (simplest and most reliable)
                            supplyGroup:destroy()
                            
                            Utils.showDebugMessage("Helicopter group destroyed: " .. groupName, 5)
                        end
                    end)
                    
                    if cleanupSuccess then
                        Utils.showMessage("Supply helicopter '" .. groupName .. "' completed mission for zone " .. zoneName .. " and returned to base.", 8)
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
                Utils.showMessage("DEBUG: Found truck supply group for cleanup in zone " .. zoneName, 8)
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
                            Utils.showMessage("Cleaning up truck: " .. groupName .. " in zone " .. zoneName, 8)
                            
                            -- Method 1: Try immediate destruction (simplest and most reliable)
                            supplyGroup:destroy()
                            
                            Utils.showDebugMessage("Truck group destroyed: " .. groupName, 5)
                        end
                    end)
                    
                    if cleanupSuccess then
                        Utils.showMessage("Supply truck '" .. groupName .. "' completed mission for zone " .. zoneName .. " and withdrew.", 8)
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
    Utils.showMessage("=== DISCOVERING DEPLOYMENT ZONES ===", 5)
    Utils.showMessage("Looking for zones with prefixes: " .. CONFIG.ZONES.SR_SAM_DEPLOYMENT_PREFIX .. " and " .. CONFIG.ZONES.LR_SAM_DEPLOYMENT_PREFIX, 8)
    
    local srZones = {}
    local lrZones = {}
    local totalZones = 0
    
    -- Get all trigger zones in the mission
    local env = _G.env or {}
    if env.mission and env.mission.triggers and env.mission.triggers.zones then
        Utils.showMessage("Checking mission trigger zones...", 8)
        for _, zone in pairs(env.mission.triggers.zones) do
            if zone.name then
                local zoneName = zone.name
                Utils.showDebugMessage("Checking zone: " .. zoneName, 5, 2)
                
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
                        Utils.showMessage("Found short range SAM zone: " .. zoneName, 8)
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
                        Utils.showMessage("Found long range SAM zone: " .. zoneName, 8)
                        totalZones = totalZones + 1
                    end
                end
            end
        end
    else
        Utils.showMessage("No mission environment data available, trying fallback method...", 8)
    end
    
    -- Fallback: Try to get zones by name pattern (less reliable but worth trying)
    if totalZones == 0 then
        Utils.showMessage("No zones found via mission data, trying name-based discovery...", 8)
        
        -- Try common naming patterns
        for i = 0, 20 do  -- Check up to 20 numbered zones
            local suffix = (i == 0) and "" or ("-" .. i)
            
            -- Short range zones
            local srZoneName = CONFIG.ZONES.SR_SAM_DEPLOYMENT_PREFIX .. suffix
            Utils.showDebugMessage("Trying to find zone: " .. srZoneName, 5, 3)
            local srZone = trigger.misc.getZone(srZoneName)
            if srZone then
                table.insert(srZones, {
                    name = srZoneName,
                    zone = srZone,
                    type = "SHORT_RANGE",
                    active = true
                })
                Utils.showMessage("Found short range SAM zone: " .. srZoneName, 8)
                totalZones = totalZones + 1
            end
            
            -- Long range zones
            local lrZoneName = CONFIG.ZONES.LR_SAM_DEPLOYMENT_PREFIX .. suffix
            Utils.showDebugMessage("Trying to find zone: " .. lrZoneName, 5, 3)
            local lrZone = trigger.misc.getZone(lrZoneName)
            if lrZone then
                table.insert(lrZones, {
                    name = lrZoneName,
                    zone = lrZone,
                    type = "LONG_RANGE",
                    active = true
                })
                Utils.showMessage("Found long range SAM zone: " .. lrZoneName, 8)
                totalZones = totalZones + 1
            end
        end
        
        -- Also try without numbers or suffixes
        Utils.showDebugMessage("Trying base zone names without suffixes...", 5, 2)
        local baseShortZone = trigger.misc.getZone(CONFIG.ZONES.SR_SAM_DEPLOYMENT_PREFIX)
        if baseShortZone then
            table.insert(srZones, {
                name = CONFIG.ZONES.SR_SAM_DEPLOYMENT_PREFIX,
                zone = baseShortZone,
                type = "SHORT_RANGE",
                active = true
            })
            Utils.showMessage("Found base short range SAM zone: " .. CONFIG.ZONES.SR_SAM_DEPLOYMENT_PREFIX, 8)
            totalZones = totalZones + 1
        end
        
        local baseLongZone = trigger.misc.getZone(CONFIG.ZONES.LR_SAM_DEPLOYMENT_PREFIX)
        if baseLongZone then
            table.insert(lrZones, {
                name = CONFIG.ZONES.LR_SAM_DEPLOYMENT_PREFIX,
                zone = baseLongZone,
                type = "LONG_RANGE",
                active = true
            })
            Utils.showMessage("Found base long range SAM zone: " .. CONFIG.ZONES.LR_SAM_DEPLOYMENT_PREFIX, 8)
            totalZones = totalZones + 1
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
    Utils.showMessage("Started monitoring all deployment zones for enemy elimination and SAM destruction.", 8)
    
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
                    Utils.showDebugMessage("Zone " .. zoneName .. " already has active supply mission", 3)
                else
                    -- Clean up dead reference
                    MissionState.vehicles.supplyGroups[zoneName] = nil
                end
            end
            
            if not zoneHasSupplyMission then
                -- Check if we've reached the maximum concurrent deployments limit
                local activeDeployments = Utils.countActiveDeployments()
                if activeDeployments >= CONFIG.ZONES.MAX_CONCURRENT_DEPLOYMENTS then
                    Utils.showDebugMessage("Zone " .. zoneName .. " clear but max concurrent deployments (" .. CONFIG.ZONES.MAX_CONCURRENT_DEPLOYMENTS .. ") reached. Waiting for deployment slots...", 5)
                    if CONFIG.DEBUG_MODE == 1 then
                        Utils.showMessage("Zone " .. zoneName .. " waiting for deployment slot (" .. activeDeployments .. "/" .. CONFIG.ZONES.MAX_CONCURRENT_DEPLOYMENTS .. " active)", 8)
                    end
                    return -- Skip this zone for now
                end
                
                -- RACE CONDITION FIX: Reserve the deployment slot immediately
                -- Create a placeholder to prevent other zones from spawning simultaneously
                MissionState.vehicles.supplyGroups[zoneName] = "DEPLOYMENT_PENDING"
                Utils.showDebugMessage("Reserved deployment slot for zone " .. zoneName, 5)
                
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
                        Utils.showMessage("Zone " .. zoneName .. " clear! Dispatching supply truck (optimal for distance)...", 10)
                        VehicleSpawning.spawnTruckForZone(zoneInfo)
                    else
                        Utils.showMessage("Zone " .. zoneName .. " clear! Dispatching supply helicopter (optimal for distance)...", 10)
                        VehicleSpawning.spawnHeloForZone(zoneInfo)
                    end
                elseif canDispatchAlternate then
                    if optimalVehicleType == "truck" then
                        Utils.showMessage("Zone " .. zoneName .. " clear! Truck unavailable, dispatching supply helicopter...", 10)
                        VehicleSpawning.spawnHeloForZone(zoneInfo)
                    else
                        Utils.showMessage("Zone " .. zoneName .. " clear! Helicopter unavailable, dispatching supply truck...", 10)
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
            Utils.showMessage("SAM site in zone " .. zoneName .. " has been destroyed! Re-deployment now available.", 10)
            zoneState.samDeployed = false
            -- Reset spawn counts to enable continuous resupply
            MissionState.missions.truck.spawnCount = CONFIG.SPAWN_LIMITS.TRUCK
            MissionState.missions.helo.spawnCount = CONFIG.SPAWN_LIMITS.HELO
            Utils.showMessage("Spawn counts replenished for zone " .. zoneName .. ". Resuming monitoring for enemy elimination...", 8)
        end
    end
end

function ZoneMonitoring.stopMultiZoneMonitoring()
    MissionState.monitoring.monitoringActive = false
    Utils.showMessage("Stopped multi-zone monitoring.", 5)
end

-- Legacy functions for backward compatibility
function ZoneMonitoring.startTruckZoneMonitoring()
    Utils.showMessage("Starting legacy truck zone monitoring - redirecting to multi-zone monitoring...", 5)
    ZoneMonitoring.startMultiZoneMonitoring()
end

function ZoneMonitoring.startHeloZoneMonitoring()
    Utils.showMessage("Starting legacy helo zone monitoring - redirecting to multi-zone monitoring...", 5)
    ZoneMonitoring.startMultiZoneMonitoring()
end

function ZoneMonitoring.stopTruckZoneMonitoring()
    Utils.showMessage("Stopping legacy truck zone monitoring - multi-zone monitoring continues...", 5)
end

function ZoneMonitoring.stopHeloZoneMonitoring()
    Utils.showMessage("Stopping legacy helo zone monitoring - multi-zone monitoring continues...", 5)
end

-- =====================================================================================
-- SAM DEPLOYMENT FUNCTIONS 
-- Dependancy ZoneMonitoring
-- =====================================================================================

function SAMDeployment.spawnManually(templateName, targetZone, missionType, zoneName)
    local isHeloMission = (missionType == "helicopter")
    
    Utils.showMessage("Creating SAM site manually at target zone " .. (zoneName or "unknown") .. "...", 8)
    Utils.showDebugMessage("Mission type: " .. missionType, 5)
    Utils.showDebugMessage("Zone name: " .. (zoneName or "unknown"), 5)
    
    local samUnits = {}
    
    -- Get zone-specific SAM units
    if zoneName then
        samUnits = ZoneDiscovery.getSAMUnitsForZone(zoneName) or {}
        if #samUnits > 0 then
            Utils.showDebugMessage("Using " .. #samUnits .. " zone-specific SAM units for " .. zoneName, 5)
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
            -- Fallback to linear spacing
            unitX = targetZone.point.x + (i * CONFIG.SAM.UNIT_SPACING)
            unitZ = targetZone.point.z + (i * CONFIG.SAM.UNIT_SPACING)
            
            Utils.showDebugMessage("Using linear spacing for unit " .. i, 5)
        end
        
        -- Apply randomization if enabled
        if CONFIG.SAM.POSITION_RANDOMIZATION.ENABLED then
            local maxOffset = CONFIG.SAM.POSITION_RANDOMIZATION.MAX_OFFSET
            local randomX = (math.random() - 0.5) * 2 * maxOffset
            local randomZ = (math.random() - 0.5) * 2 * maxOffset
            
            unitX = unitX + randomX
            unitZ = unitZ + randomZ
            
            Utils.showDebugMessage("Applied randomization: +" .. randomX .. ", +" .. randomZ, 5)
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
        Utils.showMessage("SAM site deployed via " .. missionType .. " and is now active at zone " .. (zoneName or "unknown") .. "!", 15)
        
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
            Utils.showMessage("Starting zone monitoring for SAM destruction detection...", 8)
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
    Utils.showDebugMessage("Creating new supply truck group for zone " .. zoneName .. "...", 5)
    
    -- Find the closest truck supply zone to the target
    local closestSupplyZone, distance = Utils.getClosestSupplyZone(targetZone, "truck")
    local spawnPoint
    
    if closestSupplyZone and closestSupplyZone.zone then
        -- Spawn at the closest truck supply zone
        spawnPoint = {
            x = closestSupplyZone.zone.point.x,
            z = closestSupplyZone.zone.point.z
        }
        Utils.showDebugMessage("Using closest truck spawn zone: " .. closestSupplyZone.name .. " at (" .. spawnPoint.x .. ", " .. spawnPoint.z .. ") - " .. math.floor(distance) .. "m away", 5)
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
                    Utils.showMessage("Supply truck spawned successfully for zone " .. zoneName .. " with " .. #units .. " units!", 8)
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
        Utils.showMessage("Helicopter spawning disabled for crash prevention. Using truck deployment instead.", 8)
        Utils.showDebugMessage("Helicopter spawning disabled in CONFIG.VEHICLE.ENABLE_HELICOPTER_SPAWNING", 5)
        return false
    end
    
    Utils.showDebugMessage("Creating crash-safe helicopter group for zone " .. zoneName .. "...", 5)
    
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
    
    Utils.showDebugMessage("Attempting to spawn validated helicopter group...", 5)
    
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
        Utils.showMessage("Failed to spawn helicopter for zone " .. zoneName, 8)
        Utils.showDebugMessage("Helicopter spawn completely failed", 5)
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
                Utils.showDebugMessage("Helicopter " .. uniqueGroupName .. " verified and en route to zone " .. zoneName, 5)
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
    
    Utils.showDebugMessage("Attempting to spawn supply truck for zone " .. zoneName .. "...", 5)
    
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
                -- Release the deployment slot if spawn ultimately failed
                if MissionState.vehicles.supplyGroups[zoneName] == "DEPLOYMENT_PENDING" then
                    MissionState.vehicles.supplyGroups[zoneName] = nil
                    Utils.showDebugMessage("Released deployment slot for failed truck spawn in zone " .. zoneName, 5)
                end
            end
            return nil
        end, nil, timer.getTime() + 2)
    else
        -- Release the deployment slot if spawn failed immediately
        if MissionState.vehicles.supplyGroups[zoneName] == "DEPLOYMENT_PENDING" then
            MissionState.vehicles.supplyGroups[zoneName] = nil
            Utils.showDebugMessage("Released deployment slot for failed truck spawn in zone " .. zoneName, 5)
        end
    end
    
    return success
end

function VehicleSpawning.spawnHeloForZone(zoneInfo)
    Utils.showMessage("DEBUG: Helicopter spawn requested for zone " .. zoneInfo.name, 8)
    Utils.showDebugMessage("DEBUG: Helicopter spawn count available: " .. MissionState.missions.helo.spawnCount, 5)
    
    if MissionState.missions.helo.spawnCount <= 0 then
        Utils.showMessage("No more helicopter spawns available for zone " .. zoneInfo.name .. "!", 5)
        return false
    end
    
    local zoneName = zoneInfo.name
    local targetZone = zoneInfo.zone
    
    Utils.showMessage("DEBUG: Target zone for helicopter: " .. zoneName .. " at (" .. targetZone.point.x .. ", " .. targetZone.point.z .. ")", 8)
    Utils.showDebugMessage("Attempting to spawn supply helicopter for zone " .. zoneName .. "...", 5)
    
    -- Mark zone as having helo mission active
    if MissionState.missions.zoneStates[zoneName] then
        MissionState.missions.zoneStates[zoneName].heloActive = true
        Utils.showMessage("DEBUG: Marked zone " .. zoneName .. " as having active helicopter mission", 8)
    end
    
    -- Create unique group name for this zone
    local uniqueGroupName = "SupplyHelo_" .. zoneName .. "_" .. timer.getTime()
    
    Utils.showMessage("DEBUG: Creating helicopter group: " .. uniqueGroupName, 8)
    
    -- Try to spawn unique helicopter for this zone
    local success = VehicleSpawning.spawnNewHeloForZone(zoneName, uniqueGroupName, targetZone)
    if success then
        Utils.showMessage("DEBUG: Helicopter spawn successful, starting position monitoring...", 8)
        -- Start monitoring helicopter position (no separate route setup needed)
        timer.scheduleFunction(function()
            local supplyGroup = MissionState.vehicles.supplyGroups[zoneName]
            if supplyGroup and supplyGroup ~= "DEPLOYMENT_PENDING" and supplyGroup:isExist() then
                Utils.showMessage("DEBUG: Found helicopter group for monitoring: " .. supplyGroup:getName(), 8)
                Utils.showDebugMessage("Starting position monitoring for helicopter " .. uniqueGroupName .. " in zone " .. zoneName, 5)
                VehicleSpawning.startHeloPositionMonitoringForZone(zoneInfo, supplyGroup)
            else
                Utils.showMessage("DEBUG: Failed to find helicopter group for monitoring in zone " .. zoneName, 8)
                Utils.showDebugMessage("Failed to start helicopter monitoring for zone " .. zoneName .. " - group not found", 5)
                -- Release the deployment slot if spawn ultimately failed
                if MissionState.vehicles.supplyGroups[zoneName] == "DEPLOYMENT_PENDING" then
                    MissionState.vehicles.supplyGroups[zoneName] = nil
                    Utils.showDebugMessage("Released deployment slot for failed helicopter spawn in zone " .. zoneName, 5)
                end
            end
            return nil
        end, nil, timer.getTime() + 2)
    else
        Utils.showMessage("DEBUG: Helicopter spawn failed for zone " .. zoneName, 8)
        -- Release the deployment slot if spawn failed immediately
        if MissionState.vehicles.supplyGroups[zoneName] == "DEPLOYMENT_PENDING" then
            MissionState.vehicles.supplyGroups[zoneName] = nil
            Utils.showDebugMessage("Released deployment slot for failed helicopter spawn in zone " .. zoneName, 5)
        end
    end
    
    return success
end

-- Complete route setup and monitoring functions
function VehicleSpawning.setupTruckRouteToZone(targetZone, supplyGroup)
    if not supplyGroup or not supplyGroup:isExist() then
        Utils.showDebugMessage("Cannot setup route: invalid supply group", 5)
        return false
    end
    
    if not targetZone or not targetZone.point then
        Utils.showDebugMessage("Cannot setup route: invalid target zone", 5)
        return false
    end
    
    Utils.showDebugMessage("Setting up truck route to target zone at (" .. targetZone.point.x .. ", " .. targetZone.point.z .. ")", 5)
    
    -- Get current group position
    local groupPos = supplyGroup:getUnits()[1]:getPosition().p
    
    -- Create route with current position and target
    local route = {
        [1] = {
            ["alt"] = 0,
            ["type"] = "Turning Point",
            ["ETA"] = 0,
            ["alt_type"] = "BARO",
            ["formation_template"] = "",
            ["y"] = groupPos.z,
            ["x"] = groupPos.x,
            ["ETA_locked"] = false,
            ["speed"] = CONFIG.VEHICLE.TRUCK_SPEED,
            ["action"] = "Off Road",
            ["task"] = {
                ["id"] = "ComboTask",
                ["params"] = { ["tasks"] = {} }
            },
            ["speed_locked"] = true,
        },
        [2] = {
            ["alt"] = 0,
            ["type"] = "Turning Point",
            ["ETA"] = 0,
            ["alt_type"] = "BARO",
            ["formation_template"] = "",
            ["y"] = targetZone.point.z,
            ["x"] = targetZone.point.x,
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
    
    -- Apply the route to the group
    local controller = supplyGroup:getController()
    if controller then
        controller:setTask({
            id = 'Mission',
            params = {
                route = {
                    points = route
                }
            }
        })
        Utils.showDebugMessage("Route successfully applied to truck group", 5)
        return true
    else
        Utils.showDebugMessage("Failed to get controller for truck group", 5)
        return false
    end
end

function VehicleSpawning.startTruckPositionMonitoringForZone(zoneInfo, supplyGroup)
    if not supplyGroup or not supplyGroup:isExist() then
        Utils.showDebugMessage("Cannot start monitoring: invalid supply group for zone " .. zoneInfo.name, 5)
        return
    end
    
    Utils.showDebugMessage("Starting truck position monitoring for zone " .. zoneInfo.name, 5)
    
    local function monitorPosition()
        if not supplyGroup or not supplyGroup:isExist() then
            Utils.showDebugMessage("Truck group no longer exists for zone " .. zoneInfo.name .. ", stopping monitoring", 5)
            return nil -- Stop monitoring
        end
        
        local units = supplyGroup:getUnits()
        if not units or #units == 0 then
            Utils.showDebugMessage("No units in truck group for zone " .. zoneInfo.name .. ", stopping monitoring", 5)
            return nil -- Stop monitoring
        end
        
        local leadUnit = units[1]
        if not leadUnit or not leadUnit:isExist() then
            Utils.showDebugMessage("Lead truck unit no longer exists for zone " .. zoneInfo.name .. ", stopping monitoring", 5)
            return nil -- Stop monitoring
        end
        
        local unitPos = leadUnit:getPosition().p
        local distanceToZone = Utils.getDistance(unitPos, zoneInfo.zone.point)
        
        -- Check if truck reached the deployment zone
        if distanceToZone <= zoneInfo.zone.radius then
            Utils.showMessage("Supply truck has reached deployment zone " .. zoneInfo.name .. "!", 8)
            Utils.showDebugMessage("Truck reached zone " .. zoneInfo.name .. " - distance: " .. math.floor(distanceToZone) .. "m", 5)
            
            -- Mark zone as supplied and stop monitoring
            if MissionState.missions.zoneStates[zoneInfo.name] then
                MissionState.missions.zoneStates[zoneInfo.name].truckActive = false
                MissionState.missions.zoneStates[zoneInfo.name].lastSupplied = timer.getTime()
            end
            
            return nil -- Stop monitoring - truck has arrived
        end
        
        -- Continue monitoring every 5 seconds
        return timer.getTime() + 5
    end
    
    -- Start position monitoring
    timer.scheduleFunction(monitorPosition, nil, timer.getTime() + 5)
end

function VehicleSpawning.startHeloPositionMonitoringForZone(zoneInfo, supplyGroup)
    if not supplyGroup or not supplyGroup:isExist() then
        Utils.showDebugMessage("Cannot start monitoring: invalid supply group for zone " .. zoneInfo.name, 5)
        return
    end
    
    Utils.showDebugMessage("Starting helicopter position monitoring for zone " .. zoneInfo.name, 5)
    
    local function monitorPosition()
        if not supplyGroup or not supplyGroup:isExist() then
            Utils.showDebugMessage("Helicopter group no longer exists for zone " .. zoneInfo.name .. ", stopping monitoring", 5)
            return nil -- Stop monitoring
        end
        
        local units = supplyGroup:getUnits()
        if not units or #units == 0 then
            Utils.showDebugMessage("No units in helicopter group for zone " .. zoneInfo.name .. ", stopping monitoring", 5)
            return nil -- Stop monitoring
        end
        
        local leadUnit = units[1]
        if not leadUnit or not leadUnit:isExist() then
            Utils.showDebugMessage("Lead helicopter unit no longer exists for zone " .. zoneInfo.name .. ", stopping monitoring", 5)
            return nil -- Stop monitoring
        end
        
        local unitPos = leadUnit:getPosition().p
        local distanceToZone = Utils.getDistance(unitPos, zoneInfo.zone.point)
        
        -- Check if helicopter reached the deployment zone
        if distanceToZone <= zoneInfo.zone.radius + 100 then -- Extra margin for helicopters
            Utils.showMessage("Supply helicopter has reached deployment zone " .. zoneInfo.name .. "!", 8)
            Utils.showDebugMessage("Helicopter reached zone " .. zoneInfo.name .. " - distance: " .. math.floor(distanceToZone) .. "m", 5)
            
            -- Mark zone as supplied and stop monitoring
            if MissionState.missions.zoneStates[zoneInfo.name] then
                MissionState.missions.zoneStates[zoneInfo.name].heloActive = false
                MissionState.missions.zoneStates[zoneInfo.name].lastSupplied = timer.getTime()
            end
            
            return nil -- Stop monitoring - helicopter has arrived
        end
        
        -- Continue monitoring every 5 seconds
        return timer.getTime() + 5
    end
    
    -- Start position monitoring
    timer.scheduleFunction(monitorPosition, nil, timer.getTime() + 5)
end

-- =====================================================================================
-- CARGO MANAGEMENT SYSTEM
-- =====================================================================================

-- Initialize the cargo management system and spawn initial supply objects
function CargoManagement.initialize()
    Utils.showMessage("=== INITIALIZING CARGO MANAGEMENT SYSTEM ===", 5)
    
    -- Discover and load the ammo supply zone
    MissionState.zones.ammoSupplyZone = Utils.getZoneByName(CONFIG.ZONES.SUPPORT_AMMO_SUPPLY)
    if not MissionState.zones.ammoSupplyZone then
        Utils.showMessage("WARNING: Ammo supply zone '" .. CONFIG.ZONES.SUPPORT_AMMO_SUPPLY .. "' not found! Cargo spawning disabled.", 10)
        return false
    end
    
    Utils.showMessage("Ammo supply zone loaded successfully: " .. CONFIG.ZONES.SUPPORT_AMMO_SUPPLY, 5)
    Utils.showDebugMessage("Ammo supply zone center: (" .. MissionState.zones.ammoSupplyZone.point.x .. ", " .. MissionState.zones.ammoSupplyZone.point.z .. "), radius: " .. MissionState.zones.ammoSupplyZone.radius .. "m", 5, 2)
    
    -- Spawn initial supply objects
    CargoManagement.spawnInitialSupplyObjects()
    
    return true
end

-- Spawn the initial supply objects in the ammo supply zone
function CargoManagement.spawnInitialSupplyObjects()
    if not MissionState.zones.ammoSupplyZone then
        Utils.showDebugMessage("Cannot spawn initial supply objects - ammo supply zone not available", 5)
        return false
    end
    
    if not CONFIG.AVAILABLE_SUPPLY_OBJECT_TYPES or #CONFIG.AVAILABLE_SUPPLY_OBJECT_TYPES == 0 then
        Utils.showMessage("ERROR: No supply object types configured in AVAILABLE_SUPPLY_OBJECT_TYPES!", 10)
        return false
    end
    
    local objectsToSpawn = CONFIG.STARTING_SUPPLY_OBJECTS or 10
    Utils.showMessage("Spawning " .. objectsToSpawn .. " initial supply objects in " .. CONFIG.ZONES.SUPPORT_AMMO_SUPPLY .. "...", 8)
    
    local successCount = 0
    local failureCount = 0
    
    for i = 1, objectsToSpawn do
        local success = CargoManagement.spawnRandomSupplyObject()
        if success then
            successCount = successCount + 1
        else
            failureCount = failureCount + 1
        end
        
        -- Small delay between spawns to prevent issues
        if i < objectsToSpawn then
            timer.scheduleFunction(function()
                return nil
            end, nil, timer.getTime() + 0.1)
        end
    end
    
    Utils.showMessage("Initial supply spawn completed: " .. successCount .. " objects spawned successfully, " .. failureCount .. " failed", 10)
    Utils.showDebugMessage("Current cargo count: " .. #MissionState.spawnedCargo, 5, 2)
    
    return successCount > 0
end

-- Spawn a random supply object in the ammo supply zone
function CargoManagement.spawnRandomSupplyObject()
    if not MissionState.zones.ammoSupplyZone then
        Utils.showDebugMessage("Cannot spawn supply object - ammo supply zone not available", 5, 3)
        return false
    end
    
    -- Select random supply object type
    local objectTypes = CONFIG.AVAILABLE_SUPPLY_OBJECT_TYPES
    local randomIndex = math.random(1, #objectTypes)
    local selectedType = objectTypes[randomIndex]
    
    Utils.showDebugMessage("Selected random supply type: " .. selectedType.name .. " (" .. selectedType.type .. ")", 5, 3)
    
    -- Generate random position within the zone
    local spawnPos = CargoManagement.getRandomPositionInZone(MissionState.zones.ammoSupplyZone)
    if not spawnPos then
        Utils.showDebugMessage("Failed to generate random position in ammo supply zone", 5)
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

-- Generate a random position within a zone, avoiding overlaps with existing cargo
function CargoManagement.getRandomPositionInZone(zone)
    if not zone or not zone.point or not zone.radius then
        Utils.showDebugMessage("Invalid zone data for random position generation", 5, 3)
        return nil
    end
    
    local maxAttempts = 50
    local minDistance = 5 -- Minimum distance between cargo objects
    
    for attempt = 1, maxAttempts do
        -- Generate random angle and distance
        local angle = math.random() * 2 * math.pi
        local maxRadius = zone.radius * 0.8 -- Stay within 80% of zone radius for safety
        local distance = math.random() * maxRadius
        
        -- Calculate position
        local x = zone.point.x + distance * math.cos(angle)
        local z = zone.point.z + distance * math.sin(angle)
        
        local newPos = {x = x, z = z}
        
        -- Check for conflicts with existing cargo
        local validPosition = true
        for _, existingCargo in pairs(MissionState.spawnedCargo) do
            if existingCargo.position then
                local distance = Utils.getDistance(newPos, existingCargo.position)
                if distance < minDistance then
                    validPosition = false
                    break
                end
            end
        end
        
        if validPosition then
            Utils.showDebugMessage("Found valid position after " .. attempt .. " attempts: (" .. x .. ", " .. z .. ")", 5, 3)
            return newPos
        end
    end
    
    Utils.showDebugMessage("Failed to find valid position after " .. maxAttempts .. " attempts, using fallback", 5, 2)
    -- Fallback to zone center with small random offset
    return {
        x = zone.point.x + (math.random() - 0.5) * 10,
        z = zone.point.z + (math.random() - 0.5) * 10
    }
end

-- Clean up destroyed or missing cargo objects from tracking
function CargoManagement.cleanupMissingCargo()
    local initialCount = #MissionState.spawnedCargo
    local newCargoList = {}
    
    for _, cargo in pairs(MissionState.spawnedCargo) do
        -- Try to find the static object
        local staticObj = StaticObject.getByName(cargo.name)
        if staticObj and staticObj:isExist() then
            table.insert(newCargoList, cargo)
        else
            Utils.showDebugMessage("Removed missing cargo from tracking: " .. cargo.name, 5, 3)
        end
    end
    
    MissionState.spawnedCargo = newCargoList
    local removedCount = initialCount - #newCargoList
    
    if removedCount > 0 then
        Utils.showDebugMessage("Cargo cleanup: removed " .. removedCount .. " missing objects, " .. #newCargoList .. " remain", 5, 2)
    end
    
    return removedCount
end

-- Get current cargo status for reporting
function CargoManagement.getCargoStatus()
    CargoManagement.cleanupMissingCargo()
    
    local cargoCount = #MissionState.spawnedCargo
    local typeBreakdown = {}
    
    for _, cargo in pairs(MissionState.spawnedCargo) do
        local typeName = cargo.typeName or cargo.type
        typeBreakdown[typeName] = (typeBreakdown[typeName] or 0) + 1
    end
    
    return {
        totalCount = cargoCount,
        typeBreakdown = typeBreakdown,
        zone = CONFIG.ZONES.SUPPORT_AMMO_SUPPLY
    }
end

-- Manually spawn additional supply objects (for radio commands or events)
function CargoManagement.spawnAdditionalSupplies(count)
    count = count or 1
    Utils.showMessage("Spawning " .. count .. " additional supply objects...", 5)
    
    local successCount = 0
    for i = 1, count do
        if CargoManagement.spawnRandomSupplyObject() then
            successCount = successCount + 1
        end
    end
    
    Utils.showMessage("Spawned " .. successCount .. " of " .. count .. " additional supply objects", 8)
    return successCount
end

-- Discover all supply zones (truck and helicopter spawn zones)
function Utils.discoverSupplyZones()
    local truckZones = {}
    local heloZones = {}
    
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
            end
        end
    end
    
    -- Fallback: Try to get zones by name pattern
    if #truckZones == 0 and #heloZones == 0 then
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
        end
    end
    
    -- Store discovered zones in MissionState (already done above)
    
    Utils.showMessage("Discovered " .. #truckZones .. " truck spawn zones and " .. #heloZones .. " helo spawn zones", 8)
    
    -- Return the discovered zones in the expected format
    return {
        truck = truckZones,
        helo = heloZones
    }
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

-- Get count of active deployment zones for status reporting
function Utils.getActiveZoneCount()
    local activeZoneCount = 0
    
    -- Count SAM deployment zones
    for _, zoneInfo in pairs(MissionState.zones.srSamZones) do
        if zoneInfo.active then
            activeZoneCount = activeZoneCount + 1
        end
    end
    
    for _, zoneInfo in pairs(MissionState.zones.lrSamZones) do
        if zoneInfo.active then
            activeZoneCount = activeZoneCount + 1
        end
    end
    
    return activeZoneCount
end

-- =====================================================================================
-- SCRIPT INITIALIZATION
-- =====================================================================================

-- MAIN INITIALIZATION FUNCTION
function SAM_Resupply_Init()
    Utils.showMessage("SAM Auto Resupply v0.3.24 Initializing...", 10)
    
    -- Discover SAM deployment zones first  
    Utils.showMessage("Starting SAM zone discovery...", 8)
    if not ZoneDiscovery.discoverDeploymentZones() then
        Utils.showMessage("ERROR: Failed to discover SAM deployment zones! Check zone naming.", 10)
        return
    end
    Utils.showMessage("SAM zone discovery completed successfully!", 8)
    
    -- Initialize cargo management system
    CargoManagement.initialize()
    
    -- Discover all supply zones
    local allZones = Utils.discoverSupplyZones()
    MissionState.zones.truckSpawnZones = allZones.truck
    MissionState.zones.heloSpawnZones = allZones.helo
    
    if #MissionState.zones.truckSpawnZones > 0 then
        Utils.showMessage("Found " .. #MissionState.zones.truckSpawnZones .. " truck supply zones", 5)
    end
    
    if #MissionState.zones.heloSpawnZones > 0 then
        Utils.showMessage("Found " .. #MissionState.zones.heloSpawnZones .. " helicopter supply zones", 5)
    end
    
    -- Find and validate ammo supply zone
    local ammoZone = trigger.misc.getZone(CONFIG.ZONES.SUPPORT_AMMO_SUPPLY)
    if ammoZone then
        MissionState.zones.ammoSupplyZone = ammoZone
        Utils.showMessage("Found ammo supply zone: " .. CONFIG.ZONES.SUPPORT_AMMO_SUPPLY, 5)
        
        -- Spawn initial supply objects
        CargoManagement.spawnInitialSupplyObjects()
    else
        Utils.showMessage("WARNING: Ammo supply zone " .. CONFIG.ZONES.SUPPORT_AMMO_SUPPLY .. " not found!", 10)
    end
    
    -- Zone states are already initialized in ZoneDiscovery.discoverDeploymentZones()
    
    -- Start periodic monitoring
    ZoneMonitoring.startMultiZoneMonitoring()
    
    -- Add radio menu if EventHandler is available
    if EventHandler then
        EventHandler.addRadioMenu()
    end
    
    Utils.showMessage("SAM Auto Resupply System Ready! Monitoring " .. 
                     Utils.getActiveZoneCount() .. " zones with " .. 
                     CONFIG.STARTING_SUPPLY_OBJECTS .. " supply objects spawned.", 10)
end

-- Schedule initialization
timer.scheduleFunction(SAM_Resupply_Init, nil, timer.getTime() + 1)

