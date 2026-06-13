-- Locales/enUS.lua
-- Base locale + localization engine for UnbunkUtility.
--
-- ns.L[key] returns the translation of `key` for the ACTIVE locale, or the key
-- itself (the English source) when there is no override — so wrapping a string as
-- L["Some text"] is always safe.
--
-- The active locale is the user's saved choice (ns.db.global.locale, account-wide)
-- when set, otherwise the game client locale (GetLocale()). nil / "auto" follow the
-- game. Each locale file registers its overrides into ns.locales[<code>] REGARDLESS
-- of the client locale, so the user can force a language different from the game's;
-- ns.ApplyLocale() then points ns.L at the chosen table. Because widgets capture
-- their strings when they are built, changing the saved locale takes full effect on
-- a UI reload (the language dropdown triggers one).
--
-- To add a translation, create Locales/<locale>.lua (listed in the .toc AFTER this
-- file) that registers into ns.locales[<code>], e.g.:
--     local _, ns = ...
--     ns.locales = ns.locales or {}
--     local L = ns.locales.deDE or {}; ns.locales.deDE = L
--     L["Enable Healthstone Tracker"] = "..."
--     ns.ApplyLocale()
-- and add the code to ns.LOCALE_NAMES / ns.LOCALE_ORDER below so it appears in the
-- in-app language dropdown.

local _, ns = ...

-- code -> { [englishKey] = translatedString }. enUS has no table (identity).
ns.locales = ns.locales or {}

-- Languages offered in the in-app dropdown, by endonym. enUS is the identity source.
ns.LOCALE_NAMES = {
    enUS = "English",
    frFR = "Français",
}
-- Order the codes appear in the dropdown (the UI prepends an "Auto" entry).
ns.LOCALE_ORDER = { "enUS", "frFR" }

-- The active override table ns.L reads. Swapped by ns.ApplyLocale; ns.L ITSELF is a
-- stable table, so every `local L = ns.L` captured elsewhere keeps resolving live.
local active = {}

ns.L = ns.L or setmetatable({}, {
    __index = function(_, key)
        local v = active[key]
        if v ~= nil then return v end
        return key
    end,
})

-- The locale to actually use: the saved account-wide override when it is valid,
-- otherwise the game client locale. nil / "auto" / an unknown code => follow the game.
function ns.GetEffectiveLocale()
    local saved = ns.db and ns.db.global and ns.db.global.locale
    if saved and saved ~= "auto" and ns.locales[saved] ~= nil then
        return saved
    end
    local game = GetLocale()
    return ns.locales[game] and game or "enUS"
end

-- Point ns.L at the effective locale's overrides. Cheap and idempotent; call it
-- whenever the saved locale might have changed (Core/DB.lua does once ns.db loads).
function ns.ApplyLocale()
    active = ns.locales[ns.GetEffectiveLocale()] or {}
end
