-- undo.lua
local undoStack, redoStack = {}, {}
local maxHistory = 20

local function push(cmd)
    undoStack[#undoStack+1] = cmd
    if #undoStack > maxHistory then table.remove(undoStack, 1) end
    redoStack = {}            -- clear forward history
end

local function apply(image, data)
    if not image then return end   -- image may have been deleted
    for k,v in pairs(data) do image[k] = v end
end

local function _applyMulti(list, key)
    for _,e in ipairs(list) do apply(e.img, e[key]) end
end

local function undo()
    local cmd = table.remove(undoStack); if not cmd then return end
    if cmd.imgs      then _applyMulti(cmd.imgs, "old")
    elseif cmd.old   then apply(cmd.img, cmd.old)
    else cmd.img[cmd.prop] = cmd.old end

    if removeHandles then removeHandles() end
    if updateHandles then updateHandles() end
    if updateParameters then updateParameters() end
    redoStack[#redoStack+1] = cmd
end

local function redo()
    local cmd = table.remove(redoStack); if not cmd then return end
    if cmd.imgs      then _applyMulti(cmd.imgs, "new")
    elseif cmd.new   then apply(cmd.img, cmd.new)
    else cmd.img[cmd.prop] = cmd.new end

    if removeHandles then removeHandles() end
    if updateHandles then updateHandles() end
    if updateParameters then updateParameters() end
    undoStack[#undoStack+1] = cmd
end

-- Export a table instead of polluting global scope
return {
    push = push,
    undo = undo,
    redo = redo,
}