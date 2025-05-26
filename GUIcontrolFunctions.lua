local M = {}

M.imageGroup = display.newGroup()
M.handleGroup = display.newGroup()
M.uiGroup = display.newGroup()
M.propertiesGroup = display.newGroup()
M.uiGroup:toFront()

M.createSlider = function(options)
    -- Default options
    options = options or {}
    local width = options.width or 200
    local height = options.height or 4
    local thumbRadius = options.thumbRadius or 10
    local capRadius = height / 2
    local minValue = options.minValue or 0
    local maxValue = options.maxValue or 1  -- Ensure maxValue is 1 for alpha
    local startValue = options.startValue or 1  -- Ensure startValue is 1 for alpha
    local onChange = options.onChange or function(value) end

    -- Create slider group
    local sliderGroup = display.newGroup()

    -- Create the track
    local track = display.newRect(sliderGroup, 0, 0, width, height)
    track:setFillColor(0.8, 0.8, 0.8)
    track.anchorX = 0
    track.x = -width / 2

    -- Create the filled part of the track
    local filledTrack = display.newRect(sliderGroup, 0, 0, (startValue - minValue) / (maxValue - minValue) * width, height)
    filledTrack:setFillColor(0.3, 0.6, 0.9)
    filledTrack.anchorX = 0
    filledTrack.x = -width / 2

    -- Create the caps
    local leftCap = display.newCircle(sliderGroup, -width / 2, 0, capRadius)
    leftCap:setFillColor(0.3, 0.6, 0.9) -- same color as the filled track
    local rightCap = display.newCircle(sliderGroup, width / 2, 0, capRadius)
    rightCap:setFillColor(0.8, 0.8, 0.8)

    -- Create the thumb
    local thumb = display.newCircle(sliderGroup, 0, 0, thumbRadius * 2)
    thumb.xScale = 0.5
    thumb.yScale = 0.5
    thumb:setFillColor(0.3, 0.6, 0.9)
    thumb.x = (startValue - minValue) / (maxValue - minValue) * width - width / 2

    -- Functions to show and hide the touch overlay
    local showOverlay = function(overlay)
        transition.cancel("moveOverlay")
        transition.to(overlay, {xScale = 0.5, yScale = 0.5, time = 150, tag = "moveOverlay"})
    end

    local hideOverlay = function(overlay)
        transition.cancel("moveOverlay")
        transition.to(overlay, {xScale = 0.1, yScale = 0.1, time = 150, onComplete = function() overlay.isVisible = false end, tag = "moveOverlay"})
    end

    -- Create the touch overlay
    local touchOverlay = display.newCircle(sliderGroup, thumb.x, thumb.y, thumbRadius * 4)
    touchOverlay.xScale = 0.1
    touchOverlay.yScale = 0.1
    touchOverlay:setFillColor(0.3, 0.6, 0.9, 0.3)
    touchOverlay.isVisible = false

    -- Touch event for the thumb
    local function onThumbTouch(event)
        if event.phase == "began" then
            display.getCurrentStage():setFocus(thumb)
            thumb.isFocus = true
            touchOverlay.isVisible = true
            showOverlay(touchOverlay)
        elseif event.phase == "moved" then
            if thumb.isFocus then
                local newX = event.x - sliderGroup.x
                if newX < -width / 2 then
                    newX = -width / 2
                elseif newX > width / 2 then
                    newX = width / 2
                end
                thumb.x = newX
                touchOverlay.x = newX
                filledTrack.width = newX + width / 2
                local value = minValue + (newX + width / 2) / width * (maxValue - minValue)
                onChange(value)
            end
        elseif event.phase == "ended" or event.phase == "cancelled" then
            display.getCurrentStage():setFocus(nil)
            thumb.isFocus = nil
            hideOverlay(touchOverlay)
        end
        return true
    end

    thumb:addEventListener("touch", onThumbTouch)

    -- Function to set the slider value programmatically
    function sliderGroup:setValue(value)
        value = math.max(minValue, math.min(maxValue, value))
        thumb.x = (value - minValue) / (maxValue - minValue) * width - width / 2
        touchOverlay.x = thumb.x
        filledTrack.width = thumb.x + width / 2
        onChange(value)
    end

    -- Function to get the slider value
    function sliderGroup:getValue()
        return minValue + (thumb.x + width / 2) / width * (maxValue - minValue)
    end

    -- Initialize the slider value
    sliderGroup:setValue(startValue)

    return sliderGroup
end

M.drawOutline = function(image)
    if not image.outline then
        image.outline = display.newRect(image.parent, image.x, image.y, image.width + 2, image.height + 2)
        image.outline:setFillColor(0, 0, 0, 0)
        image.outline:setStrokeColor(0.5, 0.5, 0.5)
        image.outline.strokeWidth = 1
        image.outline:toBack()
    end
end
M.removeOutline = function(image)
    if image.outline then
        image.outline:removeSelf()
        image.outline = nil
    end
end

M.PropertiesPanel = display.newRoundedRect(M.propertiesGroup, _W / 2, _H / 2, 210, 180, 5)
M.PropertiesPanel:setFillColor(0.8, 0.8, 0.8, 0.8)
M.PropertiesPanel.x = 15 + M.PropertiesPanel.width / 2
M.PropertiesPanel.y = (_H - 5) - M.PropertiesPanel.height / 2

M.PropertiesPanel:addEventListener(
    "touch",
    function()
        return true
    end
)

local TextOptions = {
    parent = M.propertiesGroup,
    text = "txt",
    x = 0,
    y = 0,
    font = native.systemFont,
    fontSize = 15 * 2
}

M.createmyText = function(name, text, x, y)
    local myText = display.newText(TextOptions)
    myText.x = x
    myText.y = y
    myText.text = text
    myText:setFillColor(0.4)
    myText.xScale = 0.5
    myText.yScale = 0.5
    myText.anchorX = 1
    _G[name] = myText -- Store the text object in a global variable with the given name
end
local properties = {
    {name = "PropertiesXtext", text = " x =", yOffset = 20},
    {name = "PropertiesYtext", text = " y =", yOffset = 40},
    {name = "PropertiesScaleXtext", text = "width =", yOffset = 60},
    {name = "PropertiesScaleYtext", text = "height =", yOffset = 80},
    {name = "PropertiesOpacitytext", text = "alpha =", yOffset = 100},
    {name = "PropertiesRotationtext", text = "rotation =", yOffset = 140},
    {name = "flipXText", text = "flipX", yOffset = 160},
    {name = "flipYText", text = "flipY", yOffset = 160, xOffset = 145}
}

for _, prop in ipairs(properties) do
    local x = prop.xOffset or M.PropertiesPanel.x - M.PropertiesPanel.width / 2 + 70
    local y = M.PropertiesPanel.y - M.PropertiesPanel.height / 2 + prop.yOffset
    M.createmyText(prop.name, prop.text, x, y)
end

-- TextField Factory Function
M.createTextField = function(x, y, width, height, parentGroup)
    local textField = native.newTextField(x, y, width, height)
    parentGroup:insert(textField) -- Insert into the parent group if needed
    return textField
end

M.setButtonTint = function(button, isSelected)
    -- Guard against nil button reference
    if not button then return end

    if isSelected then
        button:setFillColor(1, 0.6, 0) -- Orange tint
    else
        button:setFillColor(1, 1, 1)   -- Neutral tint
    end
end

return M