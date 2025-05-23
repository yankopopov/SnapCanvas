-----------------------------------------------------------------------
-- loader.lua  –  runtime helper for SnapCanvas exports
-----------------------------------------------------------------------

local M = {}

-- these will be filled after load()
M.all      = {}   --  ordered array  →  sprites[1], sprites[2] …
M.byName   = {}   --  name → sprite
M.byHandle = {}   --  displayObject → original data table (optional)

--- Load sprites from a SnapCanvas image_data.lua file
-- @param sceneGroup (optional) display group to insert into (default: current stage)
-- @param dataFile   (optional) module path (default: "image_data")
function M.load(sceneGroup, dataFile)
    sceneGroup = sceneGroup or display.getCurrentStage()
    dataFile   = dataFile   or "image_data"

    local ok, imageData = pcall(require, dataFile)
    assert(ok and type(imageData)=="table", "Could not require '"..dataFile.."'")

    -- Sort entries on saved hierarchyIndex so bottom-most draw first
    table.sort(imageData, function(a,b) return a.hierarchyIndex < b.hierarchyIndex end)

    for _, entry in ipairs(imageData) do
        local sprite = display.newImage(sceneGroup, entry.path)
        if not sprite then
            print("WARNING: missing file", entry.path)
        else
            ------------------------------------------------------------
            --  Apply saved transform
            ------------------------------------------------------------
            sprite.x       = entry.x
            sprite.y       = entry.y
            sprite.width   = entry.width
            sprite.height  = entry.height
            sprite.rotation= entry.rotation
            sprite.alpha   = entry.alpha
            sprite.xScale  = entry.xScale
            sprite.yScale  = entry.yScale

            -- bookkeeping
            M.all[#M.all+1]    = sprite
            M.byName[entry.name]= sprite
            M.byHandle[sprite] = entry
        end
    end
end

-----------------------------------------------------------------------
-- Convenience helpers
-----------------------------------------------------------------------

--- Get sprite by name (string) or index (number)
function M.get(ref)
    if type(ref)=="string" then
        return M.byName[ref]
    elseif type(ref)=="number" then
        return M.all[ref]
    end
end

--- Iterate all sprites in draw order
function M.each()
    local i = 0
    return function()
        i = i + 1
        return M.all[i]
    end
end

return M