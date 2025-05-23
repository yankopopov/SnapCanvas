-- Checkbox.lua

-- Constants
local uncheckedImage = "GFX/checkOFF.png"
local checkedImage = "GFX/checkON.png"

-- Checkbox Class
local Checkbox = {}
Checkbox.__index = Checkbox

function Checkbox:new(params)
    local self = setmetatable({}, Checkbox)
    
    self.id = params.id
    self.x = params.x
    self.y = params.y
    self.parentGroup = params.parentGroup
    self.isChecked = false
    
    self.displayObject = display.newImage(self.parentGroup, uncheckedImage)
    self.displayObject.x = self.x
    self.displayObject.y = self.y
    self.displayObject:scale(0.2, 0.2)
    self.displayObject.id = self.id
    self.displayObject.checkbox = self -- Reference back to the checkbox object
    
    self.displayObject:addEventListener("touch", function(event) return self:toggleCheckbox(event, params.getSelectedImage()) end)
    
    return self
end

function Checkbox:setCheckedState(state, selectedImage)
    self.isChecked = state
    local imagePath = state and checkedImage or uncheckedImage
    self.displayObject.fill = {type = "image", filename = imagePath}
    
    if selectedImage then
        if state then
            if self.id == "checkboxFlipX" then
                selectedImage.xScale = -1
            else
                selectedImage.yScale = -1
            end
        else
            if self.id == "checkboxFlipX" then
                selectedImage.xScale = 1
            else
                selectedImage.yScale = 1
            end
        end
    end
end

function Checkbox:toggleCheckbox(event, selectedImage)
    local checkbox = event.target.checkbox
    if event.phase == "ended" and selectedImage then
        checkbox:setCheckedState(not checkbox.isChecked, selectedImage)
    end
    return true
end

return Checkbox