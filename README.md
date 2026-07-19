# Unbunk Utility

A comprehensive cooldown manager and combat utility addon for World of Warcraft
Retail that keeps you informed during fights — healer range, deaths, cooldowns,
battle resurrections, consumables and more, through fully customizable on-screen
alerts and icons.

## Two ways to render the Cooldown Manager

Unbunk Utility is built around Blizzard's **Cooldown Manager (CDM)** and gives you
two rendering backends, switchable at any time from **CDM Settings**:

- **Standalone engine (default)** — a ground-up, self-drawn Cooldown Manager. It
  draws its own Essential/Utility cooldown icons and hosts the native Buff/Bar
  frames, so aura stacks, durations and bar fills stay correct in combat. Adds
  engine-only extras: class-resource bars, proc glow, range check and a
  global-cooldown sweep.
- **Redesigned native** — reuses, resizes and restyles the game's own cooldown
  icons and bars in place.

Either way you get the same four tabs (Essential / Utility / Buffs / Bars), the
same per-group and per-icon settings, and can build your own tracked icons.

## Requirements

- World of Warcraft Retail (Interface `120007`).

## Installation

- **CurseForge / Wago / WoWInterface** — search for *Unbunk Utility*, or
- **Manual** — drop the `UnbunkUtility` folder into
  `World of Warcraft/_retail_/Interface/AddOns/`, then `/reload`.

Open the settings with `/ubu`.

## Highlights

- **Standalone CDM engine** — draws the Cooldown Manager itself (own-draw
  cooldowns + adopted native buff/bar frames); the default display mode.
- **Class resources** — auto-detected bars for every spec: combo points, holy
  power, soul shards, essence, runes, aura-based resources and Brewmaster stagger,
  each independently positionable and styleable.
- **Full config parity** across both modes — size, borders, fonts, colors, grow
  direction, spacing, multi-row grids and multiple display groups, applied live.
- **Fading** — fade the CDM and reveal it on combat, target, or mouse hover,
  configured per group.
- Native ↔ engine **mode switch**, with settings migrating automatically.

## Features

### Cooldown Manager

- **Essential & Utility groups** — per-group and per-icon control over size,
  border, timer-text thresholds (size/color as the cooldown drops), title,
  stacks/charges, glow-on-proc and keybind text. Drawn by the engine or restyled
  in place, your choice.
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

### Class resources (engine)

Auto-detected, per-spec resource bars — combo points, holy power, soul shards,
Evoker essence, Death Knight runes (with ready/recharging colors), aura-based
resources (Icicles, Maelstrom Weapon…) and Brewmaster stagger with color
thresholds. Each is an independently positioned, fully styleable bar (textures,
fill/background colors, value/percentage text, segment dividers, adaptive width).

### Engine extras

- **Proc glow** — icons light up when the spell procs (configurable style/color).
- **Range check** — the icon tints red when the target is out of range.
- **Global-cooldown sweep** — the classic radial GCD sweep shared across ready
  abilities.
- **Keybind press-flash** — flashes while the action-bar keybind is held.

### Trackers & alerts

- **Healer Range** — alert when no healer is in range during combat
  (class-aware, including Preservation Evoker 25y).
- **Death Alerts** — independent Tank / Healer / DPS death alerts with GUID
  tracking, wipe guard and DPS spam guard.
- **BL Tracker** — Bloodlust/Heroism and equivalents, with active timer,
  Sated countdown and ready check.
- **BRez Tracker** — shared battle-res pool, charges, and an optional
  class-colored player list with per-member Rebirth readiness.
- **Potion / Healthstone / Trinket Trackers** — buff/cooldown icons with stacks,
  favorite fallback (potions) and active/passive detection (trinkets).
- **Cast bar** — reworked player cast bar anchored to your first CDM group, with
  an optional border and cast-end feedback.
- **Combo sounds** — collapses near-simultaneous tracker cues into a single
  "BL Combo" / "Potion Combo".

### Fading

Fade the Cooldown Manager — its parts chosen per group — and reveal it when you
want: in combat, with a target, or by hovering with the mouse. Works on both the
engine's own frames and the native viewers.

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
- Drag-and-drop / tab-driven positioning with X/Y offset inputs.
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
