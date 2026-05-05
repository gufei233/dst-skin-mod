_G = GLOBAL
require = _G.require
GLOBAL.setmetatable(env,{__index=function(t,k) return GLOBAL.rawget(GLOBAL,k) end})

print("Is MiM enabled?: ", is_mim_enabled, " What is the server game mode?: ", _G.TheNet:GetServerGameMode())
if is_mim_enabled and _G.TheNet:GetServerGameMode() ~= "" then return end

Assets = {}

local DEFAULT_PREFIX = "custom_"

function string:start_with_that_prefix()
    return self:sub(1, #DEFAULT_PREFIX) == DEFAULT_PREFIX
end

function string:trip_that_prefix()
    return self:sub(#DEFAULT_PREFIX + 1)
end
modimport "scripts/prefabsPostInit/dragonfly_chest"
modimport "scripts/prefabsPostInit/treasurechest"



modimport("skinloader/skinloader")
modimport("localskinmain")

initializeModMain()

