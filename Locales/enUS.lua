-- Locales/enUS.lua
-- Base locale and localization entry point for UnbunkUtility.
--
-- ns.L is a table whose __index returns the key itself, so any user-facing
-- string wrapped as L["Some text"] yields the original English text when no
-- translation override exists. This makes wrapping strings safe by
-- construction: an un-translated key always falls back to its English source.
--
-- To add a translation, create Locales/<locale>.lua (and list it in the .toc
-- after this file), e.g.:
--     local _, ns = ...
--     if GetLocale() ~= "frFR" then return end
--     local L = ns.L
--     L["Enable Healthstone Tracker"] = "Activer le suivi des pierres de soin"

local _, ns = ...

ns.L = ns.L or setmetatable({}, { __index = function(_, key) return key end })
