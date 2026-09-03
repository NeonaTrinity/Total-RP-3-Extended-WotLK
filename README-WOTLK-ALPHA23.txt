TRP3 Extended WotLK Alpha 23
================================

Workflow/editor fixes:
- Fixes closeOperandLayer Lua scope error by forward-declaring the local function.
- Workflow rows now reserve the left half for "N. Effect: Type" and the right
  half for the live effect preview (for example "Adds 1x [Item]").
- Right-clicking a workflow element now has an explicit Edit action that opens
  the same element-specific property editor as normal left-click editing.
- Effect-condition editing now lives inside the same visible dark modal host used
  by Add Element. Inner X closes the condition panel; outer X returns to workflow.

Campaign Actions:
- Add/Edit Action editor is centered inside the Actions panel instead of using the
  old off-screen hover-frame positioning.
- Action type/workflow dropdowns are anchored inside the editor box.
- Right-click action menu exposes Edit and Remove directly; Edit reopens the same
  action type/workflow controls used at creation.
- Action-condition editing now gets its own visible dark modal host with outer X.

Base totalRP3 / totalRP3_Data are not included or modified.
