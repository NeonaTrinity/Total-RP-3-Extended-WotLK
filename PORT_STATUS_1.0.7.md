# Total RP 3 Extended WotLK - Original 1.0.7 Feature Parity

This port uses **Total RP 3 Extended 1.0.7 (2018-01-31)** as the original feature baseline.
The goal is to restore that original feature set on WoW 3.3.5a before selectively importing later Extended features.

Status meanings:
- **Verified**: exercised successfully in live 3.3.5a testing.
- **Present / partial**: original code is present and loads, but the full feature path has not been exhaustively live-tested or still has known compatibility work.
- **Deferred compatibility**: original feature exists, but a later-client dependency still needs a faithful Wrath implementation.

## Runtime / player-facing systems

| Original 1.0.7 system | Alpha 29 status | Notes |
|---|---|---|
| Custom RP items + RP inventory | Verified | Core inventory, item creation/use and container behavior have been live-tested across prior alphas. |
| Documents/books | Verified | Reading and creation/editing paths have been exercised; WotLK parchment/font compatibility is active. |
| Wearable RP item placement | Present / partial | Original wearable locator is restored; model controls use Wrath compatibility behavior. |
| RP item trading / object download | Present / partial | Stock WotLK TRP3 object transport is reused; custom-object message-ID compatibility is present. Continue multiplayer testing. |
| Ground drops | Verified | Original local-drop behavior is preserved. Ground drops are local to the dropper by original 1.0.7 design. |
| Multiplayer stashes | Verified / calibrating | Works in Orgrimmar. Alpha 27 fixed unsafe cast IDs and calibrates 15 original yards to 45 current map units based on Orgrimmar only; other maps remain observational. |
| Inspect another player's Extended inventory | Present / partial | Original separate inspection window/action is restored; continue multiplayer verification. |
| Security levels / secured effects | Present / partial | Original security code is present; effect-by-effect runtime coverage is not yet exhaustive. |
| Sounds / local sounds / music history | Present / partial | WotLK sound-history and local-sound compatibility exists; distance depends on the same map-coordinate approximation under observation. |
| Casting / Arcano-Casino | Present / partial | WotLK casting-bar compatibility was restored; more scripted cast effects still need live coverage. |
| Item links | Present / partial | Hidden addon metadata path and fixed-duration tooltips are implemented; SAY/YELL cannot carry hidden recipient metadata on Wrath. |

## Creation Tools / scripting

| Original 1.0.7 system | Alpha 29 status | Notes |
|---|---|---|
| Quick / Normal / Expert item editors | Present / partial | Core creation/edit flows work; UI compatibility cleanup continues. |
| Workflows | Present / partial | Engine is original 1.0.7. Editor/modal/listbox compatibility has been heavily restored; effect-by-effect testing continues. |
| Conditions + Tests + operands | Present / active testing | Alpha 27 hardens left/right argument Confirm handling; Alpha 29 explicitly contains all three Test Editor selectors plus Configure/Preview controls inside the Wrath editor bounds. |
| Effects | Present / partial | Original effect registry is present. Individual effects must be verified on 3.3.5 APIs. |
| Variables + interpolation | Present / partial | Original 1.0.7 scripting code, including campaign variable interpolation, is present. |
| Companion effects | Present / partial | Wrath mount/critter APIs are emulated. Alpha 28 restores the missing Summon Mount selection browser using the player's actual Wrath mount collection. |
| Import / Export companion addon | Present / partial | Original totalRP3_Extended_ImpExport is restored as a third addon; full round-trip testing still recommended. |

## Campaign / quest / narrative systems

| Original 1.0.7 system | Alpha 29 status | Notes |
|---|---|---|
| Campaign creation/copy/activation | Present / partial | Original code is present and entry points are restored. |
| Quest log / quests / steps / objectives | Present / partial | Original engine is present; workflow-driven progression still needs systematic live testing. |
| Campaign Actions (Look/Inspect, Talk, Listen, Action) | Present / active testing | Macro/editor compatibility restored. Alpha 29 restores the original 1.0.7 full-banner click target so right-click Edit/Remove/Edit condition works over the whole added-action banner. Edit reloads the same Action Type + Linked Workflow options used at creation. |
| Customized NPCs | Present / partial | Wrath GUID lookup and numeric/string NPC-key compatibility restored; target-ID helper restored. |
| 3D dialogues + choices | Present / partial | Dialogue engine is present. Exact original model scaling/animation fidelity is still deferred to TRP-Anim-DB work below. |
| Cutscene creation tools | Present / partial | Original files are present; model/camera fidelity needs more testing. |

## Deferred original dependency: TRP-Anim-DB

Original Extended 1.0.7 references the git submodule **TRP-Anim-DB @ 33f5da2**. The downloadable 1.0.7 ZIP contains only the empty submodule directory, so early WotLK alphas installed neutral library fallbacks.

The exact historical revision has now been identified and remains available. It contains:
- AnimDB.lua (animation duration + punctuation-to-dialogue-animation mappings)
- ScalingDB.lua (paired-model scale + placement data)
- TRP-Anim-DB.xml

It is **not yet activated in Alpha 29** because the 2018 library identifies models by later FileData IDs and calls later model-control helpers (`InitializeCamera`, `SetHeightFactor`, `SetTargetDistance`, `SetAnimation`). Wrath PlayerModel instead exposes legacy mechanisms such as `SetSequence`, `SetFacing` and `SetPosition`. The next restoration must bridge model identity and camera placement instead of blindly copying later runtime calls.

## Source completeness

Every normal file contained in the supplied original 1.0.7 ZIP exists in the WotLK port. Alpha 29 adds only compatibility/support files; it does not delete original Extended modules. The historical TRP-Anim-DB git submodule is the one missing source dependency and is tracked above.

Stock `totalRP3` and `totalRP3_Data` remain separate and unmodified on disk.
