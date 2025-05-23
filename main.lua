-----------------------------------------------------------------------------------------
-- main.lua
-----------------------------------------------------------------------------------------
--[[
GraphicsMover - Image Manipulation Application
Version: 1.0

DESCRIPTION:
This application allows users to load, manipulate, and arrange multiple images in a workspace.
It provides tools for resizing, rotating, repositioning, and organizing images in layers.

FEATURES:
1. Image Management:
   - Load multiple PNG images into a workspace
   - Save and load workspaces to/from files
   - Export workspace configurations as Lua files
   - Organize images in layers with controls to move images up/down in the layer hierarchy

2. Image Manipulation:
   - Resize images using corner handles
   - Rotate images using rotation handles
   - Pan/move images by dragging them
   - Flip images horizontally or vertically
   - Adjust image opacity/transparency
   - Pan the entire workspace

3. User Interface:
   - Properties panel showing the selected image's position, size, rotation, and opacity
   - Layer management with a scrollable list of images
   - Ability to rename images
   - Toggle image visibility
   - Delete images from the workspace
   - Multi-select images with shift key for group operations

KEYBOARD SHORTCUTS:
   - Shift: Multi-select images
   - 's': Switch to resize mode
   - 'r': Switch to rotate mode

DEPENDENCIES:
   - Corona SDK/Solar2D game engine
   - tinyfiledialogs plugin for file dialogs
   - widget library for UI components

CODE ORGANIZATION:
   - UI setup and initialization at the top
   - Event handlers and touch functions in the middle
   - Image manipulation functions (resize, rotate, etc.)
   - Layer management functions
   - File operations (save, load, export)
--]]

_W = display.contentWidth
_H = display.contentHeight
local json = require("json")
local save = require("saveexport")
local myPlugin = require("plugin.tinyfiledialogs")
local Service = require("service")
local GUI = require("GUIcontrolFunctions")
local Checkbox = require("Checkbox")

--------------------------------------
-- Declarations and predeclarations ---
--------------------------------------
local tt = transition.to
local selectedButton = "resize"
local removeHandles, showHandles, updateHandles, updateTextColors, moveImageUp,
    moveImageDown, deleteImage, selectedImage, ButtonRotate, ButtonResize,
    moveImageToTop, moveImageToBottom, saveWorkspace, loadWorkspace,
    updateImageListOrde, exportWorkspace, gatherImageData, clearWorkspace,
    imageTouch, addImageToList, reorderImageGroup, selectResize,
    selectRotate, startPanX, startPanY, LoadFileFunction, addPendingFile, nextStep
local images = {}
local handles = {}
local resizeHandles = {}
local rotateHandles = {}
local multiSelectedImages = {}
local imageOrder = {}
local isPanning = false
local panelVisible = true
local createdImmages = 0
local canvasZoomSize = 1
local zoomFactor = 1
-- Pending files awaiting placement
local pendingFiles = {}
local filesScrollView -- pending‑files list (green, top‑right)

-- Function to get the currently selected image
local function getSelectedImage()
    return selectedImage
end


local checkboxFlipX = Checkbox:new{ id = "checkboxFlipX", x = flipXText.x + 19, y = flipXText.y, parentGroup = GUI.propertiesGroup, getSelectedImage = getSelectedImage }
local checkboxFlipY = Checkbox:new{ id = "checkboxFlipY", x = flipYText.x + 19, y = flipYText.y, parentGroup = GUI.propertiesGroup, getSelectedImage = getSelectedImage }

local PropertiesXinput = GUI.createTextField(PropertiesXtext.x + 60, PropertiesXtext.y, 100, 15, GUI.propertiesGroup)
local PropertiesYinput = GUI.createTextField(PropertiesYtext.x + 60, PropertiesYtext.y, 100, 15, GUI.propertiesGroup)
local PropertiesScaleXinput = GUI.createTextField(PropertiesScaleXtext.x + 60, PropertiesScaleXtext.y, 100, 15, GUI.propertiesGroup)
local PropertiesScaleYinput = GUI.createTextField(PropertiesScaleYtext.x + 60, PropertiesScaleYtext.y, 100, 15, GUI.propertiesGroup)
local PropertiesAlphainput = GUI.createTextField(PropertiesOpacitytext.x + 60, PropertiesOpacitytext.y, 100, 15, GUI.propertiesGroup)
local PropertiesRotationinput = GUI.createTextField(PropertiesRotationtext.x + 60, PropertiesRotationtext.y, 100, 15, GUI.propertiesGroup)

local function SliderChanged(value)
    if selectedImage then
        selectedImage.alpha = value
        PropertiesAlphainput.text = string.format("%.2f", value)
    end
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
            if selectedImage then
                selectedImage[property] = value
                if callback then
                    callback(value)
                end
                updateHandles()
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
    if panelVisible == false then
        GUI.PropertiesPanel.xScale = 0.8
        GUI.PropertiesPanel.yScale = 0.8
        tt(GUI.PropertiesPanel, {xScale = 1, yScale = 1, time = 80, transition = easing.inOutBack})
        tt(
            GUI.propertiesGroup,
            {
                alpha = 1,
                time = 150,
                onComplete = function()
                    PropertiesXinput.isVisible = true
                    PropertiesRotationinput.isVisible = true
                    PropertiesAlphainput.isVisible = true
                    PropertiesScaleYinput.isVisible = true
                    PropertiesScaleXinput.isVisible = true
                    PropertiesYinput.isVisible = true
                end
            }
        )
    end
    panelVisible = true
    PropertiesXinput.text = tostring(selectedImage.x)
    PropertiesYinput.text = tostring(selectedImage.y)
    PropertiesScaleXinput.text = tostring(selectedImage.width)
    PropertiesScaleYinput.text = tostring(selectedImage.height)
    PropertiesAlphainput.text = tostring(selectedImage.alpha)
    PropertiesRotationinput.text = tostring(selectedImage.rotation)
    OpacitySlider.alpha = 1
    OpacitySlider:setValue(selectedImage.alpha)
    
    if selectedImage.xScale == -1 then
        checkboxFlipX:setCheckedState(true)
    else
        checkboxFlipX:setCheckedState(false)
    end
    if selectedImage.yScale == -1 then
        checkboxFlipY:setCheckedState(true)
    else
        checkboxFlipY:setCheckedState(false)
    end
end
local function makePanelInvisible()
    PropertiesXinput.isVisible = false
    PropertiesRotationinput.isVisible = false
    PropertiesAlphainput.isVisible = false
    PropertiesScaleYinput.isVisible = false
    PropertiesScaleXinput.isVisible = false
    PropertiesYinput.isVisible = false
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
local function onButtonUpTouch(event)
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
            if selectedImage then
                moveImageUp(selectedImage.ID)
            end
        end
    end
    return true
end
local function onButtonToBottomTouch(event)
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
            if selectedImage then
                moveImageToBottom(selectedImage.ID)
            end
        end
    end
    return true
end
local function onButtonToTopTouch(event)
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
            if selectedImage then
                moveImageToTop(selectedImage.ID)
            end
        end
    end
    return true
end
local function onButtonDownTouch(event)
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
            if selectedImage then
                moveImageDown(selectedImage.ID)
            end
        end
    end
    return true
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
    if event.phase == "ended" then
        if selectedButton == "pan" then
            selectedButton = nil
            GUI.setButtonTint(ButtonPan, false)
        else
            selectedButton = "pan"
            GUI.setButtonTint(ButtonPan, true)
            GUI.setButtonTint(ButtonResize, false)
            GUI.setButtonTint(ButtonRotate, false)
            removeHandles()
        end
    end
    return true
end
local function updateHandlesForm()
    if selectedImage then
        removeHandles()
        showHandles()
    end
end
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
local function initializeImageOrder()
    imageOrder = {}
    for i, img in ipairs(images) do
        table.insert(imageOrder, img.ID)
    end
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
    local placeBtn = display.newImage("GFX/addnew.png")
    placeBtn.x, placeBtn.y = 20, 0
    placeBtn.xScale, placeBtn.yScale = 0.3, 0.3
    group:insert(placeBtn)

    -- When pressed, spawn a new instance in the workspace but keep this row for reuse
    placeBtn:addEventListener("touch", function(event)
        if event.phase == "ended" then
            -- Spawn a *new* instance of the chosen image in the workspace,
            -- but keep this row so it can be used again later.
            nextStep(filePath)
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
    createdImmages = createdImmages + 1
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
-- Create Buttons using the Factory Function
local ButtonSave = createButton("GFX/save.png", 0.3, 0.3, 20, 20, onButtonSaveTouch)
local ButtonLoad = createButton("GFX/load.png", 0.3, 0.3, 53, 20, onButtonLoadTouch)
local ButtonExport = createButton("GFX/export.png", 0.3, 0.3, 86, 20, onButtonExportTouch)
local ButtonResize = createButton("GFX/resize.png", 0.3, 0.3, _W / 2 - 30, 20, onButtonResizeTouch)
local ButtonRotate = createButton("GFX/rotate.png", 0.3, 0.3, _W / 2 + 3, 20, onButtonRotateTouch)
local ButtonPan = createButton("GFX/pan.png", 0.3, 0.3, _W / 2 + 90, 20, onButtonPanTouch)
local ButtonToTop = createButton("GFX/totop.png", 0.3, 0.3, _W - 285, 20, onButtonToTopTouch)
local ButtonDown = createButton("GFX/up_arrow.png", 0.3, 0.3, _W - 252, 20, onButtonDownTouch)
local ButtonUp = createButton("GFX/down_arrow.png", 0.3, 0.3, _W - 219, 20, onButtonUpTouch)
local ButtonToBottom = createButton("GFX/tobottom.png", 0.3, 0.3, _W - 186, 20, onButtonToBottomTouch)
local ButtonAddNew = createButton("GFX/addnew.png", 0.3, 0.3, _W - 285, _H - 20, LoadFileFunction)
-- Set initial tint for buttons
GUI.setButtonTint(ButtonResize, true)
GUI.setButtonTint(ButtonRotate, false)
GUI.setButtonTint(ButtonUp, false)
GUI.setButtonTint(ButtonDown, false)

-- Initialize visibility and movement variables
local visible = false
-- Track the state of the shift key
local multiSelectedImages = {}
local shiftPressed = false
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
-- Function to update handle positions based on the image size, position, and rotation
updateHandles = function()
    if selectedImage then
        local halfWidth = selectedImage.width / 2
        local halfHeight = selectedImage.height / 2
        local cosRot = math.cos(math.rad(selectedImage.rotation))
        local sinRot = math.sin(math.rad(selectedImage.rotation))

        -- Adjust positions based on the imageGroup's position
        local groupX, groupY = GUI.imageGroup.x, GUI.imageGroup.y

        local function getRotatedPosition(x, y)
            return {
                x = (selectedImage.x + (x * cosRot - y * sinRot)) * zoomFactor + GUI.imageGroup.x,
                y = (selectedImage.y + (x * sinRot + y * cosRot)) * zoomFactor + GUI.imageGroup.y
            }
        end

        if selectedButton == "resize" then
            local topLeft = getRotatedPosition(-halfWidth, -halfHeight)
            local topRight = getRotatedPosition(halfWidth, -halfHeight)
            local bottomLeft = getRotatedPosition(-halfWidth, halfHeight)
            local bottomRight = getRotatedPosition(halfWidth, halfHeight)

            resizeHandles.topLeft.x, resizeHandles.topLeft.y = topLeft.x, topLeft.y
            resizeHandles.topRight.x, resizeHandles.topRight.y = topRight.x, topRight.y
            resizeHandles.bottomLeft.x, resizeHandles.bottomLeft.y = bottomLeft.x, bottomLeft.y
            resizeHandles.bottomRight.x, resizeHandles.bottomRight.y = bottomRight.x, bottomRight.y
        elseif selectedButton == "rotate" then
            local topLeft = getRotatedPosition(-halfWidth, -halfHeight)
            local topRight = getRotatedPosition(halfWidth, -halfHeight)
            local bottomLeft = getRotatedPosition(-halfWidth, halfHeight)
            local bottomRight = getRotatedPosition(halfWidth, halfHeight)

            rotateHandles.topLeft.x, rotateHandles.topLeft.y = topLeft.x, topLeft.y
            rotateHandles.topRight.x, rotateHandles.topRight.y = topRight.x, topRight.y
            rotateHandles.bottomLeft.x, rotateHandles.bottomLeft.y = bottomLeft.x, bottomLeft.y
            rotateHandles.bottomRight.x, rotateHandles.bottomRight.y = bottomRight.x, bottomRight.y
        end
    end
    for img, _ in pairs(multiSelectedImages) do
        img.prevX, img.prevY = img.x, img.y
    end
end
local HandleScale = 1.8
local HandleScale = 1.8

local function handleTouch(event)
    local handle = event.target
    if event.phase == "began" then
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
            local dx, dy = (event.x - handle.startX) / zoomFactor, (event.y - handle.startY) / zoomFactor
            if selectedButton == "resize" then
                local proportion = handle.startWidth / handle.startHeight

                Service.updateImageSizeAndPosition(
                    selectedImage,
                    resizeHandles,
                    handle,
                    dx,
                    dy,
                    proportion,
                    shiftPressed,
                    controlPressed,
                    zoomFactor
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
            display.getCurrentStage():setFocus(handle, nil)
            handle.isFocus = false
            --handle:scale(1 / HandleScale, 1 / HandleScale) -- Scale back the handle to its original size
            transition.cancel("scaleHandles")
            tt(handle, {xScale = 1, yScale = 1, time = 150, tag = "scaleHandles"})
        end
    end
    return true
end
-- Function to add touch listeners to handles
local function addHandleListeners()
    for _, handle in pairs(handles) do
        handle:addEventListener("touch", handleTouch)
    end
end
-- Function to remove handles from the display
removeHandles = function()
    for _, handle in pairs(resizeHandles) do
        handle:removeSelf()
    end
    resizeHandles = {}
    for _, handle in pairs(rotateHandles) do
        handle:removeSelf()
    end
    rotateHandles = {}
    clearParameters()
end
-- Function to create and show handles around the selected image
showHandles = function()
    if selectedImage then
        if selectedButton == "resize" then
            -- Create resize handles (ignoring rotation)
            resizeHandles = {
                topLeft = createHandle(
                    selectedImage.x - selectedImage.width / 2,
                    selectedImage.y - selectedImage.height / 2
                ),
                topRight = createHandle(
                    selectedImage.x + selectedImage.width / 2,
                    selectedImage.y - selectedImage.height / 2
                ),
                bottomLeft = createHandle(
                    selectedImage.x - selectedImage.width / 2,
                    selectedImage.y + selectedImage.height / 2
                ),
                bottomRight = createHandle(
                    selectedImage.x + selectedImage.width / 2,
                    selectedImage.y + selectedImage.height / 2
                )
            }
            -- Add touch listeners to resize handles
            for _, handle in pairs(resizeHandles) do
                handle:addEventListener("touch", handleTouch)
            end
        elseif selectedButton == "rotate" then
            -- Create rotation handles
            local halfWidth = selectedImage.width / 2 * zoomFactor
            local halfHeight = selectedImage.height / 2 * zoomFactor
            local cosRot = math.cos(math.rad(selectedImage.rotation))
            local sinRot = math.sin(math.rad(selectedImage.rotation))
            local function getRotatedPosition(x, y)
                return {
                    x = selectedImage.x + (x * cosRot - y * sinRot),
                    y = selectedImage.y + (x * sinRot + y * cosRot)
                }
            end
            local topLeft = getRotatedPosition(-halfWidth, -halfHeight)
            local topRight = getRotatedPosition(halfWidth, -halfHeight)
            local bottomLeft = getRotatedPosition(-halfWidth, halfHeight)
            local bottomRight = getRotatedPosition(halfWidth, halfHeight)
            rotateHandles = {
                topLeft = createHandle(topLeft.x, topLeft.y),
                topRight = createHandle(topRight.x, topRight.y),
                bottomLeft = createHandle(bottomLeft.x, bottomLeft.y),
                bottomRight = createHandle(bottomRight.x, bottomRight.y)
            }
            -- Set rotation for rotation handles
            for _, handle in pairs(rotateHandles) do
                handle.rotation = selectedImage.rotation
                handle:addEventListener("touch", handleTouch)
            end
        end
        updateParameters()
    end
end
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

        if shiftPressed then
            if selectedImage and selectedImage ~= image then
                -- Add outline to the current selected image and add it to multiSelectedImages
                GUI.drawOutline(selectedImage)
                multiSelectedImages[selectedImage] = true
                removeHandles()
                selectedImage = nil
            end
            
            if multiSelectedImages[image] then
                -- Deselect the image if it's already selected
                GUI.removeOutline(image)
                multiSelectedImages[image] = nil
            else
                -- Select the image if it's not already selected
                GUI.drawOutline(image)
                multiSelectedImages[image] = true
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
            img.prevX = img.x
            img.prevY = img.y
        end
    elseif image.isFocus then
        if event.phase == "moved" then
            local dx = event.x - (image.startX + image.offsetX)
            local dy = event.y - (image.startY + image.offsetY)
            if next(multiSelectedImages) ~= nil then
                for img, _ in pairs(multiSelectedImages) do
                    img.x = img.startX + dx
                    img.y = img.startY + dy
                    if img.outline then
                        img.outline.x = img.x
                        img.outline.y = img.y
                    end
                end
            else
                image.x = image.startX + dx
                image.y = image.startY + dy
                if image.outline then
                    image.outline.x = image.x
                    image.outline.y = image.y
                end
            end
            if image == selectedImage then
                updateHandles()
                updateParameters()
            end
        elseif event.phase == "ended" or event.phase == "cancelled" then
            display.getCurrentStage():setFocus(image, nil)
            image.isFocus = false
            if next(multiSelectedImages) ~= nil then
                for img, _ in pairs(multiSelectedImages) do
                    img.prevX = img.x
                    img.prevY = img.y
                end
            else
                image.prevX = image.x
                image.prevY = image.y
            end
        end
    end

    if event.phase == "ended" then
        -- Keep the selected images intact
        if not shiftPressed then
            if selectedImage then
                updateHandles()
                updateParameters()
            end
        end
    end
    return true
end
-- Create a ScrollView for the list of images
local scrollViewHeight = _H - 83
local halfHeight = scrollViewHeight / 2   -- each of our two stacked lists
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
scrollView.y = _H/2 + halfHeight/2   -- bottom half of the column
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
filesScrollView.y = _H/2 - halfHeight/2   -- top half
GUI.uiGroup:insert(filesScrollView)


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
    local background = display.newRoundedRect(renameGroup, _W / 2, _H / 2, 300, 200, 5)
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
local textElements = {} -- Table to store text elements

updateTextColors = function()
    for _, element in pairs(textElements) do
        if selectedImage and element.id == selectedImage.ID then
            element.text:setFillColor(0, 0, 1) -- Blue color for selected image
        elseif multiSelectedImages[element] then
            element.text:setFillColor(0.5, 0.5, 0.5) -- Gray color for multi-selected images
        else
            element.text:setFillColor(0) -- Black color for unselected images
        end
    end
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


-- Initialize the image order table when adding a new image
addImageToList = function(imageID)
    local group = display.newGroup()
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
    textElements[imageID] = {id = imageID, text = text, group = group} -- Ensure id is set

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
    -- Make the text element touch-sensitive to select the image
    text:addEventListener(
        "touch",
        function(event)
            if event.phase == "ended" then
                selectedImage = nil
                for i, img in ipairs(images) do
                    if img.ID == imageID then
                        selectedImage = img
                        break
                    end
                end
                removeHandles()
                showHandles()
                updateHandles()
                updateTextColors()
            end
            return true
        end
    )
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
    for i, img in ipairs(images) do
        if img.ID == imageID then
            if selectedImage == img then
                if visible then
                    img.isVisible = true
                else
                    img.isVisible = false
                end
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
        if selectedImage then
            removeHandles()
            selectedImage = nil
            updateTextColors() -- Update text colors
        end
        -- Deselect all multi-selected images
        for img, _ in pairs(multiSelectedImages) do
            GUI.removeOutline(img)
        end
        multiSelectedImages = {}
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
    scrollView.y = _H/2 + halfHeight/2
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
makePanelInvisible()

-- Key event listener to track shift key state
local function onKeyEvent(event)
    if event.keyName == "leftShift" or event.keyName == "rightShift" then
        if event.phase == "down" then
            shiftPressed = true
        elseif event.phase == "up" then
            shiftPressed = false
        end
    end
    if event.keyName == "leftControl" or event.keyName == "rightControl" then
        if event.phase == "down" then
            controlPressed = true
        elseif event.phase == "up" then
            controlPressed = false
        end
    end
    -- Add key event handling for "s" and "r"
    if event.phase == "down" then
        if event.keyName == "s" then
            selectResize()
        elseif event.keyName == "r" then
            selectRotate()
        end
    end

    return false
end
Runtime:addEventListener("key", onKeyEvent)
