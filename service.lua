local M = {}

M.GetSystemInfo = function()
    local mySystem = system.getInfo( "platform" )
    print("system is " .. mySystem)
    return mySystem
end

M.GetSystemInfo()

local function doesFileExistSB( fname, path )

    local results = false
   
   -- Path for the file
    local filePath = system.pathForFile( fname, path )
    print("file path is "..filePath)
    if ( filePath ) then
       local file, errorString = io.open( filePath, "r" )
   
       if not file then
           -- Error occurred; output the cause
           print( "File error: " .. errorString )
       else
           -- File exists!
           print( "File found: " .. fname )
           results = true
           -- Close the file handle
           file:close()
       end
    end
   
    return results
end
local function doesFileExist( fname, path )

    local results = false
    -- Path for the file
    local filePath = path..fname
    --print("file path is "..filePath)
    if ( filePath ) then
        local file, errorString = io.open( filePath, "r" )
    
        if not file then
            -- Error occurred; output the cause
            print( "File error: " .. errorString )
        else
            -- File exists!
            print( "File found: " .. fname )
            results = true
            -- Close the file handle
            file:close()
        end
    end
    
    return results
end

M.copyFileToSB = function( srcName, srcPath, dstName, dstPath, overwrite )

    local results = false
    print("file name" .. srcName )
    local fileExists = doesFileExist( srcName, srcPath )
    if ( fileExists == false ) then
        return nil  -- nil = Source file not found
    end
    
    -- Check to see if destination file already exists
    if not ( overwrite ) then
        if ( doesFileExistSB( dstName, dstPath ) ) then
            return 1  -- 1 = File already exists (don't overwrite)
        end
    end
    
    -- Copy the source file to the destination file
    local rFilePath = srcPath..srcName  
    local wFilePath = system.pathForFile( dstName, dstPath )
    
    local rfh = io.open( rFilePath, "rb" )
    local wfh, errorString = io.open( wFilePath, "wb" )
    
    if not ( wfh ) then
        -- Error occurred; output the cause
        native.showAlert("ERROR", "File error: " .. errorString)
        print( "File error: " .. errorString )
        return false
    else
        -- Read the file and write to the destination directory
        local data = rfh:read( "*a" )
        if not ( data ) then
            print( "Read error!" )
            return false
        else
            if not ( wfh:write( data ) ) then
                print( "Write error!" )
                return false
            end
        end
    end
    
    results = 2  -- 2 = File copied successfully!
    
    -- Close file handles
    rfh:close()
    wfh:close()
    
    return results
end


M.copyFileFromSB = function( srcName, srcPath, dstName, dstPath, overwrite )

    local results = false
    
    local fileExists = doesFileExistSB( srcName, srcPath )
    if ( fileExists == false ) then
        return nil  -- nil = Source file not found
    end
    
    -- Check to see if destination file already exists
    if not ( overwrite ) then
        if ( doesFileExist( dstName, dstPath ) ) then
            return 1  -- 1 = File already exists (don't overwrite)
        end
    end
    
    -- Copy the source file to the destination file
    local rFilePath = system.pathForFile( srcName, srcPath )
    local wFilePath = dstPath..dstName
    
    local rfh = io.open( rFilePath, "rb" )
    local wfh, errorString = io.open( wFilePath, "wb" )
    
    if not ( wfh ) then
        -- Error occurred; output the cause
        print( "File error: " .. errorString )
        native.showAlert("ERROR", "File error: " .. errorString)
        return false
    else
        -- Read the file and write to the destination directory
        local data = rfh:read( "*a" )
        if not ( data ) then
            print( "Read error!" )
            return false
        else
            if not ( wfh:write( data ) ) then
                print( "Write error!" )
                return false
            end
        end
    end
    
    results = 2  -- 2 = File copied successfully!
    
    -- Close file handles
    rfh:close()
    wfh:close()
    
    return results
end


    M.getPath = function(str, sep)
        sep = sep or package.config:sub(1,1) -- Get the default separator for the OS
        local pattern = "(.*" .. sep .. ")"
        return str:match(pattern)
    end
    M.get_file_name = function(file)
        return file:match("^.+[\\/](.+)$")
    end

    M.get_file_name_no_extension = function(file)
        -- Match the filename with or without path separators (handles both / and \)
        local filename = file:match("^.+[\\/](.+)$")
        -- Remove the extension
        return filename and filename:match("(.+)%..+$") or file:match("(.+)%..+$")
    end

-- Touch listener for handles to resize the image
-- Function to update the size and position of the selected image based on the handle and movement
M.updateImageSizeAndPosition = function(selectedImage, resizeHandles, handle, dx, dy, proportion, shiftPressed, controlPressed)
    -- Get the rotation angle in radians
    local angle = math.rad(selectedImage.rotation)
    local cosAngle = math.cos(angle)
    local sinAngle = math.sin(angle)

    -- Calculate the local dx and dy in the rotated coordinate system
    local localDx = dx * cosAngle + dy * sinAngle
    local localDy = dy * cosAngle - dx * sinAngle

    local newWidth, newHeight

    if controlPressed then
        -- Calculate the distance from the center of the image to the mouse cursor
        local centerX, centerY = selectedImage.x, selectedImage.y
        local distanceX = (handle.startX + dx) - centerX
        local distanceY = (handle.startY + dy) - centerY

        -- Calculate the initial distances of the handle from the center
        local initialDistanceX = handle.startX - centerX
        local initialDistanceY = handle.startY - centerY

        -- Calculate the scaling factors
        local scaleX = (initialDistanceX ~= 0) and (distanceX / initialDistanceX) or 1
        local scaleY = (initialDistanceY ~= 0) and (distanceY / initialDistanceY) or 1

        -- Apply the scaling factors to calculate new width and height
        newWidth = handle.startWidth * scaleX
        newHeight = handle.startHeight * scaleY

        -- Apply proportional scaling if shift is pressed
        if shiftPressed then
            if math.abs(scaleX) > math.abs(scaleY) then
                newWidth = handle.startWidth * scaleX
                newHeight = newWidth / proportion
            else
                newHeight = handle.startHeight * scaleY
                newWidth = newHeight * proportion
            end
        end

        -- Update the position of the handle being manipulated to stay under the cursor
        handle.x = handle.startX + dx
        handle.y = handle.startY + dy

        -- Ensure consistent scaling factors
        if scaleX < 0 then
            selectedImage.xScale = -math.abs(selectedImage.xScale)
        else
            selectedImage.xScale = math.abs(selectedImage.xScale)
        end

        if scaleY < 0 then
            selectedImage.yScale = -math.abs(selectedImage.yScale)
        else
            selectedImage.yScale = math.abs(selectedImage.yScale)
        end
    else
        if handle == resizeHandles.topLeft then
            if shiftPressed then
                newWidth = handle.startWidth - localDx
                newHeight = newWidth / proportion
                localDx = handle.startWidth - newWidth
                localDy = handle.startHeight - newHeight
            else
                newWidth = handle.startWidth - localDx
                newHeight = handle.startHeight - localDy
            end
            selectedImage.x = handle.startImageX + (localDx * cosAngle - localDy * sinAngle) / 2
            selectedImage.y = handle.startImageY + (localDx * sinAngle + localDy * cosAngle) / 2
        elseif handle == resizeHandles.topRight then
            if shiftPressed then
                newWidth = handle.startWidth + localDx
                newHeight = newWidth / proportion
                localDx = newWidth - handle.startWidth
                localDy = handle.startHeight - newHeight
            else
                newWidth = handle.startWidth + localDx
                newHeight = handle.startHeight - localDy
            end
            selectedImage.x = handle.startImageX + (localDx * cosAngle - localDy * sinAngle) / 2
            selectedImage.y = handle.startImageY + (localDx * sinAngle + localDy * cosAngle) / 2
        elseif handle == resizeHandles.bottomLeft then
            if shiftPressed then
                newHeight = handle.startHeight + localDy
                newWidth = newHeight * proportion
                localDx = handle.startWidth - newWidth
                localDy = newHeight - handle.startHeight
            else
                newWidth = handle.startWidth - localDx
                newHeight = handle.startHeight + localDy
            end
            selectedImage.x = handle.startImageX + (localDx * cosAngle - localDy * sinAngle) / 2
            selectedImage.y = handle.startImageY + (localDx * sinAngle + localDy * cosAngle) / 2
        elseif handle == resizeHandles.bottomRight then
            if shiftPressed then
                newWidth = handle.startWidth + localDx
                newHeight = newWidth / proportion
                localDx = newWidth - handle.startWidth
                localDy = newHeight - handle.startHeight
            else
                newWidth = handle.startWidth + localDx
                newHeight = handle.startHeight + localDy
            end
            selectedImage.x = handle.startImageX + (localDx * cosAngle - localDy * sinAngle) / 2
            selectedImage.y = handle.startImageY + (localDx * sinAngle + localDy * cosAngle) / 2
        end
    end

    -- Apply the new dimensions
    selectedImage.width = math.abs(newWidth)
    selectedImage.height = math.abs(newHeight)
end
M.buttonTouch = function(onRelease)
    return function(self, event)
        -- Defensive guard for nil or non-touch calls
        if not event or not event.phase then
            if onRelease then onRelease() end
            return true
        end
        if event.phase == "began" then
            display.getCurrentStage():setFocus(self, event.id)
            -- Optional visual feedback (shrink):
            self.xScale = (self.InitialScaleX or 1) - 0.05
            self.yScale = (self.InitialScaleY or 1) - 0.05
            self.isFocus = true
        elseif self.isFocus and event.phase == "ended" then
            -- Restore scale
            transition.to(self, {
                xScale     = self.InitialScaleX or 1,
                yScale     = self.InitialScaleY or 1,
                time       = 120,
                transition = easing.outBack
            })
            display.getCurrentStage():setFocus(self, nil)
            self.isFocus = false
            if onRelease then onRelease() end
        end
        return true
    end
end
return M