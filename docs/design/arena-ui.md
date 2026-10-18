# Autochess interface

Current surface brief, 18 October 2026. Preparation emphasizes readable choices;
combat emphasizes the battlefield and its result. Keep the original creatures,
serif headings, bronze accents and snowy courtyard.

## Persistent controls

- Top: animated original recruits with price, copy progress, stars and alliance
  marks. The shop sells only one-star forms for 1–5 gold. Tier-four and tier-five
  figures have rarity glow. Refresh and the level/XP ring remain beside the shelf.
- Left: friendly damage rows with a 32-pixel native portrait, name, stars, value
  and proportional bar. Rows sort by damage; casualties retain their contribution.
  This block and the alliance grid have **no background or outer border**. Fine
  text outlines maintain contrast against terrain. Individual alliance icons
  retain their colored state and threshold pips, with full details on hover.
- Right: round clock, menu/shop controls, and compact player standings. A grid
  button opens the nine-board overview. Scouting retains the current camera pose.
  Creature hover details temporarily occupy this space, including for eliminated
  spectators. Inspecting does not grant shopping or formation permissions.
- Bottom: army/reserve counts, original-model reserves, income, gold, health and
  battle controls. Selecting a unit exposes its current sale return. Online prices
  are authoritative quotes, checked again when the host accepts the sale.

All ninety portraits are direct low-resolution renders of the existing native
figures, cropped toward the head where the rig provides one. Preserve original
colors, clothing and silhouettes; no generated replacement artwork is used.

## Feedback and transitions

A brief central bronze notice announces each round and its income. The final ten
preparation seconds use a large countdown. Victory, draw and defeat use the same
visual language, with health lost and the next-round countdown. Losing health is
charged immediately on the board result; other simultaneous battles continue.
Shared income and places wait for every participant. Repeated results do not
charge twice. Battles last at most 1:30 of simulated time.

Purchases never select a creature automatically. An upgrade retains the deployed
copy’s position and shows the complete native before/after figures, stats, sound
and highlight. In online play this notice is triggered by the host-confirmed army
change. It does not wait for another purchase. The notice sits beside the damage
block, and can be covered by menus or overview without consuming its reading time.
Survivors return to native idle clips when combat ends.

## Camera and input

WASD moves relative to the camera. Q/E turns continuously. Right drag changes yaw
and pitch; a stationary right click retains cancel behavior. Middle drag turns,
Alt + middle drag tilts, and Shift + middle drag pans. The wheel zooms, including
fractional wheel events. The existing modern-camera speed and inversion settings
apply. Home is the explicit reset. Round starts and board changes preserve the
chosen view. Camera speed follows real time at 1× and 2× combat speed.

Menus, wiki, text editing, overview and application focus loss clear held camera
input. Body geometry and health labels remain hover/picking targets. All labels,
dynamic descriptions, help and errors use English, Russian and German. HUD scale
and layout are checked in all three languages.

## Visual reference and limits

The supplied Underlords video informed the compact damage rows, alliance icons,
large round/countdown notice and clear loss feedback. Its character art, item
system and rectangular HUD panels were not copied. Original native figures and
this game’s typography remain the visual source.

See [the current validation record](../validation/allods-challenge-2026-10-18.md).
Earlier screenshots and reports describe earlier builds.
