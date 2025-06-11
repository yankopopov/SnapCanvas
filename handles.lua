local M             = {}
local Service       = require("service")
local Undo          = require("undo")
local GUI           = require("GUIcontrolFunctions")
local globals       = require("globals")
local tt            = transition.to

-- Safe accessor for the global selection helper
local function getSel()
    if _G.getSelectedImagesList then
        local t = _G.getSelectedImagesList()
        if #t > 0 then return t end
    end
    -- Fallback: single selection stored in global
    if _G.selectedImage then
        return { _G.selectedImage }
    end
    return {}
end

local resizeHandles      = _G.resizeHandles      or {}
local rotateHandles      = _G.rotateHandles      or {}
local groupHandleRect    = _G.groupHandleRect    -- may be nil
local groupResizeHandles = _G.groupResizeHandles or {}

-- Safe getter for the current zoom factor (defaults to 1)
local function getZoom() return _G.zoomFactor or 1 end

-- Call the real bringOutlinesToFront (defined later in main.lua) if present
local function bringToFront()
    if _G.bringOutlinesToFront then
        _G.bringOutlinesToFront()
    end
end

-- Function to create handles for resizing, rotating, or quadrilateral distortion
local function createHandle(x, y)
    local handle
    if selectedButton == "rotate" then
        handle = display.newCircle(x, y, 5)
        handle:setFillColor(1, 0, 0, 0.7)
    else
        handle = display.newRect(x, y, 10, 10)
        handle:setFillColor(0, 1, 0, 0.7)
    end
    GUI.handleGroup:insert(handle)
    handle:toFront()
    return handle
end

removeHandles = function()
    for _, handle in pairs(resizeHandles) do
        handle:removeSelf()
    end
    resizeHandles = {}
    for _, handle in pairs(rotateHandles) do
        handle:removeSelf()
    end
    rotateHandles = {}
    if groupHandleRect then
        groupHandleRect:removeSelf()
        groupHandleRect = nil
    end
    if groupResizeHandles then
        for _, h in pairs(groupResizeHandles) do
            h:removeSelf()
        end
    end
    groupResizeHandles = {}
    -- Keep global references in sync
    _G.groupHandleRect    = nil
    _G.groupResizeHandles = {}
end

local HandleScale = 1.8

local function handleTouch(event)
    local handle = event.target
    if event.phase == "began" then
        if handle.isGroupResize and event.phase == "began" then
            display.getCurrentStage():setFocus(handle, event.id)
            handle.isFocus = true
            -- Record the pointer’s initial position for proper deltas
            handle.startX = event.x
            handle.startY = event.y
            return true
        end
        display.getCurrentStage():setFocus(handle, event.id)
        handle.isFocus = true
        handle.startX, handle.startY = event.x, event.y
        handle.startWidth, handle.startHeight = selectedImage.width, selectedImage.height
        handle.startImageX, handle.startImageY = selectedImage.x, selectedImage.y
        handle.startRotation = selectedImage.rotation
        transition.cancel("scaleHandles")
        tt(handle, {xScale = HandleScale, yScale = HandleScale, time = 150, tag = "scaleHandles"})
    elseif handle.isFocus then
        if event.phase == "moved" then
            if handle.isGroupResize and handle.isFocus and event.phase == "moved" then
                local h        = handle
                -- Convert event.x/y (screen) into world coords (accounting for pan & zoom)
                local z      = getZoom()
                local worldX = (event.x - GUI.imageGroup.x) / z
                local worldY = (event.y - GUI.imageGroup.y) / z
                local b        = h.boxStart
                local origMinX = b.minX
                local origMinY = b.minY
                local origMaxX = b.maxX
                local origMaxY = b.maxY
                local origW    = origMaxX - origMinX
                local origH    = origMaxY - origMinY

                -- Determine new box corners based on dragged handle (in world space)
                local newMinX, newMinY = origMinX, origMinY
                local newMaxX, newMaxY = origMaxX, origMaxY
                if h.corner == "topLeft" then
                    newMinX, newMinY = worldX, worldY
                elseif h.corner == "topRight" then
                    newMaxX, newMinY = worldX, worldY
                elseif h.corner == "bottomLeft" then
                    newMinX, newMaxY = worldX, worldY
                elseif h.corner == "bottomRight" then
                    newMaxX, newMaxY = worldX, worldY
                end

                -- Compute scales for width/height
                local newW = newMaxX - newMinX
                local newH = newMaxY - newMinY
                local scaleX = newW / origW
                local scaleY = newH / origH
                -- Uniform scale if Shift held
                if globals.shiftPressed then scaleY = scaleX end

                -- Scale each image size and reposition relative to box
                for _, img in ipairs(h.selImages) do
                    -- new dimensions
                    img.width  = img.groupOrigW * scaleX
                    img.height = img.groupOrigH * scaleY
                    -- normalized positions within original box
                    local u = (img.groupOrigX - origMinX) / origW
                    local v = (img.groupOrigY - origMinY) / origH
                    -- new positions inside new box
                    img.x = newMinX + u * newW
                    img.y = newMinY + v * newH
                    if img.outline then
                        img.outline.x, img.outline.y = img.x, img.y
                    end
                end

                -- Update the bounding-box rectangle (in world space)
                if groupHandleRect then
                    groupHandleRect.width  = newW
                    groupHandleRect.height = newH
                    groupHandleRect.x = newMinX + newW * 0.5
                    groupHandleRect.y = newMinY + newH * 0.5
                end

                -- Reposition corner handles to new corners (in world space)
                for corner, hdl in pairs(groupResizeHandles) do
                    if corner == "topLeft" then
                        hdl.x, hdl.y = newMinX, newMinY
                    elseif corner == "topRight" then
                        hdl.x, hdl.y = newMaxX, newMinY
                    elseif corner == "bottomLeft" then
                        hdl.x, hdl.y = newMinX, newMaxY
                    elseif corner == "bottomRight" then
                        hdl.x, hdl.y = newMaxX, newMaxY
                    end
                end

                -- Update the properties panel in real time
                updateParameters()

                return true
            end
            local z  = getZoom()
            local dx = (event.x - handle.startX) / z
            local dy = (event.y - handle.startY) / z
            if selectedButton == "resize" then
                local proportion = handle.startWidth / handle.startHeight

                Service.updateImageSizeAndPosition(
                    selectedImage,
                    resizeHandles,
                    handle,
                    dx,
                    dy,
                    proportion,
                    globals.shiftPressed,
                    controlPressed,
                    z
                )
                updateHandles()
                updateParameters()
            elseif selectedButton == "rotate" then
                local imageCenterX, imageCenterY = selectedImage:localToContent(0, 0)
                local startAngle = math.atan2(handle.startY - imageCenterY, handle.startX - imageCenterX)
                local currentAngle = math.atan2(event.y - imageCenterY, event.x - imageCenterX)
                local angleDelta = math.deg(currentAngle - startAngle)
                selectedImage.rotation = handle.startRotation + angleDelta
                updateHandles()
                updateParameters()
            end
        elseif event.phase == "ended" or event.phase == "cancelled" then
            if handle.isGroupResize then
                -- End the drag focus
                handle.isFocus = false
                display.getCurrentStage():setFocus(handle, nil)

                -- Compute the box’s new extents from the red rect
                local cx, cy      = groupHandleRect.x, groupHandleRect.y
                local halfW, halfH = groupHandleRect.width/2, groupHandleRect.height/2
                local newMinX, newMinY = cx - halfW, cy - halfH
                local newMaxX, newMaxY = cx + halfW, cy + halfH

                -- Record group resize undo/redo
                local resizeCmds = {}
                for _, img in ipairs(handle.selImages) do
                    table.insert(resizeCmds, {
                        img = img,
                        old = { x = img.groupOrigX, y = img.groupOrigY, width = img.groupOrigW, height = img.groupOrigH },
                        new = { x = img.x,       y = img.y,       width = img.width,       height = img.height }
                    })
                end
                Undo.push({ imgs = resizeCmds })

                -- Commit each image’s new “original” size and position
                for _, img in ipairs(handle.selImages) do
                    img.groupOrigX, img.groupOrigY = img.x, img.y
                    img.groupOrigW, img.groupOrigH = img.width, img.height
                end

                -- Update this handle’s stored boxStart for the next drag
                handle.startX, handle.startY = handle.x, handle.y
                handle.boxStart = {
                    minX = newMinX, minY = newMinY,
                    maxX = newMaxX, maxY = newMaxY
                }

                -- Redraw box & handles after group resize ends
                showHandles()
                updateHandles()
                return true
            end
            display.getCurrentStage():setFocus(handle, nil)
            handle.isFocus = false
            --handle:scale(1 / HandleScale, 1 / HandleScale) -- Scale back the handle to its original size
            transition.cancel("scaleHandles")
            tt(handle, {xScale = 1, yScale = 1, time = 150, tag = "scaleHandles"})
            -- Redraw box & handles after resize/rotate ends
            showHandles()
            updateHandles()
            -- Record resize/rotate undo/redo
            if not handle.isGroupResize then
                if selectedButton == "resize" then
                    Undo.push({
                        img = selectedImage,
                        old = {
                            width  = handle.startWidth,
                            height = handle.startHeight,
                            x      = handle.startImageX,
                            y      = handle.startImageY
                        },
                        new = {
                            width  = selectedImage.width,
                            height = selectedImage.height,
                            x      = selectedImage.x,
                            y      = selectedImage.y
                        }
                    })
                elseif selectedButton == "rotate" then
                    Undo.push({
                        img = selectedImage,
                        prop = "rotation",
                        old  = handle.startRotation,
                        new  = selectedImage.rotation
                    })
                end
            end
        end
    end
    return true
end
-- Function to update handle positions based on the image size, position, and rotation
updateHandles = function()
    -- Skip repositioning handles during multi-select; showHandles manages group handles
    local sel = getSel()
    if #sel > 1 then return end
    local img = sel[1]
    -- If no active handle objects exist (e.g. after undo cleared them), rebuild all handles
    if selectedButton == "resize" then
        if not (resizeHandles.topLeft and resizeHandles.topLeft.removeSelf) then
            showHandles(); return
        end
    elseif selectedButton == "rotate" then
        if not (rotateHandles.topLeft and rotateHandles.topLeft.removeSelf) then
            showHandles(); return
        end
    end
    if img then
        -- Canvas pan offset (imageGroup is translated during panning)
        local offsetX = (GUI.imageGroup and GUI.imageGroup.x or 0)
        local offsetY = (GUI.imageGroup and GUI.imageGroup.y or 0)
        local halfWidth  = img.width  / 2
        local halfHeight = img.height / 2
        local cosRot = math.cos(math.rad(img.rotation))
        local sinRot = math.sin(math.rad(img.rotation))

        local function getRotatedPosition(x, y)
            return {
                x = offsetX + img.x + (x * cosRot - y * sinRot),
                y = offsetY + img.y + (x * sinRot + y * cosRot)
            }
        end

        if selectedButton == "resize" then
            local topLeft     = getRotatedPosition(-halfWidth, -halfHeight)
            local topRight    = getRotatedPosition( halfWidth, -halfHeight)
            local bottomLeft  = getRotatedPosition(-halfWidth,  halfHeight)
            local bottomRight = getRotatedPosition( halfWidth,  halfHeight)

            resizeHandles.topLeft.x,     resizeHandles.topLeft.y     = topLeft.x,     topLeft.y
            resizeHandles.topRight.x,    resizeHandles.topRight.y    = topRight.x,    topRight.y
            resizeHandles.bottomLeft.x,  resizeHandles.bottomLeft.y  = bottomLeft.x,  bottomLeft.y
            resizeHandles.bottomRight.x, resizeHandles.bottomRight.y = bottomRight.x, bottomRight.y

        elseif selectedButton == "rotate" then
            local topLeft     = getRotatedPosition(-halfWidth, -halfHeight)
            local topRight    = getRotatedPosition( halfWidth, -halfHeight)
            local bottomLeft  = getRotatedPosition(-halfWidth,  halfHeight)
            local bottomRight = getRotatedPosition( halfWidth,  halfHeight)

            rotateHandles.topLeft.x,     rotateHandles.topLeft.y     = topLeft.x,     topLeft.y
            rotateHandles.topRight.x,    rotateHandles.topRight.y    = topRight.x,    topRight.y
            rotateHandles.bottomLeft.x,  rotateHandles.bottomLeft.y  = bottomLeft.x,  bottomLeft.y
            rotateHandles.bottomRight.x, rotateHandles.bottomRight.y = bottomRight.x, bottomRight.y
        end
    end
end


-- Exposed: draw red bounding box & corner handles
showHandles = function()
    -- Make absolutely sure GUI.handleGroup exists and is on‑stage
    if not GUI.handleGroup or not GUI.handleGroup.removeSelf then
        GUI.handleGroup = display.newGroup()
    end
    -- Ensure handleGroup is in the display hierarchy *and* above everything else
    if not GUI.handleGroup.parent then
        display.getCurrentStage():insert(GUI.handleGroup)
    end
    GUI.handleGroup:toFront()   -- always bring to the very front
    -- Clear existing handles/outlines (global to avoid local nil)
    if _G.removeHandles then _G.removeHandles() end

    local sel = getSel()
    -- Fallback: if tool not initialised, default to resize
    if selectedButton == nil then
        selectedButton = "resize"
    end
    if #sel > 1 then
        -- ------------------------------------------------------------------
        -- Compute the axis‑aligned bounding box *in screen coordinates*
        -- by transforming each sprite corner via localToContent().
        -- This is immune to any pan/zoom transforms on GUI.imageGroup.
        -- ------------------------------------------------------------------
        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        for _, img in ipairs(sel) do
            local tlx, tly = img:localToContent(-img.width * 0.5, -img.height * 0.5)
            local brx, bry = img:localToContent( img.width * 0.5,  img.height * 0.5)
            minX = math.min(minX, tlx, brx)
            minY = math.min(minY, tly, bry)
            maxX = math.max(maxX, tlx, brx)
            maxY = math.max(maxY, tly, bry)
        end
        local boxW = maxX - minX
        local boxH = maxY - minY
        local centerX = (minX + maxX) / 2
        local centerY = (minY + maxY) / 2

        -- Draw transparent rectangle with stroke in screen space
        groupHandleRect = display.newRect(GUI.handleGroup, centerX, centerY, boxW, boxH)
        groupHandleRect:setFillColor(0,0,0,0)
        groupHandleRect.strokeWidth = 3   -- slightly thicker for clarity
        groupHandleRect:setStrokeColor(1,0,0)
        _G.groupHandleRect = groupHandleRect

        -- Store original for each image
        for _, img in ipairs(sel) do
            img.groupOrigX, img.groupOrigY = img.x, img.y
            img.groupOrigW, img.groupOrigH = img.width, img.height
        end

        -- Create corner handles for group-resize in screen space
        groupResizeHandles = {}
        local corners = {
            { x = minX, y = minY, corner = "topLeft" },
            { x = maxX, y = minY, corner = "topRight" },
            { x = minX, y = maxY, corner = "bottomLeft" },
            { x = maxX, y = maxY, corner = "bottomRight" },
        }
        for _, c in ipairs(corners) do
            local h = createHandle(c.x, c.y)
            h.isGroupResize = true
            h.corner = c.corner
            h.startX, h.startY = h.x, h.y
            h.boxStart = { minX = minX, minY = minY, maxX = maxX, maxY = maxY }
            h.selImages = sel
            h:addEventListener("touch", handleTouch)
            groupResizeHandles[c.corner] = h
        end
        _G.groupResizeHandles = groupResizeHandles

    else
        -- Single-image mode: draw handles in world space
        local img = getSel()[1]
        if img then
            local halfW, halfH = img.width/2, img.height/2
            local offsetX = (GUI.imageGroup and GUI.imageGroup.x or 0)
            local offsetY = (GUI.imageGroup and GUI.imageGroup.y or 0)

            if selectedButton == "resize" then
                -- Create resize handles at the four corners
                resizeHandles = {
                    topLeft     = createHandle(offsetX + img.x - halfW, offsetY + img.y - halfH),
                    topRight    = createHandle(offsetX + img.x + halfW, offsetY + img.y - halfH),
                    bottomLeft  = createHandle(offsetX + img.x - halfW, offsetY + img.y + halfH),
                    bottomRight = createHandle(offsetX + img.x + halfW, offsetY + img.y + halfH),
                }
                for _, h in pairs(resizeHandles) do
                    h:addEventListener("touch", handleTouch)
                end
                _G.resizeHandles = resizeHandles

            elseif selectedButton == "rotate" then
                -- Create rotate handles at the four corners
                rotateHandles = {
                    topLeft     = createHandle(offsetX + img.x - halfW, offsetY + img.y - halfH),
                    topRight    = createHandle(offsetX + img.x + halfW, offsetY + img.y - halfH),
                    bottomLeft  = createHandle(offsetX + img.x - halfW, offsetY + img.y + halfH),
                    bottomRight = createHandle(offsetX + img.x + halfW, offsetY + img.y + halfH),
                }
                for _, h in pairs(rotateHandles) do
                    h:addEventListener("touch", handleTouch)
                end
                _G.rotateHandles = rotateHandles
            end
        end
    end

    -- Finally, ensure outlines stay on top
    bringToFront()
end
-- Function to add touch listeners to handles
local function addHandleListeners()
    for _, handle in pairs(handles) do
        handle:addEventListener("touch", handleTouch)
    end
end
local function updateHandlesForm()
    if selectedImage then
        removeHandles()
        showHandles()
    end
end

-- Expose so legacy calls from main.lua (selectResize/selectRotate) still work
_G.updateHandlesForm = updateHandlesForm
-- Expose helpers to the global namespace for legacy calls
_G.updateHandles  = updateHandles
_G.showHandles    = showHandles
_G.removeHandles  = removeHandles

function M.clear()   removeHandles() end
function M.show(sel, mode) showHandles(sel, mode) end
function M.update(sel) updateHandles(sel) end

return M