-- globals.lua  ──────────────────────────────────────────
-- Central shared-state table.  Extend here instead of making new globals.
local G = {
    -- Modifier-key state
    shiftPressed = false,

    -- Selection & handles
    selectedImage       = nil,
    multiSelectedImages = {},          -- [img] = true
    handles             = { resize = {}, rotate = {}, group = {} },

    -- UI mode enum: 1 = resize, 2 = rotate, 3 = pan (0 = none)
    mode = 1,
}

return G