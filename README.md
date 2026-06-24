# Unbunk Utility

A comprehensive combat utility addon for World of Warcraft Retail that keeps you
informed during fights — healer range, deaths, cooldowns, battle resurrections,
consumables and more, through customizable on-screen alerts and icons.

As of **5.0.0**, Unbunk Utility is built on Blizzard's **Cooldown Manager (CDM)**:
instead of drawing its own frames, it reuses, resizes and restyles the game's
native cooldown icons and bars — and lets you build your own.

## Requirements

- World of Warcraft Retail (Interface `120007`).
- Uses the built-in Cooldown Manager for most of its display.

## Installation

- **CurseForge** — search for *Unbunk Utility* and install via the app, or
- **Manual** — drop the `UnbunkUtility` folder into
  `World of Warcraft/_retail_/Interface/AddOns/`, then `/reload`.

Open the settings with `/ubu`.

## What's new in 5.0.0

A ground-up rework around the Cooldown Manager, plus a deep performance pass
(shared aura + timer engines) that makes the addon run much lighter, especially
in raids. Existing settings migrate automatically on first login.

## Features

### Cooldown Manager integration

- **Essential & Utility groups** — per-group and per-icon control over size,
  border, timer-text thresholds (size/color as the cooldown drops), title,
  stacks/charges, glow-on-proc and keybind text.
- **Buff groups** — arrange buff icons (Group 1 + an Unused pool), drag to
  reorder, add custom cast-triggered buffs, look set per group.
- **Cooldown bars** — a "Bars" tab styling the native Buff Bar viewer (colors,
  background, icon, fill direction, height/width) per group, with per-bar overrides.
- **Below-player frame** — a configurable row of icons under your character,
  split into Front / End buckets, each icon with its own look.
- **Custom icons** — create your own icons from any spell, item or buff straight
  into a group, including on-use trinkets/potions with charges.
- **Per-icon Override / Free settings** — every tracked cooldown has an
  *Override* look (while inside the CDM) and a *Free* look (free-floating on screen).

### Trackers & alerts

- **Healer Range** — alert when no healer is in range during combat
  (class-aware, including Preservation Evoker 25y).
- **Death Alerts** — independent Tank / Healer / DPS death alerts with GUID
  tracking, wipe guard and DPS spam guard.
- **BL Tracker** — Bloodlust/Heroism and equivalents, with active timer,
  Sated countdown and ready check.
- **PI Tracker** — Power Infusion received from a Priest, glowing icon + timer.
- **BRez Tracker** — shared battle-res pool, charges, and an optional
  class-colored player list with per-member Rebirth readiness.
- **Potion / Healthstone / Trinket Trackers** — buff/cooldown icons with stacks,
  favorite fallback (potions) and active/passive detection (trinkets).
- **Cast bar** — reworked player cast bar anchored to your first CDM group,
  with an optional border.
- **Combo sounds** — collapses near-simultaneous tracker cues into a single
  "BL Combo" / "Potion Combo".

### Utility modules

- **Show IDs** — append spell / item / icon / quest / NPC IDs to tooltips.
- **Disable keybinds** — turn keybinds off by context (combat-safe).
- **Focus buffs** — hide Blizzard's Focus frame debuffs, keep the stack count.
- **Decursive helper** — move/place the Decursive MUF container (taint-safe).
- **Reloading announcement** — optional group announcement before a reload.
- **Details! profile** — per-profile opacity with mouse-over reveal.
- **Death Animation** — custom on-death animation + sound (drop your own frame
  sequences into the `Media` folder).

### Shared across features

- Live inside the Cooldown Manager (styled per-icon) or float freely on screen.
- Custom sound (LibSharedMedia), font, size, color and outline.
- Per-instance filtering (Dungeon, Raid, Battleground, Outdoor).
- Drag-and-drop positioning with X/Y offset inputs.
- Brand color + global font theming.
- Saved profiles with import / export.
- English and French localization.

## Slash commands

| Command | Action |
| --- | --- |
| `/ubu` (or `/ubu config` / `settings` / `options`) | Open the settings window |
| `/ubu help` | Show the command list |

## Configuration & profiles

All settings live in the in-game panel (`/ubu`). Profiles are backed by AceDB and
can be exported/imported as a string to share or move between characters.

## Localization

Ships with English (default) and French. Language can be switched in the settings.
