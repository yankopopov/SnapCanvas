SnapCanvas
Version: 0.9a
Platform: Solar2D (Corona Simulator)
License: Apache License 2.0

⸻

Overview
SnapCanvas is an experimental image-layout and manipulation editor for Solar2D. 
It provides a visual workspace for importing PNG assets in batches; positioning, resizing, rotating, aligning and distributing them; 
persisting your work and reloading it without duplication; and exporting ready-to-use Lua and asset folders for seamless integration into any other Solar2D project.

Features
• Custom loader dialog via the plugin.tinyfiledialogs for batch PNG import
• Interactive placement: drag images on the canvas to move them
• Single-image handles: green-square corners for resize, red-circle corners for rotate
• Shift-click multi-select on canvas or in the list panel, with a red group bounding box and per-corner group handles for collective transforms
• Always-visible properties panel showing numeric X, Y, Width, Height (plus Rotation & Opacity for single images) with live updates
• Align controls for snapping top, bottom, left, right edges or vertical/horizontal centers
• Distribute controls for evenly spacing image centers horizontally or vertically
• Save and load full workspaces (images, transforms, layer order) 
• Export generates a “GFX” folder of assets plus image_data.lua and loader.lua for reuse

Getting Started
	1.	Download or clone the SnapCanvas repository to your computer.
	2.	Open Solar2D’s Corona Simulator.
	3.	In the simulator, choose File → Open, navigate to the SnapCanvas folder, and select main.lua.
	4.	SnapCanvas launches immediately—no additional setup required.

Workflow
	1.	Add Images: click “Add New” or the “+” icon to select PNG files. Display in your workspace with the "load button" next to the file name
	2.	Move & Place: drag images on the canvas.
	3.	Single-Image Transform: click an image to select it, then drag green handles to resize or red handles to rotate.
	4.	Multi-Select: hold Shift and click images on the canvas or in the list to group-select; use the red box handles for group transforms.
	5.	Edit Properties: adjust numeric X, Y, Width, Height (and Rotation & Opacity for single images) in the panel.
	6.	Align & Distribute: use the bottom toolbar to snap edges or space centers evenly.
	7.	Save/Load: persist your workspace and reload it later with transforms re-applied.
	8.	Export: generate a GFX/ directory plus image_data.lua to use with loader.lua for your Solar2D projects.

loader.lua
The loader.lua script re-creates an exported SnapCanvas layout in any Solar2D project. By default it expects image_data.lua in the same folder. Usage examples:
• local loader = require("loader")
• loader.load() — loads image_data.lua into the current stage
• or loader.load(myGroup, "image_data") — loads into your own display group

After loading, you can access sprites by:
• loader.all — ordered array of sprites
• loader.get(1) or loader.get("Name") — by index or export-name
• loader.each() — iterate all sprites in draw order

Loading an Export
	1.	Copy the exported GFX/ folder and loader.lua (and image_data.lua) into your Solar2D project directory.
	2.	In your main.lua, require loader and call loader.load().
	3.	Retrieve sprites via loader.get() or by iterating loader.each().

Contributing
SnapCanvas is experimental—your feedback and pull requests are welcome. 
To contribute, fork the repo, create a feature branch, commit your changes, push, and open a pull request.

License
This project is licensed under the Apache License 2.0. See the LICENSE file for full terms.
