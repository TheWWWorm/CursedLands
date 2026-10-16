# Cursed Lands wiki

<!-- impeccable:product-schema 1 -->

## Platform

web

The same encyclopedia also has a native Godot interface within the game.

## Users

Cursed Lands players looking up equipment, quests, places and mechanics while playing, or preparing a character and crafting plan outside the game.

## Product Purpose

Make the website and in-game wiki useful, attractive and easy to navigate. The user requested better search, acquisition and usage links, gameplay entry points, maps and quest guides, shareable crafting and character plans, and practical mechanics explanations.

## Operating Context

The website is a static, account-free reference. The native wiki reads the installed campaign and active data mods without changing the current game. Both cover the base campaign and Lost in Astral. Existing item and spell constructors use the game's calculations.

## Capabilities and Constraints

Player-visible text is required in English, Russian and German. Preserve original localized names and artwork, existing article addresses, campaign selection and constructor behavior. Distinguish authored possibilities from guaranteed drops, current stock, or current quest progress. Links that share a build must contain its data. No subagents or delegation.

## Brand Commitments

The user chose a modern fantasy field guide: readable, illustrated, with restrained parchment and dark metal accents. Their Civilopedia reference calls for strong serif headings, quiet navigation and generous space around the article. The rejected flat, dense first pass is an anti-reference. Character, item and
spell builders must use the actual game camp layout and original artwork. They
scale with the viewport; equipment selection keeps its item and actions visible
while the catalogue scrolls.
Wide layouts put item/spell selection in the available space beside the camp,
keeping character skills visible. Named item, spell and character snapshots can
be saved locally, reopened, and reused; sharing remains available through links.
Browser and native libraries are separate and do not change gameplay saves.

## Content Visibility

The user chose to show all quest hints, hidden locations and rewards by default. Filters and collapsible sections may help navigation without hiding this information on first use.

## Evidence on Hand

`docs/wiki.md`, `game/src/game/wiki_catalog.gd`, installed game databases and original text archives, and `public/wiki/images` supply real content and artwork. `web/wiki` owns the website UI; `game/src/ui/wiki_panel.gd` owns the native UI.

Maps open with exits and quest areas. The creature layer is optional, following the user’s latest feedback that maps were too crowded; nearby markers cluster at the displayed zoom level. This is a map-density choice, not a spoiler gate.
