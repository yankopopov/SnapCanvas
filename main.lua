-----------------------------------------------------------------------------------------
-- main.lua
-----------------------------------------------------------------------------------------
_W = display.contentWidth
_H = display.contentHeight
----------------------------------------------------------------
local json = require("json")
local save = require("saveexport")
local myPlugin = require("plugin.tinyfiledialogs")
local Service = require("service")
local Handles = require("handles")
local GUI = require("GUIcontrolFunctions")
local Checkbox      = require("Checkbox")
local Undo          = require("undo")
local globals       = require("globals")

--------------------------------------
-- Declarations and predeclarations ---
--------------------------------------
local tt = transition.to
-- ──────────────────────────────────────────────────────────────
-- Helpers: refresh handles • bounding box • move sprite+outline
-- ──────────────────────────────────────────────────────────────
local function refreshHandles()
    if _G.removeHandles then removeHandles() end
    if _G.showHandles   then showHandles()   end
    if _G.updateHandles then updateHandles() end
end
_G.refreshHandles = refreshHandles

local function getBoundingBox(sel)
    local minX, minY =  math.huge,  math.huge
    local maxX, maxY = -math.huge, -math.huge
    for _, img in ipairs(sel) do
        minX = math.min(minX, img.x - img.width /2)
        minY = math.min(minY, img.y - img.height/2)
        maxX = math.max(maxX, img.x + img.width /2)
        maxY = math.max(maxY, img.y + img.height/2)
    end
    local cx, cy = (minX+maxX)/2, (minY+maxY)/2
    return minX, minY, maxX, maxY, cx, cy, maxX-minX, maxY-minY
end
_G.getBoundingBox = getBoundingBox

local function moveSprite(img, newX, newY)
    img.x, img.y = newX, newY
    if img.outline then
        img.outline.x, img.outline.y = newX, newY
    end
end
_G.moveSprite = moveSprite
-- ──────────────────────────────────────────────────────────────

selectedButton = "resize"   -- make global so handles.lua can read it
local updateTextColors, moveImageUp, moveImageDown, deleteImage,
      ButtonRotate, ButtonResize, moveImageToTop, moveImageToBottom,
      saveWorkspace, loadWorkspace, updateImageListOrder, exportWorkspace,
      gatherImageData, clearWorkspace, imageTouch, addImageToList,
      reorderImageGroup, selectResize, selectRotate, startPanX, startPanY,
      LoadFileFunction, addPendingFile, nextStep, getSelectedImagesList,
      alignVerticalBottomGroup, alignVerticalTopGroup, alignVerticalCenterGroup,
      alignHorizontalLeftGroup, alignHorizontalRightGroup, alignHorizontalCenterGroup,
      distributeHorizontalGroup, distributeVerticalGroup, ButtonPan
selectedImage = nil       -- one global copy
_G.selectedImage = selectedImage

local images = {}

-- ------------------------------------------------------------------
_G.resizeHandles      = _G.resizeHandles      or {}
_G.rotateHandles      = _G.rotateHandles      or {}
_G.groupHandleRect    = _G.groupHandleRect    or nil
_G.groupResizeHandles = _G.groupResizeHandles or {}

-- Convenient local aliases
local resizeHandles      = _G.resizeHandles
local rotateHandles      = _G.rotateHandles
local groupHandleRect    = _G.groupHandleRect
local groupResizeHandles = _G.groupResizeHandles

-- Table that tracks the current multi‑selection
local multiSelectedImages = {}

-- Clipboard for copy/paste
local clipboard = nil

local panelDrawerOpen = true
local panelOriginalX, panelOriginalY
local scrollDrawerOpen = true
local scrollOriginalX, filesOriginalX

local imageOrder = {}
local isPanning = false
local panelVisible = true
local createdImages = 0
local canvasZoomSize = 1
local zoomFactor = 1
-- Pending files awaiting placement
local pendingFiles = {}
local filesScrollView -- pending‑files list (green, top‑right)

-- Placement mode state
local isPlacing = false
local placingImage = nil

local mouseWasDown = false  -- state flag

local function placementTouch(event)
    if not isPlacing then return false end
    if event.phase == "began" or event.phase == "moved" then
        -- Convert global coordinates to imageGroup-local (accounting for pan)
        local localX = event.x - (GUI.imageGroup and GUI.imageGroup.x or 0)
        local localY = event.y - (GUI.imageGroup and GUI.imageGroup.y or 0)
        placingImage.x, placingImage.y = localX, localY
    elseif event.phase == "ended" then
        -- finalize placement
        placingImage.alpha = 1
        -- Now the new image should respond to touch
        placingImage:addEventListener("touch", imageTouch)
        table.insert(images, placingImage)
        addImageToList(placingImage.ID)
        initializeImageOrder()
        selectedImage = placingImage
        _G.selectedImage = selectedImage

        isPlacing = false
        placingImage = nil
        placingImage:removeEventListener("touch", placementTouch)
        Runtime:removeEventListener("mouse", placementMouse)
        refreshHandles(); updateTextColors()
    end
    return true
end


local function placementMouse(event)
    if not isPlacing then return false end
    -- Always move ghost under cursor (convert to imageGroup‑local)
    local localX = event.x - (GUI.imageGroup and GUI.imageGroup.x or 0)
    local localY = event.y - (GUI.imageGroup and GUI.imageGroup.y or 0)
    placingImage.x, placingImage.y = localX, localY

    if event.name == "mouse" then
        -- Track button state
        if event.isPrimaryButtonDown then
            mouseWasDown = true
        elseif mouseWasDown and not event.isPrimaryButtonDown then
            -- Button was released → finalize placement
            mouseWasDown = false
            placingImage.alpha = 1
            placingImage:addEventListener("touch", imageTouch)
            table.insert(images, placingImage)
            addImageToList(placingImage.ID)
            initializeImageOrder()

            -- Select it
            selectedImage = placingImage
            _G.selectedImage = selectedImage

            multiSelectedImages = {}
            isPlacing = false
            placingImage = nil

            Runtime:removeEventListener("mouse", placementMouse)

            if _G.removeHandles then removeHandles() end
            if _G.showHandles then showHandles() end
            if _G.updateHandles then updateHandles() end
            if _G.updateTextColors then updateTextColors() end
        end
    end
    return false
end

-- Function to get the currently selected image
local function getSelectedImage()
    return selectedImage
end

local checkboxFlipX = Checkbox:new{ id = "checkboxFlipX", x = flipXText.x + 19, y = flipXText.y, parentGroup = GUI.propertiesGroup, getSelectedImage = getSelectedImage }
local checkboxFlipY = Checkbox:new{ id = "checkboxFlipY", x = flipYText.x + 19, y = flipYText.y, parentGroup = GUI.propertiesGroup, getSelectedImage = getSelectedImage }

-- Undo/Redo for flips (guarded)
if checkboxFlipX and checkboxFlipX.addEventListener then
    checkboxFlipX:addEventListener("tap", function()
        if selectedImage then
            local oldValue = selectedImage.xScale
            local newValue = -oldValue
            selectedImage.xScale = newValue
            Undo.push({ img = selectedImage, prop = "xScale", old = oldValue, new = newValue })
            updateHandles(); updateParameters()
        end
        return true
    end)
end

if checkboxFlipY and checkboxFlipY.addEventListener then
    checkboxFlipY:addEventListener("tap", function()
        if selectedImage then
            local oldValue = selectedImage.yScale
            local newValue = -oldValue
            selectedImage.yScale = newValue
            Undo.push({ img = selectedImage, prop = "yScale", old = oldValue, new = newValue })
            updateHandles(); updateParameters()
        end
        return true
    end)
end

local PropertiesXinput = GUI.createTextField(PropertiesXtext.x + 60, PropertiesXtext.y, 100, 15, GUI.propertiesGroup)
local PropertiesYinput = GUI.createTextField(PropertiesYtext.x + 60, PropertiesYtext.y, 100, 15, GUI.propertiesGroup)
local PropertiesScaleXinput = GUI.createTextField(PropertiesScaleXtext.x + 60, PropertiesScaleXtext.y, 100, 15, GUI.propertiesGroup)
local PropertiesScaleYinput = GUI.createTextField(PropertiesScaleYtext.x + 60, PropertiesScaleYtext.y, 100, 15, GUI.propertiesGroup)
local PropertiesAlphainput = GUI.createTextField(PropertiesOpacitytext.x + 60, PropertiesOpacitytext.y, 100, 15, GUI.propertiesGroup)
local PropertiesRotationinput = GUI.createTextField(PropertiesRotationtext.x + 60, PropertiesRotationtext.y, 100, 15, GUI.propertiesGroup)

-- Flag to prevent recursive slider updates
local ignoreSlider = false
local function SliderChanged(value)
    if ignoreSlider or not selectedImage then return end
    -- Record alpha undo/redo
    local oldValue = selectedImage.alpha
    selectedImage.alpha = value
    PropertiesAlphainput.text = string.format("%.2f", value)
    Undo.push({ img = selectedImage, prop = "alpha", old = oldValue, new = value })
    updateParameters()
end

local SliderOptions = {
    width = 95,
    height = 3,
    thumbRadius = 6,
    minValue = 0,
    maxValue = 1,
    startValue = 1,
    onChange = function(value)
        SliderChanged(value)
    end
}
local OpacitySlider = GUI.createSlider(SliderOptions)
OpacitySlider.x = PropertiesOpacitytext.x + 60
OpacitySlider.y = PropertiesOpacitytext.y + 20

local OpacityHighImage = display.newImage(GUI.propertiesGroup, "GFX/opacityHigh.png")
OpacityHighImage.x = OpacitySlider.x + OpacitySlider.width - 40
OpacityHighImage.y = OpacitySlider.y
OpacityHighImage.xScale = 0.2
OpacityHighImage.yScale = 0.2
local OpacityLowImage = display.newImage(GUI.propertiesGroup, "GFX/opacityLow.png")
OpacityLowImage.x = OpacitySlider.x - 60
OpacityLowImage.y = OpacitySlider.y
OpacityLowImage.xScale = 0.2
OpacityLowImage.yScale = 0.2

GUI.propertiesGroup:insert(OpacitySlider)
GUI.propertiesGroup:insert(PropertiesXinput)
GUI.propertiesGroup:insert(PropertiesYinput)
GUI.propertiesGroup:insert(PropertiesScaleXinput)
GUI.propertiesGroup:insert(PropertiesScaleYinput)
GUI.propertiesGroup:insert(PropertiesAlphainput)
GUI.propertiesGroup:insert(PropertiesRotationinput)

-- Generic Input Handler Function
local function handleInput(event, property, min, max, callback)
    if event.phase == "ended" or event.phase == "submitted" then
        local value = tonumber(event.target.text)
        if value then
            if min and max then
                value = math.max(min, math.min(max, value)) -- Clamp the value between min and max
            end

            -- Determine selection list
            local sel = getSelectedImagesList()
            if #sel > 1 then
                -- Multi-selection edits
                -- Compute bounding box
                local minX, minY = math.huge, math.huge
                local maxX, maxY = -math.huge, -math.huge
                for _, img in ipairs(sel) do
                    minX = math.min(minX, img.groupOrigX or img.x - img.width/2)
                    minY = math.min(minY, img.groupOrigY or img.y - img.height/2)
                    maxX = math.max(maxX, img.groupOrigX or img.x + img.width/2)
                    maxY = math.max(maxY, img.groupOrigY or img.y + img.height/2)
                end
                local centerX = (minX + maxX)/2
                local centerY = (minY + maxY)/2
                local boxW = maxX - minX
                local boxH = maxY - minY

                -- Apply property change
                if property == "x" then
                    local dx = value - centerX
                    for _, img in ipairs(sel) do img.x = img.x + dx end
                elseif property == "y" then
                    local dy = value - centerY
                    for _, img in ipairs(sel) do img.y = img.y + dy end
                elseif property == "width" or property == "height" then
                    local newW = (property=="width" ) and value or boxW
                    local newH = (property=="height") and value or boxH
                    local scaleX = newW / boxW
                    local scaleY = newH / boxH
                    -- Uniform scale if Shift pressed
                    if globals.shiftPressed then scaleY = scaleX end
                    for _, img in ipairs(sel) do
                        -- scale size
                        img.width  = img.groupOrigW * scaleX
                        img.height = img.groupOrigH * scaleY
                        -- reposition proportionally within box
                        local u = (img.groupOrigX - centerX) / (boxW/2)
                        local v = (img.groupOrigY - centerY) / (boxH/2)
                        img.x = centerX + u*(newW/2)
                        img.y = centerY + v*(newH/2)
                    end
                end

                -- Refresh UI
                updateHandles()
                showHandles()
                updateTextColors()
                return
            end
            if selectedImage then
                local oldValue = selectedImage[property]
                selectedImage[property] = value
                if callback then
                    callback(value)
                end
                updateHandles()
                Undo.push({ img = selectedImage, prop = property, old = oldValue, new = value })
            end
        end
    end
end

-- Add Event Listeners with Inline Functions
PropertiesAlphainput:addEventListener("userInput", function(event)
    handleInput(event, "alpha", 0, 1, function(value) OpacitySlider:setValue(value) end)
end)
PropertiesXinput:addEventListener("userInput", function(event)
    handleInput(event, "x")
end)
PropertiesYinput:addEventListener("userInput", function(event)
    handleInput(event, "y")
end)
PropertiesScaleXinput:addEventListener("userInput", function(event)
    handleInput(event, "width")
end)
PropertiesScaleYinput:addEventListener("userInput", function(event)
    handleInput(event, "height")
end)
PropertiesRotationinput:addEventListener("userInput", function(event)
    handleInput(event, "rotation")
end)

local function updateParameters()
    -- If nothing is selected, skip parameter update
    if not selectedImage and next(multiSelectedImages) == nil then
        return
    end
    if panelVisible == false then
        -- existing show animation code...
        GUI.PropertiesPanel.xScale = 0.8
        GUI.PropertiesPanel.yScale = 0.8
        tt(GUI.PropertiesPanel, {xScale = 1, yScale = 1, time = 80, transition = easing.inOutBack})
        tt(GUI.propertiesGroup, {
            alpha = 1,
            time = 150,
            onComplete = function()
                PropertiesXinput.isVisible = true
                PropertiesYinput.isVisible = true
                PropertiesScaleXinput.isVisible = true
                PropertiesScaleYinput.isVisible = true
                PropertiesAlphainput.isVisible = true
                PropertiesRotationinput.isVisible = true
            end
        })
    end
    panelVisible = true
    -- Make sure the panel background and group are visible (for multi-select)
    GUI.PropertiesPanel.alpha = 1
    GUI.propertiesGroup.alpha    = 1

    -- Determine selection list
    local sel = getSelectedImagesList()
    if #sel > 1 then
        -- Multi-selection: show bounding-box parameters
        -- Compute bounding box
        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        for _, img in ipairs(sel) do
            minX = math.min(minX, img.x - img.width/2)
            minY = math.min(minY, img.y - img.height/2)
            maxX = math.max(maxX, img.x + img.width/2)
            maxY = math.max(maxY, img.y + img.height/2)
        end
        local centerX = (minX + maxX)/2
        local centerY = (minY + maxY)/2
        local boxW = maxX - minX
        local boxH = maxY - minY

        -- Populate inputs with box values
        PropertiesXinput.text       = string.format("%.2f", centerX)
        PropertiesYinput.text       = string.format("%.2f", centerY)
        PropertiesScaleXinput.text  = string.format("%.2f", boxW)
        PropertiesScaleYinput.text  = string.format("%.2f", boxH)
        -- Dim or disable rotation/alpha fields
        PropertiesRotationinput.text = ""
        PropertiesAlphainput.text    = ""
        OpacitySlider.alpha = 0.1

        -- Show only X/Y and width/height inputs; hide rotation, alpha, and slider
        PropertiesXinput.isVisible       = true
        PropertiesYinput.isVisible       = true
        PropertiesScaleXinput.isVisible  = true
        PropertiesScaleYinput.isVisible  = true
        PropertiesRotationinput.isVisible = false
        PropertiesAlphainput.isVisible    = false
        OpacitySlider.isVisible           = false
    else
        -- Single selection: original behavior
        local img = getSelectedImagesList()[1]
        if not img then return end
        PropertiesXinput.text       = string.format("%.2f", img.x)
        PropertiesYinput.text       = string.format("%.2f", img.y)
        PropertiesScaleXinput.text  = string.format("%.2f", img.width)
        PropertiesScaleYinput.text  = string.format("%.2f", img.height)
        PropertiesRotationinput.text = string.format("%.2f", img.rotation)
        PropertiesAlphainput.text    = string.format("%.2f", img.alpha)
        OpacitySlider.alpha = 1
        -- Update slider without triggering change listener
        ignoreSlider = true
        OpacitySlider:setValue(img.alpha)
        ignoreSlider = false

        -- Ensure all inputs and slider are visible for single selection
        PropertiesXinput.isVisible       = true
        PropertiesYinput.isVisible       = true
        PropertiesScaleXinput.isVisible  = true
        PropertiesScaleYinput.isVisible  = true
        PropertiesRotationinput.isVisible = true
        PropertiesAlphainput.isVisible    = true
        OpacitySlider.isVisible           = true
    end

    -- Flip checkbox states for single selection only
    if selectedImage then
        checkboxFlipX:setCheckedState(selectedImage.xScale == -1)
        checkboxFlipY:setCheckedState(selectedImage.yScale == -1)
    end
end

-- Expose updateParameters for undo/redo
_G.updateParameters = updateParameters
local function makePanelInvisible()
    PropertiesXinput.isVisible = false
    PropertiesRotationinput.isVisible = false
    PropertiesAlphainput.isVisible = false
    PropertiesScaleYinput.isVisible = false
    PropertiesScaleXinput.isVisible = false
    PropertiesYinput.isVisible = false
    OpacitySlider.isVisible = false
    GUI.propertiesGroup.alpha = 0
    PropertiesXinput.text = ""
    PropertiesYinput.text = ""
    PropertiesScaleXinput.text = ""
    PropertiesScaleYinput.text = ""
    PropertiesAlphainput.text = ""
    OpacitySlider.alpha = 0.1
    PropertiesRotationinput.text = ""
    checkboxFlipX:setCheckedState(false)
    checkboxFlipY:setCheckedState(false)
    panelVisible = false
end
local function clearParameters()
    if panelVisible == true then
        PropertiesXinput.isVisible = false
        PropertiesRotationinput.isVisible = false
        PropertiesAlphainput.isVisible = false
        PropertiesScaleYinput.isVisible = false
        PropertiesScaleXinput.isVisible = false
        PropertiesYinput.isVisible = false
        OpacitySlider.isVisible = false
        tt(
            GUI.propertiesGroup,
            {
                alpha = 0,
                time = 150,
                onComplete = function()
                end
            }
        )
    end
    PropertiesXinput.text = ""
    PropertiesYinput.text = ""
    PropertiesScaleXinput.text = ""
    PropertiesScaleYinput.text = ""
    PropertiesAlphainput.text = ""
    OpacitySlider.alpha = 0.1
    PropertiesRotationinput.text = ""
    panelVisible = false
end
local function onButtonExportTouch(event)
    local self = event.target
    local InitialScaleX = self.InitialScaleX
    local InitialScaleY = self.InitialScaleY
    if event.phase == "began" then
        display.getCurrentStage():setFocus(self, event.id)
        self.xScale = InitialScaleX - 0.05
        self.yScale = InitialScaleY - 0.05
        self.isFocus = true
    elseif self.isFocus then
        if event.phase == "ended" or event.phase == "cancelled" then
            self.xScale = InitialScaleX
            self.yScale = InitialScaleY
            display.getCurrentStage():setFocus(self, nil)
            self.isFocus = false
            save.exportWorkspace(gatherImageData)
        end
    end
    return true
end
local function onButtonResizeTouch(event)
    if event.phase == "ended" then
        selectResize()
    end
    return true
end
local function onButtonRotateTouch(event)
    if event.phase == "ended" then
        selectRotate()
    end
    return true
end
local function onButtonPanTouch(event)
    print("onButtonPanTouch")
    print(selectedButton)
    if event.phase == "ended" then
        if selectedButton == "pan" then
            selectedButton = nil
            GUI.setButtonTint(ButtonPan, false)
        else
            selectedButton = "pan"
            GUI.setButtonTint(ButtonPan, true)
            GUI.setButtonTint(ButtonResize, false)
            GUI.setButtonTint(ButtonRotate, false)
            -- keep existing multi-select handles visible during pan
        end
    end
    return true
end

-- Pan canvas (and handles) when in pan mode
local function canvasPanTouch(event)
    if selectedButton ~= "pan" then return false end
    if event.phase == "began" then
        startPanX, startPanY = event.x, event.y
    elseif event.phase == "moved" then
        local dx, dy = event.x - startPanX, event.y - startPanY
        GUI.imageGroup.x = GUI.imageGroup.x + dx
        GUI.imageGroup.y = GUI.imageGroup.y + dy
        startPanX, startPanY = event.x, event.y
        -- Redraw handles in new screen position
        if _G.removeHandles then removeHandles() end
        showHandles()
        updateHandles()
    end
    return true
end
Runtime:addEventListener("touch", canvasPanTouch)

local function onButtonSaveTouch(event)
    local self = event.target
    local InitialScaleX = self.InitialScaleX
    local InitialScaleY = self.InitialScaleY
    if event.phase == "began" then
        display.getCurrentStage():setFocus(self, event.id)
        self.xScale = InitialScaleX - 0.05
        self.yScale = InitialScaleY - 0.05
        self.isFocus = true
    elseif self.isFocus then
        if event.phase == "ended" or event.phase == "cancelled" then
            self.xScale = InitialScaleX
            self.yScale = InitialScaleY
            display.getCurrentStage():setFocus(self, nil)
            self.isFocus = false
            timer.performWithDelay(100, save.saveWorkspace(gatherImageData))
        end
    end
    return true
end
local function onButtonLoadTouch(event)
    local self = event.target
    local InitialScaleX = self.InitialScaleX
    local InitialScaleY = self.InitialScaleY
    if event.phase == "began" then
        display.getCurrentStage():setFocus(self, event.id)
        self.xScale = InitialScaleX - 0.05
        self.yScale = InitialScaleY - 0.05
        self.isFocus = true
    elseif self.isFocus then
        if event.phase == "ended" or event.phase == "cancelled" then
            self.xScale = InitialScaleX
            self.yScale = InitialScaleY
            display.getCurrentStage():setFocus(self, nil)
            self.isFocus = false
            timer.performWithDelay(100, loadWorkspace)
        end
    end
    return true
end
initializeImageOrder = function()
    imageOrder = {}
    for i, img in ipairs(images) do
        table.insert(imageOrder, img.ID)
    end
end
----------------------------------------------------------------
-- Alignment helpers (work with multi-select)
----------------------------------------------------------------
getSelectedImagesList = function()
    local list = {}
    for img,_ in pairs(multiSelectedImages) do list[#list+1] = img end
    if #list == 0 and selectedImage then list[1] = selectedImage end
    return list
end
_G.getSelectedImagesList = getSelectedImagesList

alignVerticalBottomGroup = function()
    local sel=getSelectedImagesList(); if #sel<2 then return end
    local target=-1e9; for _,img in ipairs(sel) do target=math.max(target,img.y+img.height/2) end
    for _,img in ipairs(sel) do img.y=target-img.height/2; if img.outline then img.outline.y=img.y end end
    updateHandles()
    -- redraw bounding box & handles after align
    showHandles()
    updateHandles()
end
alignVerticalTopGroup = function()
    local sel=getSelectedImagesList(); if #sel<2 then return end
    local target=1e9; for _,img in ipairs(sel) do target=math.min(target,img.y-img.height/2) end
    for _,img in ipairs(sel) do img.y=target+img.height/2; if img.outline then img.outline.y=img.y end end
    updateHandles()
    -- redraw bounding box & handles after align
    showHandles()
    updateHandles()
end
alignVerticalCenterGroup = function()
    local sel=getSelectedImagesList(); if #sel<2 then return end
    local sum=0; for _,img in ipairs(sel) do sum=sum+img.y end
    local target=sum/#sel
    for _,img in ipairs(sel) do img.y=target; if img.outline then img.outline.y=img.y end end
    updateHandles()
    -- redraw bounding box & handles after align
    showHandles()
    updateHandles()
end
alignHorizontalLeftGroup = function()
    local sel=getSelectedImagesList(); if #sel<2 then return end
    local target=1e9; for _,img in ipairs(sel) do target=math.min(target,img.x-img.width/2) end
    for _,img in ipairs(sel) do img.x=target+img.width/2; if img.outline then img.outline.x=img.x end end
    updateHandles()
    -- redraw bounding box & handles after align
    showHandles()
    updateHandles()
end
alignHorizontalRightGroup = function()
    local sel=getSelectedImagesList(); if #sel<2 then return end
    local target=-1e9; for _,img in ipairs(sel) do target=math.max(target,img.x+img.width/2) end
    for _,img in ipairs(sel) do img.x=target-img.width/2; if img.outline then img.outline.x=img.x end end
    updateHandles()
    -- redraw bounding box & handles after align
    showHandles()
    updateHandles()
end
alignHorizontalCenterGroup = function()
    local sel=getSelectedImagesList(); if #sel<2 then return end
    local sum=0; for _,img in ipairs(sel) do sum=sum+img.x end
    local target=sum/#sel
    for _,img in ipairs(sel) do img.x=target; if img.outline then img.outline.x=img.x end end
    updateHandles()
    -- redraw bounding box & handles after align
    showHandles()
    updateHandles()
end

----------------------------------------------------------------
-- Distribution helpers (evenly space multi-selected images)
----------------------------------------------------------------
distributeHorizontalGroup = function()
    local sel = getSelectedImagesList()
    if #sel < 3 then return end
    -- Sort by x-coordinate
    table.sort(sel, function(a,b) return a.x < b.x end)
    local leftX  = sel[1].x
    local rightX = sel[#sel].x
    local count  = #sel
    local step   = (rightX - leftX) / (count - 1)
    for i, img in ipairs(sel) do
        local tx = leftX + (i-1) * step
        img.x = tx
        if img.outline then img.outline.x = tx end
    end
    updateHandles()
    -- redraw bounding box & handles after distribute
    showHandles()
    updateHandles()
end

distributeVerticalGroup = function()
    local sel = getSelectedImagesList()
    if #sel < 3 then return end
    -- Sort by y-coordinate
    table.sort(sel, function(a,b) return a.y < b.y end)
    local topY    = sel[1].y
    local bottomY = sel[#sel].y
    local count   = #sel
    local step    = (bottomY - topY) / (count - 1)
    for i, img in ipairs(sel) do
        local ty = topY + (i-1) * step
        img.y = ty
        if img.outline then img.outline.y = ty end
    end
    updateHandles()
    -- redraw bounding box & handles after distribute
    showHandles()
    updateHandles()
end

----------------------------------------------------------------
-- Pending-file list helpers
----------------------------------------------------------------
local function addPendingFile(filePath)
    local group = display.newGroup()

    local fileName = Service.get_file_name(filePath)
    local text = display.newText({
        text  = fileName,
        x     = 45,
        y     = 0,
        font  = native.systemFont,
        fontSize = 20 * 2
    })
    text:setFillColor(0)
    text.xScale, text.yScale = 0.5, 0.5
    text.anchorX = 0
    group:insert(text)

    -- "Place" button
    local placeBtn = display.newImage("GFX/place.png")
    placeBtn.x, placeBtn.y = 20, 0
    placeBtn.xScale, placeBtn.yScale = 0.3, 0.3
    group:insert(placeBtn)

    -- When pressed, enter placement mode for this image
    placeBtn:addEventListener("touch", function(event)
        if event.phase == "ended" then
            -- Begin placement mode instead of immediate placement
            local fileName = Service.get_file_name(filePath)
            Service.copyFileToSB(
                fileName,
                Service.getPath(filePath),
                fileName,
                system.TemporaryDirectory,
                true
            )
            placingImage = display.newImage(fileName, system.TemporaryDirectory)
            placingImage.pathToSave = filePath
            placingImage.ID         = os.time() + math.random(1,1000)
            placingImage.name       = Service.get_file_name_no_extension(filePath)
            placingImage.alpha      = 0.5
            GUI.imageGroup:insert(placingImage)
            -- Position ghost under cursor, converting to imageGroup-local coords
            local localX = event.x - (GUI.imageGroup and GUI.imageGroup.x or 0)
            local localY = event.y - (GUI.imageGroup and GUI.imageGroup.y or 0)
            placingImage.x, placingImage.y = localX, localY
            isPlacing = true
            -- Listen for both mouse and touch to move/finalize placement
            Runtime:addEventListener("mouse", placementMouse)
            placingImage:addEventListener("touch", placementTouch)
        end
        return true
    end)

    -- Position row inside the scroll view
    group.y = 20 + (#pendingFiles) * 40
    filesScrollView:insert(group)
    pendingFiles[#pendingFiles+1] = filePath
end
nextStep = function(FileToProcessPath)
    local uniqueID = os.time() + math.random(1, 1000) -- Ensure a more unique ID
    createdImages = createdImages + 1
    local newImage = display.newImage(Service.get_file_name(FileToProcessPath), system.TemporaryDirectory)
    newImage.pathToSave = FileToProcessPath
    newImage.x = _W / 2
    newImage.y = _H / 2
    newImage.ID = uniqueID -- Unique internal ID
    newImage.name = Service.get_file_name_no_extension(FileToProcessPath) -- Name for display purposes
    newImage:addEventListener("touch", imageTouch)
    GUI.imageGroup:insert(newImage) -- Add the new image to the GUI.imageGroup
    table.insert(images, newImage)
    -- Add the new image to the list
    addImageToList(newImage.ID)
    -- Select the new image and update text colors
    if selectedImage then
        removeHandles()
    end
    selectedImage = newImage
    showHandles()
    updateHandles()
    updateTextColors() -- Update text colors
    -- Initialize the image order table
    initializeImageOrder()
end
local function LoadFileFN()
    local opts = {
        title = "Choose image(s) (PNG) to process",
        filter_patterns = "*.png",
        filter_description = "PNG FILES",
        allow_multiple_selects = true -- Allow multiple file selections
    }
    local FileToProcessPaths = myPlugin.openFileDialog(opts)
    if FileToProcessPaths then
        for _, FileToProcessPath in ipairs(FileToProcessPaths) do
            print("path is " .. FileToProcessPath)
            Service.copyFileToSB(
                Service.get_file_name(FileToProcessPath),
                Service.getPath(FileToProcessPath),
                Service.get_file_name(FileToProcessPath),
                system.TemporaryDirectory,
                true
            )
            addPendingFile(FileToProcessPath)
        end
    end
end
local function LoadFileFunction(event)
    local self = event.target
    if event.phase == "began" then
        display.getCurrentStage():setFocus(self, event.id)
        self.xScale = self.currentXScale - 0.05
        self.yScale = self.currentYScale - 0.05
        self.isFocus = true
    elseif self.isFocus then
        if event.phase == "ended" or event.phase == "cancelled" then
            self.xScale = self.currentXScale
            self.yScale = self.currentYScale
            display.getCurrentStage():setFocus(self, nil)
            self.isFocus = false
            LoadFileFN()
        end
    end
    return true
end



local function createButton(imagePath, xScale, yScale, x, y, touchListener)
    local button = display.newImage(imagePath)

    -- Fallback if the image file is missing
    if not button then
        print("Warning: missing button asset", imagePath)
        button = display.newRoundedRect(0, 0, 40, 40, 6)
        button:setFillColor(0.3, 0.3, 0.3)
    end

    button.xScale = xScale
    button.yScale = yScale
    button.InitialScaleX = xScale
    button.InitialScaleY = yScale
    button.x = x
    button.y = y
    button:addEventListener("touch", touchListener)
    GUI.uiGroup:insert(button)
    return button
end
-- ------------------------------------------------------------
-- Toolbar buttons – created via shared buttonTouch helper
-- ------------------------------------------------------------
local ButtonSave = createButton("GFX/save.png", 0.3, 0.3, 20, 20,
    Service.buttonTouch(function()
        save.saveWorkspace(gatherImageData)
    end))

local ButtonLoad = createButton("GFX/load.png", 0.3, 0.3, 53, 20,
    Service.buttonTouch(function()
        loadWorkspace() 
    end))

local ButtonExport = createButton("GFX/export.png", 0.3, 0.3, 86, 20,
    Service.buttonTouch(function()
        save.exportWorkspace(gatherImageData)
    end))

-- Mode‑toggle buttons keep their tiny dedicated listeners
ButtonResize = createButton("GFX/Cursor.png", 0.3, 0.3, _W / 2 - 30, 20, onButtonResizeTouch)
ButtonRotate = createButton("GFX/rotate.png", 0.3, 0.3, _W / 2 + 3,  20, onButtonRotateTouch)
ButtonPan    = createButton("GFX/pan.png",    0.3, 0.3, _W / 2 + 90, 20, onButtonPanTouch)

-- Layer‑ordering helpers
local ButtonToTop    = createButton("GFX/totop.png",    0.3, 0.3, _W - 285, 20,
    function(e) if e.phase == "ended" then if selectedImage then moveImageToTop   (selectedImage.ID); return true end end end)
local ButtonDown     = createButton("GFX/up_arrow.png", 0.3, 0.3, _W - 252, 20,
    function(e) if e.phase == "ended" then  if selectedImage then moveImageDown    (selectedImage.ID); return true  end end end)
local ButtonUp       = createButton("GFX/down_arrow.png",0.3,0.3, _W - 219, 20,
    function(e) if e.phase == "ended" then  if selectedImage then moveImageUp      (selectedImage.ID); return true  end end end)
local ButtonToBottom = createButton("GFX/tobottom.png", 0.3, 0.3, _W - 186, 20,
    function(e) if e.phase == "ended" then  if selectedImage then moveImageToBottom(selectedImage.ID); return true  end end end)

-- Add‑new‑image button (keeps existing LoadFileFunction)
local ButtonAddNew = createButton("GFX/addnew.png", 0.3, 0.3, _W - 285, 20, LoadFileFunction)

-- Gather our layer-order and AddNew buttons for drawer transitions
local layerButtons = { ButtonAddNew, ButtonToTop, ButtonDown, ButtonUp, ButtonToBottom }
local layerOriginalXs = {}
for i, btn in ipairs(layerButtons) do
    layerOriginalXs[i] = btn.x
end


local buttonSize = ButtonSave.width * 0.3
local buttonSpacing = 3
-- Alignment buttons – handled through the generic Service.buttonTouch helper
local alignVerticalBottom = createButton(
    "GFX/button_alignVerticalBottom.png", 0.3, 0.3,
    _W/2 - buttonSize*3 - buttonSpacing*3, _H - buttonSize,
    Service.buttonTouch(alignVerticalBottomGroup)
)
local alignVerticalTop = createButton(
    "GFX/button_alignVerticalTop.png", 0.3, 0.3,
    _W/2 - buttonSize*2 - buttonSpacing*2, _H - buttonSize,
    Service.buttonTouch(alignVerticalTopGroup)
)
local alignVerticalCenter = createButton(
    "GFX/button_alignVerticalCenter.png", 0.3, 0.3,
    _W/2 - buttonSize - buttonSpacing, _H - buttonSize,
    Service.buttonTouch(alignVerticalCenterGroup)
)
local alignHorizontalLeft = createButton(
    "GFX/button_alignHorizontalLeft.png", 0.3, 0.3,
    _W/2, _H - buttonSize,
    Service.buttonTouch(alignHorizontalLeftGroup)
)
local alignHorizontalRight = createButton(
    "GFX/button_alignHorizontalRight.png", 0.3, 0.3,
    _W/2 + buttonSize + buttonSpacing, _H - buttonSize,
    Service.buttonTouch(alignHorizontalRightGroup)
)
local alignHorizontalCenter = createButton(
    "GFX/button_alignHorizontalCenter.png", 0.3, 0.3,
    _W/2 + buttonSize*2 + buttonSpacing*2, _H - buttonSize,
    Service.buttonTouch(alignHorizontalCenterGroup)
)

-- Distribution buttons
local distributeButtonY = _H - buttonSize
local distX1 = alignHorizontalCenter.x + buttonSize + buttonSpacing

local distributeHorizontal = createButton(
    "GFX/button_horizontalDistribute.png", 0.3, 0.3,
    distX1, distributeButtonY,
    Service.buttonTouch(distributeHorizontalGroup)
)

local distributeVertical = createButton(
    "GFX/button_verticalDistribute.png", 0.3, 0.3,
    distX1 + buttonSize + buttonSpacing, distributeButtonY,
    Service.buttonTouch(distributeVerticalGroup)
)


-- Set initial tint for buttons
GUI.setButtonTint(ButtonResize, true)
GUI.setButtonTint(ButtonRotate, false)
GUI.setButtonTint(ButtonUp, false)
GUI.setButtonTint(ButtonDown, false)

-- Initialize visibility and movement variables
local visible = false
-- Track the state of the shift key

local controlPressed = false


selectResize = function()
    if selectedButton == "resize" then
        selectedButton = nil
        GUI.setButtonTint(ButtonResize, false)
    else
        selectedButton = "resize"
        GUI.setButtonTint(ButtonResize, true)
        GUI.setButtonTint(ButtonPan, false)
        GUI.setButtonTint(ButtonRotate, false)
        updateHandlesForm()
        updateHandles()
    end
end
selectRotate = function()
    if selectedButton == "rotate" then
        selectedButton = nil
        GUI.setButtonTint(ButtonRotate, false)
    else
        selectedButton = "rotate"
        GUI.setButtonTint(ButtonRotate, true)
        GUI.setButtonTint(ButtonPan, false)
        GUI.setButtonTint(ButtonResize, false)
        updateHandlesForm()
        updateHandles()
    end
end



-- Expose updateHandles for undo/redo

-- Function to remove handles from the display
-- Keep outlines above every sprite
----------------------------------------------------------------
local function bringOutlinesToFront()
    -- First: make sure the dedicated handle/outline group sits above sprites
    if GUI.handleGroup and GUI.handleGroup.parent then
        GUI.handleGroup:toFront()
    end

    -- Selected image outline
    if selectedImage and selectedImage.outline then
        selectedImage.outline:toFront()
    end
    -- Multi-selected outlines
    for img,_ in pairs(multiSelectedImages) do
        if img.outline then img.outline:toFront() end
    end
end
_G.bringOutlinesToFront = bringOutlinesToFront


-- Touch listener for selecting an image
imageTouch = function(event)
    -- Ignore touch events on images if pan mode is active
    if selectedButton == "pan" then
        return false
    end
    local image = event.target
    if event.phase == "began" then
        display.getCurrentStage():setFocus(image, event.id)
        image.isFocus = true

        -- Reset the initial positions and offsets
        image.startX, image.startY = image.x, image.y
        image.prevX, image.prevY = image.x, image.y
        image.offsetX = event.x - image.x
        image.offsetY = event.y - image.y

        -- For multi‑select dragging: remember offset of each sprite from the
        -- one we are directly dragging.
        for img,_ in pairs(multiSelectedImages) do
            img.dragOffsetX = img.x - image.x
            img.dragOffsetY = img.y - image.y
        end

        if globals.shiftPressed then
            if selectedImage and selectedImage ~= image then
                -- Add outline to the current selected image and add it to multiSelectedImages
                bringOutlinesToFront()
                multiSelectedImages[selectedImage] = true
                removeHandles()
                selectedImage = nil
                _G.selectedImage = nil

            end

            if multiSelectedImages[image] then
                -- Deselect the image if it's already selected
                multiSelectedImages[image] = nil
                updateTextColors()
                showHandles()
                updateHandles()
            else
                -- Select the image if it's not already selected
                bringOutlinesToFront()
                multiSelectedImages[image] = true
                updateTextColors()
                showHandles()       -- redraw group bounding box
                updateHandles()     -- update handles as needed
                updateParameters()
            end
        else
            -- If clicking on one of the multi-selected images without pressing shift, do nothing
            if multiSelectedImages[image] then
                -- Keep the multi-selected images as they are
                return true
            end

            -- Existing single selection logic
            if selectedImage ~= image then
                removeHandles()
                selectedImage = image
                _G.selectedImage = selectedImage
                showHandles()
                updateTextColors() -- Update text colors
            end
        end

        if image == selectedImage then
            updateHandles()
            updateParameters()
        end

        -- Store initial positions for all selected images
        for img, _ in pairs(multiSelectedImages) do
            img.startX = img.x
            img.startY = img.y
            img.prevX = img.x            -- <-- set prevX at drag start
            img.prevY = img.y
        end
    elseif image.isFocus then
        if event.phase == "moved" then
            local dx = event.x - (image.startX + image.offsetX)
            local dy = event.y - (image.startY + image.offsetY)
            if next(multiSelectedImages) ~= nil then
                -- Move the sprite under the pointer
                image.x = image.startX + dx
                image.y = image.startY + dy
                if image.outline then
                    image.outline.x, image.outline.y = image.x, image.y
                end

                -- Move every other selected sprite by its saved offset
                for img,_ in pairs(multiSelectedImages) do
                    if img ~= image then
                        -- If offsets were somehow nil (e.g. new selection),
                        -- initialise them on the fly
                        if not img.dragOffsetX or not img.dragOffsetY then
                            img.dragOffsetX = img.x - image.x
                            img.dragOffsetY = img.y - image.y
                        end
                        img.x = image.x + img.dragOffsetX
                        img.y = image.y + img.dragOffsetY
                        if img.outline then
                            img.outline.x, img.outline.y = img.x, img.y
                        end
                    end
                end
            else
                -- Single‑sprite drag
                image.x = image.startX + dx
                image.y = image.startY + dy
                if image.outline then
                    image.outline.x, image.outline.y = image.x, image.y
                end
            end
            -- If dragging multiple images, update the bounding box, handles, and panel
            if next(multiSelectedImages) ~= nil then
                refreshHandles()
                updateParameters()
            end

            if image == selectedImage then
                updateHandles()
                updateParameters()
            end
        elseif event.phase == "ended" or event.phase == "cancelled" then
            display.getCurrentStage():setFocus(image, nil)
            image.isFocus = false
            -- Record drag undo/redo for position changes
            local oldX, oldY = image.startX, image.startY
            local newX, newY = image.x, image.y
            if oldX ~= newX or oldY ~= newY then
                if next(multiSelectedImages) then
                    local cmds = {}
                    for img,_ in pairs(multiSelectedImages) do
                        table.insert(cmds, { img = img, old = { x = img.startX, y = img.startY }, new = { x = img.x, y = img.y } })
                    end
                    Undo.push({ imgs = cmds })
                else
                    Undo.push({ img = image, old = { x = oldX, y = oldY }, new = { x = newX, y = newY } })
                end
            end
            -- Clear stored offsets
            for img,_ in pairs(multiSelectedImages) do
                img.dragOffsetX, img.dragOffsetY = nil, nil
            end
            image.dragOffsetX, image.dragOffsetY = nil, nil
        end
    end

    if event.phase == "ended" then
        -- Keep the selected images intact
        if not globals.shiftPressed then
            if selectedImage then
                updateHandles()
                updateParameters()
            end
        end
        -- Clear stored offsets
        for img,_ in pairs(multiSelectedImages) do
            img.dragOffsetX, img.dragOffsetY = nil, nil
        end
        image.dragOffsetX, image.dragOffsetY = nil, nil
        -- Redraw group box & handles after drag ends
        refreshHandles()
        -- Re‑show the parameters panel after handles redraw
        if selectedImage then
            updateParameters()
        end
    end
    return true
end
-- Create a ScrollView for the list of images
local scrollViewHeight = _H - 83
local halfHeight = scrollViewHeight / 2   -- each of our two stacked lists
local TOP_MARGIN = 40
local widget = require("widget")
local scrollView =
    widget.newScrollView(
    {
        width = 300,
        height = halfHeight,
        scrollWidth = 300,
        scrollHeight = halfHeight,
        verticalScrollDisabled = false,
        horizontalScrollDisabled = true,
        backgroundColor = {0.9, 0.9, 1, 0.5}
    }
)
scrollView.x = _W - 150 -- Adjusted the x position to center the scroll view
scrollView.y = _H/2 + halfHeight/2 + 40   -- bottom half of the column
GUI.uiGroup:insert(scrollView)

-- =====================================================================
-- ScrollView for files chosen but not yet placed
-- =====================================================================
filesScrollView = widget.newScrollView({
    width  = 300,
    height = halfHeight,
    scrollWidth  = 300,
    scrollHeight = halfHeight,
    verticalScrollDisabled   = false,
    horizontalScrollDisabled = true,
    backgroundColor = { 0.9, 1, 0.9, 0.5 }  -- light green
})
filesScrollView.x = _W - 150         -- same right column
filesScrollView.y = halfHeight/2 + TOP_MARGIN 
GUI.uiGroup:insert(filesScrollView)

-- Remember scrollViews’ original X positions

scrollOriginalX = scrollView.x
filesOriginalX  = filesScrollView.x

-- Function to animate layer-order and AddNew buttons on/off screen when toggling scrollViews
updateScrollToggleVisibility = function(show)
    -- Slide layer/order and AddNew buttons on/off-screen
    for i, btn in ipairs(layerButtons) do
        local origX = layerOriginalXs[i]
        -- when hidden, tuck to just off the right edge; when shown, return to original
        local targetX = show and origX or (_W + 16)
        transition.to(btn, { x = targetX, time = 200 })
    end
end

-- Create scrollViews toggle button using arrow images
local scrollToggleListener
scrollToggleBtn = display.newImage(scrollDrawerOpen and "GFX/right_arrow.png" or "GFX/left_arrow.png")
scrollToggleBtn.xScale = 0.3
scrollToggleBtn.yScale = 0.3
scrollToggleBtn.x = scrollDrawerOpen and (scrollOriginalX - scrollView.width/2 - 16) or (_W - 16)
scrollToggleBtn.y = scrollView.y + scrollView.height/2 - 16
GUI.uiGroup:insert(scrollToggleBtn)

-- Initialize visibility of related buttons
updateScrollToggleVisibility(scrollDrawerOpen)

-- Define listener for scroll toggle
scrollToggleListener = function(evt)
    if evt.phase == "ended" then
        scrollDrawerOpen = not scrollDrawerOpen
        local offset = scrollView.width + 20
        local tx1 = scrollDrawerOpen and scrollOriginalX or (scrollOriginalX + offset)
        local tx2 = scrollDrawerOpen and filesOriginalX  or (filesOriginalX + offset)
        transition.to(scrollView,      { x = tx1, time = 200 })
        transition.to(filesScrollView, { x = tx2, time = 200 })
        -- slide layer-order and AddNew buttons in sync with scrollViews
        updateScrollToggleVisibility(scrollDrawerOpen)
        -- Move toggle button and swap its image
        local desiredX = scrollDrawerOpen and (scrollOriginalX - scrollView.width/2 - 16) or (_W - 16)
        transition.to(scrollToggleBtn, {
            x = desiredX,
            time = 200,
            onComplete = function()
                local newImage = scrollDrawerOpen and "GFX/right_arrow.png" or "GFX/left_arrow.png"
                scrollToggleBtn:removeSelf()
                scrollToggleBtn = display.newImage(newImage)
                scrollToggleBtn.xScale = 0.3
                scrollToggleBtn.yScale = 0.3
                scrollToggleBtn.x = desiredX
                scrollToggleBtn.y = scrollView.y + scrollView.height/2 - 16
                GUI.uiGroup:insert(scrollToggleBtn)
                scrollToggleBtn:addEventListener("touch", scrollToggleListener)
                -- (Removed: updateScrollToggleVisibility(scrollDrawerOpen) -- now handled above)
            end
        })
    end
    return true
end

-- Attach the listener
scrollToggleBtn:addEventListener("touch", scrollToggleListener)

panelOriginalX, panelOriginalY = GUI.propertiesGroup.x, GUI.propertiesGroup.y
local panelWidth  = (GUI.PropertiesPanel and GUI.PropertiesPanel.width)  or GUI.propertiesGroup.width
local panelHeight = (GUI.PropertiesPanel and GUI.PropertiesPanel.height) or GUI.propertiesGroup.height

-- Reposition layer-order buttons under the pending-files list
local layerButtonY = filesScrollView.y + halfHeight/2 +20
ButtonToTop.y    = layerButtonY
ButtonDown.y     = layerButtonY
ButtonUp.y       = layerButtonY
ButtonToBottom.y = layerButtonY

local function showRenamePopup(imageID, textElement)
    local image = nil
    for i, img in ipairs(images) do
        if img.ID == imageID then
            image = img
            break
        end
    end

    if not image then
        return
    end -- Prevent the function from continuing if the image is nil

    local renameGroup = display.newGroup()
    local background = display.newRoundedRect(renameGroup, _W / 2, _H / 2, 300, 200, 8)
    background:setFillColor(0.8, 0.8, 0.8, 0.8)
    background:addEventListener(
        "touch",
        function()
            return true
        end
    )
    local renameText =
        display.newText(
        {
            parent = renameGroup,
            text = "Rename Image",
            x = _W / 2,
            y = _H / 2 - 60,
            font = native.systemFont,
            fontSize = 24 * 2
        }
    )
    renameText:setFillColor(0)
    renameText.xScale = 0.5
    renameText.yScale = 0.5

    local nameInput = native.newTextField(_W / 2, _H / 2, 200, 40)
    nameInput.text = image.name -- Set the initial text to the current image name
    renameGroup:insert(nameInput)

    local function onRenameComplete(event)
        if event.phase == "ended" then
            image.name = nameInput.text
            textElement.text = nameInput.text
            nameInput:removeSelf()
            renameGroup:removeSelf()
        end
        return true
    end

    local renameButton =
        display.newText(
        {
            parent = renameGroup,
            text = "OK",
            x = _W / 2,
            y = _H / 2 + 60,
            font = native.systemFont,
            fontSize = 20 * 2
        }
    )
    renameButton.xScale = 0.5
    renameButton.yScale = 0.5
    renameButton:setFillColor(0, 0, 1)
    renameButton:addEventListener("touch", onRenameComplete)
    GUI.uiGroup:insert(renameGroup)
end
-- Helper: is a sprite ID currently in multi-select?
local function isMultiSelected(id)
    for img,_ in pairs(multiSelectedImages) do
        if img.ID == id then return true end
    end
    return false
end

----------------------------------------------------------------
-- Show alignment buttons only when multi‑selection is active
----------------------------------------------------------------
local function updateAlignButtonsVisibility()
    local hasMulti = false
    for _ in pairs(multiSelectedImages) do
        hasMulti = true
        break
    end
    -- Buttons are visible only if two or more sprites are selected
    local show = hasMulti
    alignVerticalBottom.isVisible   = show
    alignVerticalTop.isVisible      = show
    alignVerticalCenter.isVisible   = show
    alignHorizontalLeft.isVisible   = show
    alignHorizontalRight.isVisible  = show
    alignHorizontalCenter.isVisible = show
    distributeHorizontal.isVisible = show
    distributeVertical.isVisible   = show
end

-- Hide them at startup
updateAlignButtonsVisibility()

local textElements = {} -- Table to store text elements

updateTextColors = function()
    for _, element in pairs(textElements) do
        local id = element.id
        -- Text always black
        element.text:setFillColor(0)
        if (selectedImage and id == selectedImage.ID) or isMultiSelected(id) then
            -- darken the background
            element.bg:setFillColor(0, 0, 0, 0.2)
        else
            -- clear back to transparent
            element.bg:setFillColor(1, 1, 1, 0)
        end
    end
    -- update align/distribute button visibility
    updateAlignButtonsVisibility()
end

-- Function to reorder the GUI.imageGroup based on the order table
reorderImageGroup = function()
    for i, imageID in ipairs(imageOrder) do
        for j, img in ipairs(images) do
            if img.ID == imageID then
                GUI.imageGroup:insert(img)
                break
            end
        end
    end
    bringOutlinesToFront()
end
-- Function to move an image up in the order table
local function moveImageInOrderTableUp(imageID)
    for i = 2, #imageOrder do
        if imageOrder[i] == imageID then
            -- Swap the order in the table
            imageOrder[i], imageOrder[i - 1] = imageOrder[i - 1], imageOrder[i]
            break
        end
    end
end
-- Function to move an image down in the order table
local function moveImageInOrderTableDown(imageID)
    for i = 1, #imageOrder - 1 do
        if imageOrder[i] == imageID then
            -- Swap the order in the table
            imageOrder[i], imageOrder[i + 1] = imageOrder[i + 1], imageOrder[i]
            break
        end
    end
end


local scrollViewItemCount = 0

-- Drag‑and‑drop reordering for scroll‑view
local DRAG_THRESHOLD = 15
local dragInfo = { isDragging = false, startY = nil, originalIndex = nil, ghostGroup = nil }

-- Insertion line for drag-and-drop reordering
local insertionLine = nil

local function removeInsertionLine()
    if insertionLine then
        insertionLine:removeSelf()
        insertionLine = nil
    end
end

local function drawInsertionLine(index)
    -- Prepare row data
    local entries = {}
    for _, id in ipairs(imageOrder) do
        local elem = textElements[id]
        local rowY = elem.group.y
        local rowH = elem.bg and elem.bg.height or 40
        table.insert(entries, { y = rowY, h = rowH })
    end
    -- Sort by vertical position ascending
    table.sort(entries, function(a, b) return a.y < b.y end)

    -- Determine new Y position for the insertion line
    local yPos
    if index == 1 then
        yPos = entries[1].y - (entries[1].h / 2)
    elseif index > #entries then
        yPos = entries[#entries].y + (entries[#entries].h / 2)
    else
        local above = entries[index - 1].y
        local below = entries[index].y
        yPos = (above + below) / 2
    end

    -- Create the line if needed
    if not insertionLine then
        insertionLine = display.newRect(0, 0, scrollView.width, 4)
        insertionLine.anchorX = 0
        insertionLine.anchorY = 0.5
        insertionLine:setFillColor(0, 0.5, 1, 0.8)
        scrollView:insert(insertionLine)  -- add to the scrollView content
    end

    -- Position and show
    insertionLine.x = 0
    insertionLine.y = yPos
end

local function cloneRowGroup(group)
    -- Capture the row as a snapshot
    local snapshot = display.capture(group)
    snapshot.alpha = 0.5
    -- Align the snapshot over the original scroll-view row
    snapshot.x = scrollView.x
    snapshot.y = scrollView.y - (scrollView.height / 2) + group.y
    -- Insert into UI group for top-layer visibility
    GUI.uiGroup:insert(snapshot)
    return snapshot
end

local function computeDropIndex(y)
    local entries = {}
    for _, id in ipairs(imageOrder) do
        table.insert(entries, { id = id, y = textElements[id].group.y })
    end
    table.sort(entries, function(a, b) return a.y < b.y end)
    for i, entry in ipairs(entries) do
        if y < entry.y then
            return i
        end
    end
    return #entries + 1
end

local function moveInImageOrder(orig, target)
    if orig < target then target = target - 1 end
    local id = table.remove(imageOrder, orig)
    table.insert(imageOrder, target, id)
end

local function highlightTargetRow(y)
    -- Compute insertion index and draw or move the line accordingly
    local targetIndex = computeDropIndex(y)
    drawInsertionLine(targetIndex)
end


-- Initialize the image order table when adding a new image
addImageToList = function(imageID)
    -- Ensure imagesLookup exists and is updated
    if not imagesLookup then imagesLookup = {} end
    local group = display.newGroup()
        -- Background for this row
    local bgRect = display.newRect(group, scrollView.width/2, 0, scrollView.width, 40)
    bgRect.anchorY = 0.5
    bgRect:setFillColor(1, 1, 1, 0)  -- transparent by default
    bgRect.isHitTestable = true
    group.id = imageID

    -- Find the image by ID
    local image
    for i, img in ipairs(images) do
        if img.ID == imageID then
            image = img
            break
        end
    end
    if not image then
        return
    end -- Exit if image not found
    imagesLookup[imageID] = image

    -- Text element for the image name
    local text =
        display.newText(
        {
            text = image.name, -- Use the image's name for display
            x = 45,
            y = 0, -- Positioning within group will be handled later
            font = native.systemFont,
            fontSize = 20 * 2
        }
    )
    text:setFillColor(0)
    text.xScale = 0.5
    text.yScale = 0.5
    text.anchorX = 0
    group:insert(text)

    -- Store reference to the text element and its group
    textElements[imageID] = {id = imageID, text = text, group = group, bg = bgRect} -- Ensure id is set

    -- Rename button
    local renameButton = display.newImage("GFX/edit.png")
    renameButton.x = 20
    renameButton.y = 0 -- Positioning within group will be handled later
    renameButton.xScale = 0.3
    renameButton.yScale = 0.3
    renameButton:setFillColor(0.7, 0.7, 0.8)
    group:insert(renameButton)

    -- Touch listener for the rename button
    renameButton:addEventListener(
        "touch",
        function(event)
            if event.phase == "ended" then
                showRenamePopup(imageID, text)
            end
            return true
        end
    )

    -- Delete button
    local deleteButton = display.newImage("GFX/delete.png")
    deleteButton.x = 280
    deleteButton.y = 0 -- Positioning within group will be handled later
    deleteButton.xScale = 0.3
    deleteButton.yScale = 0.3
    deleteButton:setFillColor(1, 0.6, 0.6)
    group:insert(deleteButton)

    -- Touch listener for the delete button
    deleteButton:addEventListener(
        "touch",
        function(event)
            if event.phase == "ended" then
                deleteImage(imageID)
            end
            return true
        end
    )

    local visibleButton = display.newImage("GFX/visible.png")
    visibleButton.x = 248
    visibleButton.y = 0 -- Positioning within group will be handled later
    visibleButton.xScale = 0.3
    visibleButton.yScale = 0.3
    visibleButton:setFillColor(0.6, 0.6, 0.7)
    group:insert(visibleButton)

    -- Flag to track the button's state
    local isButtonPressed = false

    -- Function to change the button image when pressed
    local function onVisibleButtonTouch(event)
        if event.phase == "began" then
            visibleButton:removeSelf() -- Remove the old image

            if isButtonPressed then
                visibleButton = display.newImage("GFX/visible.png") -- Set the original image
                togleVisibility(true, imageID)
                isButtonPressed = false
            else
                visibleButton = display.newImage("GFX/invisible.png") -- Set the new image
                togleVisibility(false, imageID)
                isButtonPressed = true
            end

            visibleButton.x = 248
            visibleButton.y = 0
            visibleButton.xScale = 0.3
            visibleButton.yScale = 0.3
            visibleButton:setFillColor(0.6, 0.6, 0.7)
            group:insert(visibleButton)
            -- Re-add the event listener to the new image
            visibleButton:addEventListener("touch", onVisibleButtonTouch)
        end
        return true
    end
    -- Add the event listener to the button
    visibleButton:addEventListener("touch", onVisibleButtonTouch)
    -- Touch on row background: drag-and-drop reorder or select/multiselect
    bgRect:addEventListener("touch", function(event)
        local target = event.target
        local group = textElements[imageID].group
        -- Find the image by ID
        local image = imagesLookup and imagesLookup[imageID] or nil
        if event.phase == "began" then
            display.getCurrentStage():setFocus(target, event.id)
            target.isFocus = true
            dragInfo.startY = event.y
            dragInfo.originalIndex = nil
            dragInfo.isDragging = false
            removeInsertionLine()
        elseif target.isFocus and event.phase == "moved" then
            if not dragInfo.startY then return true end
            local dy = math.abs(event.y - dragInfo.startY)
            if not dragInfo.isDragging and dy > DRAG_THRESHOLD then
                dragInfo.isDragging = true
                scrollView._scrollingEnabled = false
                -- capture original index
                for i, id in ipairs(imageOrder) do
                    if id == imageID then
                        dragInfo.originalIndex = i
                        break
                    end
                end
                dragInfo.ghostGroup = cloneRowGroup(group)
                -- group.isVisible = false -- do NOT hide the original row
            end
            if dragInfo.isDragging then
                dragInfo.ghostGroup.y = event.y
                -- Continuously update insertion line using contentToLocal conversion
                local _, localY = scrollView:contentToLocal(0, event.y)
                localY = localY + scrollView.height/2
                highlightTargetRow(localY)
            end
        elseif target.isFocus and (event.phase == "ended" or event.phase == "cancelled") then
            if dragInfo.isDragging then
                scrollView._scrollingEnabled = true
                removeInsertionLine()
                local _, localY = scrollView:contentToLocal(0, event.y)
                localY = localY + scrollView.height/2
                local v = computeDropIndex(localY)
                local count = #imageOrder
                local newIndex = count - v + 2
                moveInImageOrder(dragInfo.originalIndex, newIndex)
                reorderImageGroup()
                updateImageListOrder()
                dragInfo.ghostGroup:removeSelf()
                -- textElements[imageID].group.isVisible = true -- no longer hiding
            else
                -- normal selection
                if globals.shiftPressed then
                    -- Include the previously selected image in the multi-selection
                    if selectedImage and selectedImage ~= image and not multiSelectedImages[selectedImage] then
                        bringOutlinesToFront()
                        multiSelectedImages[selectedImage] = true
                        removeHandles()
                        selectedImage = nil
                        _G.selectedImage = nil
                    end
                    -- Toggle multi-selection for the clicked image, bringing outline to front
                    if multiSelectedImages[image] then
                        multiSelectedImages[image] = nil
                    else
                        bringOutlinesToFront()
                        multiSelectedImages[image] = true
                    end
                    updateTextColors()
                    showHandles()
                    updateHandles()
                    updateParameters()
                else
                    -- Clear any existing multi-selection outlines
                    for img, _ in pairs(multiSelectedImages) do end
                    multiSelectedImages = {}
                    -- Single selection: deselect previous, select new
                    if selectedImage then removeHandles() end
                    selectedImage = image
                    _G.selectedImage = selectedImage
                    showHandles()
                    updateHandles()
                    updateTextColors()
                end
            end
            display.getCurrentStage():setFocus(target, nil)
            target.isFocus = false
        end
        return true
    end)
    scrollView:insert(group)
    -- Add the new image to the order table
    table.insert(imageOrder, imageID)
    group.y = 0
    -- Update the scroll view positions
    updateImageListOrder()
end

updateImageListOrder = function()
    local numImages = #imageOrder
    for i, imageID in ipairs(imageOrder) do
        local element = textElements[imageID]
        if element then
            element.group.y = 20 + (numImages - i) * 40 -- Adjust the spacing between elements
        end
    end
end
togleVisibility = function(visible, imageID)
    for _, img in ipairs(images) do
        if img.ID == imageID then
            img.isVisible = visible                 -- toggle sprite itself
            if img.outline then                     -- keep outline in sync
                img.outline.isVisible = visible
            end
            break
        end
    end
end
-- Function to delete an image and update the scroll view
deleteImage = function(imageID)
    -- Remove the image from the images table
    for i, img in ipairs(images) do
        if img.ID == imageID then
            if selectedImage == img then
                removeHandles()
            end
            -- Remove the image from the display group
            img:removeSelf()
            table.remove(images, i)
            break
        end
    end

    -- Remove the image from the order table
    for i, id in ipairs(imageOrder) do
        if id == imageID then
            table.remove(imageOrder, i)
            break
        end
    end

    -- Remove the corresponding text element
    if textElements[imageID] then
        textElements[imageID].group:removeSelf()
        textElements[imageID] = nil
    end

    -- Update the scroll view positions
    updateImageListOrder()
    reorderImageGroup()
end
-- Function to move an image to the top in the order table
local function moveImageInOrderTableToTop(imageID)
    for i = 1, #imageOrder do
        if imageOrder[i] == imageID then
            table.remove(imageOrder, i)
            table.insert(imageOrder, 1, imageID)
            break
        end
    end
end
-- Function to move an image to the bottom in the order table
local function moveImageInOrderTableToBottom(imageID)
    for i = 1, #imageOrder do
        if imageOrder[i] == imageID then
            table.remove(imageOrder, i)
            table.insert(imageOrder, imageID)
            break
        end
    end
end
-- Function to move an image to the top
moveImageToBottom = function(imageID)
    moveImageInOrderTableToTop(imageID)
    reorderImageGroup()
    updateImageListOrder()
end

-- Function to move an image to the bottom
moveImageToTop = function(imageID)
    moveImageInOrderTableToBottom(imageID)
    reorderImageGroup()
    updateImageListOrder()
end

-- Function to move an image up
moveImageUp = function(imageID)
    moveImageInOrderTableUp(imageID)
    reorderImageGroup()
    updateImageListOrder()
end

-- Function to move an image down
moveImageDown = function(imageID)
    moveImageInOrderTableDown(imageID)
    reorderImageGroup()
    updateImageListOrder()
end

-- Initialize the image order table when adding a new image

ButtonAddNew.currentXScale = ButtonAddNew.xScale
ButtonAddNew.currentYScale = ButtonAddNew.yScale

-- Touch listener for deselecting the image by clicking on the background
local function backgroundTouch(event)
    if selectedButton == "pan" then
        if event.phase == "began" then
            display.getCurrentStage():setFocus(event.target, event.id)
            isPanning = true
            startPanX, startPanY = event.x - GUI.imageGroup.x, event.y - GUI.imageGroup.y
        elseif isPanning then
            if event.phase == "moved" then
                GUI.imageGroup.x = event.x - startPanX
                GUI.imageGroup.y = event.y - startPanY
            elseif event.phase == "ended" or event.phase == "cancelled" then
                display.getCurrentStage():setFocus(event.target, nil)
                isPanning = false
            end
        end
        return true
    end

    if event.phase == "ended" then
        -- Clear all handles (including group bounding box)
        removeHandles()
        -- Clear primary selection
        selectedImage = nil
        _G.selectedImage = nil

        -- Remove all outlines from multi-selected images
        -- Clear the multi-selection table
        multiSelectedImages = {}
        -- Refresh row highlighting and align/distribute button visibility
        updateTextColors()
        -- Clear properties inputs when no selection
        PropertiesXinput.text      = ""
        PropertiesYinput.text      = ""
        PropertiesScaleXinput.text = ""
        PropertiesScaleYinput.text = ""
        PropertiesRotationinput.text = ""
        PropertiesAlphainput.text  = ""
    end
    return true
end
--- -save load functionality
gatherImageData = function()
    local t = { images = {}, pendingFiles = {} }

    -- Save placed images
    for i, imageID in ipairs(imageOrder) do
        for _, img in ipairs(images) do
            if img.ID == imageID then
                table.insert(t.images, {
                    path           = img.pathToSave or img.path,
                    name           = img.name,
                    x              = img.x,
                    y              = img.y,
                    width          = img.width,
                    height         = img.height,
                    rotation       = img.rotation,
                    alpha          = img.alpha,
                    xScale         = img.xScale,
                    yScale         = img.yScale,
                    hierarchyIndex = i
                })
                break
            end
        end
    end

    -- Save upper scroll‑view list
    for _, p in ipairs(pendingFiles) do
        table.insert(t.pendingFiles, p)
    end

    return t
end
clearWorkspace = function()
    for _, img in ipairs(images) do
        img:removeSelf()
    end
    images = {}
    pendingFiles = {}
    imageOrder = {}
    textElements = {}
    scrollViewItemCount = 0 -- Reset the counter
    removeHandles()
    -- Recreate placed‑images scroll view (bottom half)
    if scrollView then scrollView:removeSelf(); scrollView = nil end
    scrollView = widget.newScrollView({
        width = 300,
        height = halfHeight,
        scrollWidth  = 300,
        scrollHeight = halfHeight,
        verticalScrollDisabled = false,
        horizontalScrollDisabled = true,
        backgroundColor = {0.9, 0.9, 1, 0.5}
    })
    scrollView.x = _W - 150
    scrollView.y = _H/2 + halfHeight/2+ 40
    GUI.uiGroup:insert(scrollView)

    -- Remove & recreate the pending‑files scroll view (top half)
    if filesScrollView then filesScrollView:removeSelf(); filesScrollView = nil end
    filesScrollView = widget.newScrollView({
        width = 300,
        height = halfHeight,
        scrollWidth  = 300,
        scrollHeight = halfHeight,
        verticalScrollDisabled = false,
        horizontalScrollDisabled = true,
        backgroundColor = { 0.9, 1, 0.9, 0.5 }
    })
    filesScrollView.x = _W - 150
    filesScrollView.y = _H/2 - halfHeight/2
    GUI.uiGroup:insert(filesScrollView)
end
loadWorkspace = function()
    local confirm =
        native.showAlert(
        "Confirmation",
        "Do you really want to clear the current workspace?",
        {"Yes", "Cancel"},
        function(event)
            if event.action == "clicked" and event.index == 1 then
                clearWorkspace()
                save.loadWorkspace(
                    addImageToList,
                    addPendingFile,
                    initializeImageOrder,
                    updateImageListOrder,
                    reorderImageGroup,
                    imageTouch,
                    images,
                    imageOrder,
                    GUI.imageGroup
                )
            end
        end
    )
end
-- Add the background touch listener to the entire screen
local background = display.newRect(_W / 2, _H / 2, _W, _H)
background:setFillColor(0.95, 0.95, 1, 1) -- Set to nearly transparent
background:addEventListener("touch", backgroundTouch)
background:toBack() -- Send background to the back layer
GUI.uiGroup:insert(GUI.propertiesGroup)

-- Capture panel’s on-screen coords and size
buttonOriginalX, buttonOriginalY = GUI.PropertiesPanel.width + 32, _H - 20
local PanelOrX = GUI.propertiesGroup.x
local panelWidth  = (GUI.PropertiesPanel and GUI.PropertiesPanel.width)  or GUI.propertiesGroup.width
local panelHeight = (GUI.PropertiesPanel and GUI.PropertiesPanel.height) or GUI.propertiesGroup.height

-- Create panel toggle button (initially showing left arrow)
panelToggleBtn = display.newImage("GFX/left_arrow.png")
panelToggleBtn.xScale = 0.3
panelToggleBtn.yScale = 0.3
panelToggleBtn.x = buttonOriginalX
panelToggleBtn.y = buttonOriginalY
GUI.uiGroup:insert(panelToggleBtn)

-- Touch listener for panel toggle button, defined once for reuse
local function panelToggleListener(evt)
    if evt.phase == "ended" then
        -- Toggle drawer state
        panelDrawerOpen = not panelDrawerOpen
        -- Slide the properties panel
        local targetX = panelDrawerOpen
            and PanelOrX
            or (PanelOrX - (panelWidth*2 + 20))
        transition.to(GUI.propertiesGroup, { x = targetX, time = 200 })
        -- Compute new button X
        local desiredX = panelDrawerOpen and buttonOriginalX or 16
        -- Slide the button and swap its image on completion
        transition.to(panelToggleBtn, {
            x = desiredX,
            y = buttonOriginalY,
            time = 200,
            onComplete = function()
                -- Choose arrow direction based on new state
                local newImage = panelDrawerOpen
                    and "GFX/left_arrow.png"
                    or "GFX/right_arrow.png"
                -- Recreate the button with updated image
                panelToggleBtn:removeSelf()
                panelToggleBtn = display.newImage(newImage)
                panelToggleBtn.xScale = 0.3
                panelToggleBtn.yScale = 0.3
                panelToggleBtn.x = desiredX
                panelToggleBtn.y = buttonOriginalY
                GUI.uiGroup:insert(panelToggleBtn)
                panelToggleBtn:addEventListener("touch", panelToggleListener)
            end
        })
    end
    return true
end

-- Attach the listener
panelToggleBtn:addEventListener("touch", panelToggleListener)


-- Always show properties panel
GUI.propertiesGroup.alpha = 1
-- Also ensure its background panel (if any) is visible
if GUI.PropertiesPanel then GUI.PropertiesPanel.alpha = 1 end


local function onKey(event)
    if     event.keyName == "leftShift"  or event.keyName == "rightShift"  then
        globals.shiftPressed   = (event.phase == "down")
    elseif event.keyName == "leftControl"or event.keyName == "rightControl"
        or event.keyName == "leftCommand"or event.keyName == "rightCommand" then
        controlPressed = (event.phase == "down")
    end
    if event.phase ~= "down" then return false end
    if event.keyName == "escape" and isPlacing then
        if placingImage and placingImage.removeSelf then placingImage:removeSelf() end
        isPlacing   = false
        placingImage = nil
        Runtime:removeEventListener("mouse", placementMouse)
        return true
    end
    if event.keyName == "z" and (event.isCtrlDown or event.isCommandDown) then
        if event.isShiftDown then Undo.redo() else Undo.undo() end
        return true
    end
    if event.keyName == "c" and (event.isCtrlDown or event.isCommandDown) then
        local sel = getSelectedImagesList()
        if #sel > 1 then
            clipboard = { multiple = true, items = {} }
            for _, img in ipairs(sel) do
                clipboard.items[#clipboard.items+1] = {
                    path     = img.pathToSave or img.path,
                    name     = img.name,
                    x        = img.x,
                    y        = img.y,
                    width    = img.width,
                    height   = img.height,
                    rotation = img.rotation,
                    alpha    = img.alpha,
                    xScale   = img.xScale,
                    yScale   = img.yScale,
                }
            end
        elseif selectedImage then
            clipboard = {
                multiple = false,
                item = {
                    path     = selectedImage.pathToSave or selectedImage.path,
                    name     = selectedImage.name,
                    x        = selectedImage.x,
                    y        = selectedImage.y,
                    width    = selectedImage.width,
                    height   = selectedImage.height,
                    rotation = selectedImage.rotation,
                    alpha    = selectedImage.alpha,
                    xScale   = selectedImage.xScale,
                    yScale   = selectedImage.yScale,
                }
            }
        end
        return true
    end
    if event.keyName == "v" and (event.isCtrlDown or event.isCommandDown) and clipboard then
        local newSel = {}
        local function pasteOne(data)
            local fileName = Service.get_file_name(data.path)
            Service.copyFileToSB(fileName, Service.getPath(data.path),
                                 fileName, system.TemporaryDirectory, true)
            local img = display.newImage(fileName, system.TemporaryDirectory)
            img.ID         = os.time() + math.random(1,1000)
            img.name       = data.name
            img.pathToSave = data.path
            img.x, img.y   = data.x, data.y
            img.width, img.height = data.width, data.height
            img.xScale, img.yScale = data.xScale, data.yScale
            img.rotation   = data.rotation
            img.alpha      = data.alpha
            img:addEventListener("touch", imageTouch)
            GUI.imageGroup:insert(img)
            images[#images+1] = img
            addImageToList(img.ID)
            newSel[#newSel+1] = img
        end
        if clipboard.multiple then
            for _,data in ipairs(clipboard.items) do pasteOne(data) end
        else
            pasteOne(clipboard.item)
        end
        initializeImageOrder()
        selectedImage = nil
        _G.selectedImage = nil

        multiSelectedImages = {}
        for _,img in ipairs(newSel) do multiSelectedImages[img] = true end
        refreshHandles(); updateTextColors()
        return true
    end

    if event.keyName == "s" then selectResize(); return true end
    if event.keyName == "r" then selectRotate(); return true end

    if event.keyName=="up" or event.keyName=="down"
       or event.keyName=="left" or event.keyName=="right" then

        local step  = controlPressed and 5 or (globals.shiftPressed and 0.1 or 1)
        local dx,dy = 0,0
        if     event.keyName=="up"    then dy=-step
        elseif event.keyName=="down"  then dy= step
        elseif event.keyName=="left"  then dx=-step
        elseif event.keyName=="right" then dx= step
        end

        local selList = getSelectedImagesList()
        for _,img in ipairs(selList) do
            img.x, img.y = img.x+dx, img.y+dy
            if img.outline then img.outline.x, img.outline.y = img.x, img.y end
        end
        updateHandles(); updateParameters()
        updateTextColors(); bringOutlinesToFront()
        return true
    end

    if event.keyName == "tab" then
        if scrollToggleBtn then
            scrollToggleBtn:dispatchEvent({ name="touch", phase="ended" })
        end
        if panelToggleBtn then
            panelToggleBtn:dispatchEvent({ name="touch", phase="ended" })
        end
        return true
    end

    return false
end

Runtime:addEventListener("key", onKey)