---
name: Cursed Lands field guide
description: A readable illustrated reference for equipment, quests and character planning.
colors:
  forest: "#243d32"
  paper: "#f3efe3"
  sheet: "#fcfaf3"
  ink: "#273528"
  muted: "#626b59"
  line: "#d6d3c2"
  brass: "#a66b28"
  selected: "#e2e6d4"
  danger: "#943f30"
  native-frame: "#1d2b23"
  native-paper: "#f1ebdc"
typography:
  display:
    fontFamily: "FieldSerif, serif"
    fontSize: "clamp(34px, 3.5vw, 50px)"
    fontWeight: 400
    lineHeight: 1.12
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "FieldSerif, serif"
    fontSize: "29px"
    fontWeight: 400
    lineHeight: 1.2
  body:
    fontFamily: "FieldSans, sans-serif"
    fontSize: "17px"
    lineHeight: 1.6
  label:
    fontFamily: "FieldSans, sans-serif"
    fontSize: "14px"
    fontWeight: 700
rounded:
  control: "5px"
  illustration: "12px"
spacing:
  tight: "8px"
  related: "16px"
  group: "24px"
  section: "38px"
components:
  button-primary:
    backgroundColor: "{colors.forest}"
    textColor: "#faf5df"
    rounded: "{rounded.control}"
    padding: "6px 12px"
  button-secondary:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "8px 12px"
  input:
    backgroundColor: "{colors.sheet}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    padding: "8px 12px"
    height: "40px"
---

# Design System: Cursed Lands field guide

## Overview

**Creative North Star: "Modern fantasy field guide"**

Readable, illustrated and restrained. Original game artwork supplies the fantasy
setting; serif headings and pale reading surfaces establish the field guide.
Dark navigation frames the content without competing with it.

**Key Characteristics:**
- Clear serif hierarchy with familiar sans serif controls.
- Original illustrations with breathing room.
- Quiet navigation, spacious reading and compact factual tables.

## Colors

Forest is the primary navigation and action color. Brass marks focus and small
navigation accents. Paper and sheet distinguish the page and reading surface;
ink and muted text preserve readable hierarchy. Selected rows use a pale green.
The native interface uses a darker frame and slightly deeper paper to remain
legible against the game behind it.

**The Paper Rule.** Paper is a reading surface, not a decorative texture overlay.

## Typography

FieldSerif is the shipped Liberation Serif; FieldSans is Liberation Sans, with
a separate bold face. Fonts are self-hosted with their license. Native controls
use the same font families, with sizing adjusted to the game viewport.

**The Reading Rule.** Serif headings carry the hierarchy; body text and controls
use the sans serif. Keep prose around 72 characters per line and allow translated
headings to wrap. Use tabular numerals in website statistics.

## Layout

The website uses a persistent sidebar beside the reading pane, becoming a browse
control below 760 pixels. The intermediate sidebar narrows at 1050 pixels. The
native interface changes to separate browse/article views below 850 scaled
pixels. The article keeps its space; illustrations and construction controls
can be opened separately in that native compact view.

**The Space Rule.** Keep related controls together and leave more space above a
section heading than below it. Tables and clear rows carry reference information.

## Elevation & Depth

Reading pages use tonal surfaces and borders. Planning and crafting deliberately
use the original game camp textures, stone slot frames, serif labels and assembly
positions. These assets are the user-requested visual authority for those tools.
A compact equipment drawer may use a soft shadow to separate it from the camp.

## Shapes

Controls have small corner radii. Illustration wells have gentler corners.
Map dots and clusters are circular because they represent positions and groups;
counts denote the number of positions rather than internal identifiers.

## Components

Buttons use sentence case and concrete actions, with a forest primary action
and a pale secondary treatment. Focus has a visible brass outline. Inputs share
the control surface and border; selection and caret colors belong to the palette.
Hover transitions are brief and respect reduced-motion preferences.

The camp workspace scales to the available viewport while preserving its 4:3
composition: ready slots above, the character or assembly in the center, stone
panels at each side, and spells or runes below. It has no fixed desktop pixel cap.
On wide windows, item and spell selectors occupy a separate rail beside the camp.
The character's attributes and skills remain visible. Equipment selection uses a
scrolling catalogue and a pinned footer for the selected item, material and actions.
Search preserves the selection. Narrow windows use a bounded drawer; short wide
windows give the rail enough height for its list and footer. Close and Escape
return focus to the original slot. Saved recipes are grouped beside current-build
entries. A searchable saved library keeps names, type, campaign and actions clear.

Search results separate the article name from category and context, using a
selected fill, not dense concatenated text. Website thumbnails reuse article art.
Campaign tabs use a straight underline. Material variants use a labeled select.

Map markers distinguish exits, quest areas and creatures through labels as well
as colors. Exits use green directional arrows. Marker selection opens a bounded
popup beside the point, with clickable named destinations. Difficulty values use
labeled Easy / Hard pairs only where values change; unchanged values appear once.
Natural armor retains its separate damage types.

## Do's and Don'ts

### Do:
- Do preserve original artwork and localized names.
- Do give articles enough room to read in English, Russian and German.
- Do use labeled controls and visible keyboard focus.
- Do cluster crowded map points without losing their named destinations.

### Don't:
- Don't squeeze navigation, an article and construction tools into a phone column.
- Don't show internal object identifiers as map markers or article names.
- Don't replace useful content with decorative tiles or invented fantasy emblems.

On wide layouts the camp defines the shared grid-row height. The selector stretches to exactly that height, with only its results scrolling; it must not introduce a separate minimum or viewport height.
