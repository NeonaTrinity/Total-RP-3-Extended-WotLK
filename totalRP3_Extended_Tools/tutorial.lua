----------------------------------------------------------------------------------
-- Total RP 3: Extended features
--	---------------------------------------------------------------------------
--	Copyright 2015 Sylvain Cossement (telkostrasz@totalrp3.info)
--
--	Licensed under the Apache License, Version 2.0 (the "License");
--	you may not use this file except in compliance with the License.
--	You may obtain a copy of the License at
--
--		http://www.apache.org/licenses/LICENSE-2.0
--
--	Unless required by applicable law or agreed to in writing, software
--	distributed under the License is distributed on an "AS IS" BASIS,
--	WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--	See the License for the specific language governing permissions and
--	limitations under the License.
----------------------------------------------------------------------------------

local Globals, Events, Utils, EMPTY = TRP3_API.globals, TRP3_API.events, TRP3_API.utils, TRP3_API.globals.empty;
local wipe, pairs, strsplit, tinsert, type, _G = wipe, pairs, strsplit, tinsert, type, _G;
local loc = TRP3_API.locale.getText;

local ToolFrame, buttonWidget;

local currentList = {};
local currentStructure;

local function hideTutorialVisuals()
	if ToolFrame then
		ToolFrame.tutorialhide:Hide();
	end
	if buttonWidget and buttonWidget.boxHighlight then
		buttonWidget.boxHighlight:Hide();
	end
	TRP3_API.navigation.hideTutorialTooltip(buttonWidget);
end

local function onStep(step)
	if not currentStructure or not currentStructure[step] then return; end
	local stepInfo = currentStructure[step];
	local cancel = false;

	local cancelMessage;
	if stepInfo.callback then
		cancel, cancelMessage = stepInfo.callback();
	end

	if cancel then
		ToolFrame.tutoframe:Hide();
		hideTutorialVisuals();
		Utils.message.displayMessage(cancelMessage, 4);
		return;
	end

	local frame = stepInfo.box;
	if frame and type(frame) == "string" then
		frame = _G[stepInfo.box];
	end

	buttonWidget.boxHighlight:ClearAllPoints();
	if frame and frame.IsVisible and frame:IsVisible() then
		buttonWidget.boxHighlight:SetAllPoints(frame);
	else
		buttonWidget.boxHighlight:SetAllPoints(ToolFrame);
	end
	buttonWidget.boxHighlight:Show();

	buttonWidget:ClearAllPoints();
	buttonWidget:SetPoint(stepInfo.anchor or "CENTER", buttonWidget.boxHighlight, stepInfo.anchor or "CENTER", stepInfo.x or 0, stepInfo.y or 0);

	TRP3_API.navigation.hideTutorialTooltip(buttonWidget);
	buttonWidget.arrow = stepInfo.arrow or "RIGHT";
	buttonWidget.text = loc(stepInfo.text or "");
	buttonWidget.textWidth = stepInfo.textWidth or 220;
	TRP3_API.navigation.showTutorialTooltip(buttonWidget);

	ToolFrame.tutoframe.previous:Enable();
	if step == 1 then
		ToolFrame.tutoframe.previous:Disable();
	end
	ToolFrame.tutoframe.next:Enable();
	if step == #currentStructure then
		ToolFrame.tutoframe.next:Disable();
	end

	ToolFrame.tutoframe.currentStep = step;
end

local function startTutorial(step)
	if ToolFrame.tutoframe:IsVisible() then
		ToolFrame.tutoframe:Hide();
		hideTutorialVisuals();
	else
		if not currentStructure or #currentStructure == 0 then return; end
		ToolFrame.tutoframe:Show();
		ToolFrame.tutorialhide:Show();
		TRP3_API.ui.listbox.setupListBox(ToolFrame.tutoframe.step, currentList, onStep, nil, 200, true);
		ToolFrame.tutoframe.step:SetSelectedValue(step or 1);
		ToolFrame.tutoframe:SetFrameLevel(ToolFrame:GetFrameLevel() + 100);
		ToolFrame.tutorialhide:SetFrameLevel(ToolFrame:GetFrameLevel() + 50);
	end
end

function TRP3_ExtendedTutorial.loadStructure(structure)
	currentStructure = structure;
	if not structure then
		ToolFrame.tutorial:Hide();
		return;
	end

	wipe(currentList);
	for index, info in pairs(currentStructure) do
		tinsert(currentList, {index .. " - " .. loc(info.title or ""), index});
	end

	ToolFrame.tutorial:Show();
	ToolFrame.tutorial:SetFrameLevel(ToolFrame:GetFrameLevel() + 100);
end

function TRP3_ExtendedTutorial.init(toolFrame)
	ToolFrame = toolFrame;

	TRP3_API.ui.tooltip.setTooltipAll(ToolFrame.tutorial, "TOP", 0, 0, loc("UI_TUTO_BUTTON"), loc("UI_TUTO_BUTTON_TT"));
	ToolFrame.tutoframe.title:SetText(loc("TU_TITLE"));
	ToolFrame.tutorial:SetScript("OnClick", function()
		startTutorial(1);
	end);

	ToolFrame.tutoframe.next:SetText(">");
	ToolFrame.tutoframe.next:SetScript("OnClick", function()
		ToolFrame.tutoframe.step:SetSelectedValue((ToolFrame.tutoframe.currentStep or 1) + 1);
	end);

	ToolFrame.tutoframe.previous:SetText("<");
	ToolFrame.tutoframe.previous:SetScript("OnClick", function()
		ToolFrame.tutoframe.step:SetSelectedValue(math.max(1, (ToolFrame.tutoframe.currentStep or 1) - 1));
	end);

	ToolFrame.tutoframe.close:SetScript("OnClick", function()
		ToolFrame.tutoframe:Hide();
		hideTutorialVisuals();
	end);

	-- WotLK replacement for the later TRP3_TutorialButton template.
	buttonWidget = CreateFrame("Frame", "TRP3X_ExtendedTutorialAnchor", UIParent);
	buttonWidget:SetWidth(2);
	buttonWidget:SetHeight(2);
	buttonWidget:SetFrameStrata("TOOLTIP");
	buttonWidget:EnableMouse(false);

	local highlight = CreateFrame("Frame", "TRP3X_ExtendedTutorialHighlight", UIParent);
	highlight:SetFrameStrata("DIALOG");
	highlight:SetFrameLevel(ToolFrame:GetFrameLevel() + 90);
	highlight:EnableMouse(false);

	local top = highlight:CreateTexture(nil, "OVERLAY");
	top:SetTexture(1, 0.82, 0, 0.95);
	top:SetHeight(2);
	top:SetPoint("TOPLEFT");
	top:SetPoint("TOPRIGHT");

	local bottom = highlight:CreateTexture(nil, "OVERLAY");
	bottom:SetTexture(1, 0.82, 0, 0.95);
	bottom:SetHeight(2);
	bottom:SetPoint("BOTTOMLEFT");
	bottom:SetPoint("BOTTOMRIGHT");

	local left = highlight:CreateTexture(nil, "OVERLAY");
	left:SetTexture(1, 0.82, 0, 0.95);
	left:SetWidth(2);
	left:SetPoint("TOPLEFT");
	left:SetPoint("BOTTOMLEFT");

	local right = highlight:CreateTexture(nil, "OVERLAY");
	right:SetTexture(1, 0.82, 0, 0.95);
	right:SetWidth(2);
	right:SetPoint("TOPRIGHT");
	right:SetPoint("BOTTOMRIGHT");

	highlight:Hide();
	buttonWidget.boxHighlight = highlight;

	ToolFrame.tutoframe:Hide();
	ToolFrame.tutorialhide:Hide();

	ToolFrame:SetScript("OnHide", function()
		ToolFrame.tutoframe:Hide();
		hideTutorialVisuals();
	end);
end
