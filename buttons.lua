--------------------------------------------------------------------------------
-- buttons.lua
--
-- Purpose: build and manage every toolbar button so main.lua only wires
--          callbacks and keeps state.  Usage:
--
--      local Buttons = require("buttons").init({
--          onSave     = handleSave,
--          onLoad     = handleLoad,
--          onExport   = handleExport,
--          onResize   = selectResize,
--          onRotate   = selectRotate,
--          onPan      = onButtonPanTouch,
--          onToTop    = onButtonToTopTouch,
--          onUp       = onButtonUpTouch,
--          onDown     = onButtonDownTouch,
--          onToBottom = onButtonToBottomTouch,
--          onAddNew   = LoadFileFunction,
--      })
--
--  …later…
--      Buttons.slideLayerButtons(show)        -- hide / show layer strip
--      Buttons.setTint(Buttons.Resize, true)  -- convenience tint wrapper
--------------------------------------------------------------------------------
local GUI = require("GUIcontrolFunctions")

local SCALE        = 0.3   -- uniform icon scale
local LAYER_NUDGE  = 16    -- px beyond the right edge when hidden

local M = {}               -- the module table

-- ---------------------------------------------------------------------------
-- Factory: makes one icon button and attaches it to GUI.uiGroup
-- ---------------------------------------------------------------------------
local function create(imagePath, x, y, listener)
    local btn = display.newImage(imagePath)

    -- Fallback if the asset is missing
    if not btn then
        btn = display.newRoundedRect(0, 0, 40, 40, 6)
        btn:setFillColor(0.3, 0.3, 0.3)
    end

    btn.xScale, btn.yScale = SCALE, SCALE
    btn.InitialScaleX      = SCALE
    btn.InitialScaleY      = SCALE
    btn.x, btn.y           = x, y

    if listener then
        btn:addEventListener("touch", function(event)
            if event.phase == "ended" then
                listener(event)
            end
            return true
        end)
    end

    GUI.uiGroup:insert(btn)
    return btn
end

-- ---------------------------------------------------------------------------
-- Public helper: delegate tinting to GUI so callers don’t repeat boiler-plate
-- ---------------------------------------------------------------------------
function M.setTint(btn, state)
    if GUI.setButtonTint then GUI.setButtonTint(btn, state) end
end

-- ---------------------------------------------------------------------------
-- Public constructor: build *all* buttons.  Pass a table of callbacks whose
-- keys are the names listed below.  Returns `M` so callers can do:
--
--      local Buttons = require("buttons").init(callbacks)
-- ---------------------------------------------------------------------------
function M.init(cb)
    -- File actions (top-left)
    M.Save   = create("GFX/save.png",   20, 20,   cb.onSave)
    M.Load   = create("GFX/load.png",   53, 20,   cb.onLoad)
    M.Export = create("GFX/export.png", 86, 20,   cb.onExport)

    -- Tool-mode selectors (centre)
    M.Resize = create("GFX/Cursor.png", (_W/2) - 30, 20, cb.onResize)
    M.Rotate = create("GFX/rotate.png", (_W/2) +   3, 20, cb.onRotate)
    M.Pan    = create("GFX/pan.png",    (_W/2) +  90, 20, cb.onPan)

    -- Layer-ordering strip (right-hand edge — slides with the drawer)
    M.ToTop    = create("GFX/totop.png",     _W - 285, 20, cb.onToTop)
    M.Down     = create("GFX/up_arrow.png",  _W - 252, 20, cb.onDown)
    M.Up       = create("GFX/down_arrow.png",_W - 219, 20, cb.onUp)
    M.ToBottom = create("GFX/tobottom.png",  _W - 186, 20, cb.onToBottom)
    M.AddNew   = create("GFX/addnew.png",    _W - 285, 20, cb.onAddNew)

    ------------------------------------------------------------------------
    --  Alignment & distribution strip (bottom‑centre of the canvas)
    ------------------------------------------------------------------------
    local btnSize = M.Save.width * SCALE   -- visual size of a 0.3‑scaled icon
    local spacing = 3
    local baseY   = _H - btnSize
    local centreX = _W / 2

    -- Vertical‑alignment buttons
    M.AlignVerticalBottom  = create("GFX/button_alignVerticalBottom.png",
                                    centreX - btnSize*3 - spacing*3, baseY,
                                    cb.onAlignVBottom)
    M.AlignVerticalTop     = create("GFX/button_alignVerticalTop.png",
                                    centreX - btnSize*2 - spacing*2, baseY,
                                    cb.onAlignVTop)
    M.AlignVerticalCenter  = create("GFX/button_alignVerticalCenter.png",
                                    centreX - btnSize   - spacing,   baseY,
                                    cb.onAlignVCenter)

    -- Horizontal‑alignment buttons
    M.AlignHorizontalLeft  = create("GFX/button_alignHorizontalLeft.png",
                                    centreX,                         baseY,
                                    cb.onAlignHLeft)
    M.AlignHorizontalRight = create("GFX/button_alignHorizontalRight.png",
                                    centreX + btnSize + spacing,     baseY,
                                    cb.onAlignHRight)
    M.AlignHorizontalCenter= create("GFX/button_alignHorizontalCenter.png",
                                    centreX + btnSize*2 + spacing*2, baseY,
                                    cb.onAlignHCenter)

    -- Distribution buttons
    local distStartX = M.AlignHorizontalCenter.x + btnSize + spacing
    M.DistributeHorizontal = create("GFX/button_horizontalDistribute.png",
                                    distStartX,                      baseY,
                                    cb.onDistributeH)
    M.DistributeVertical   = create("GFX/button_verticalDistribute.png",
                                    distStartX + btnSize + spacing,  baseY,
                                    cb.onDistributeV)

    -- Cache the layer-strip buttons so we can animate them as one
    M._layerStrip = {
        buttons  = { M.AddNew, M.ToTop, M.Down, M.Up, M.ToBottom },
        original = {}
    }
    for i,b in ipairs(M._layerStrip.buttons) do
        M._layerStrip.original[i] = b.x
    end

    return M
end

-- ---------------------------------------------------------------------------
-- Slide the layer-ordering strip on/off screen (called from your drawer toggle)
-- ---------------------------------------------------------------------------
function M.slideLayerButtons(show)
    local screenW = _W
    for i,btn in ipairs(M._layerStrip.buttons) do
        local ox = M._layerStrip.original[i]
        local targetX = show and ox or (screenW + LAYER_NUDGE)
        transition.to(btn, { x = targetX, time = 200 })
    end
end

return M