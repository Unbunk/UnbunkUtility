-- Core/Shared.lua
-- Namespace partagé entre tous les fichiers de l'addon (2e vararg passé à chaque
-- chunk). Centralise les utilitaires communs pour éviter la duplication.

local ADDON, ns = ...

-- ── Filtre d'instance ───────────────────────────────────────────────────────
-- Retourne true si le module doit être actif dans l'instance courante, selon
-- la table de filtre { dungeon, raid, battleground, outdoor }.
-- Un filtre absent (nil) => toujours actif.
function ns.IsActiveInInstance(filter)
    if not filter then return true end

    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return filter.outdoor ~= false
    elseif instanceType == "party" then
        return filter.dungeon ~= false
    elseif instanceType == "raid" then
        return filter.raid ~= false
    elseif instanceType == "pvp" or instanceType == "arena" then
        return filter.battleground ~= false
    end

    return false
end

-- ── Polices ─────────────────────────────────────────────────────────────────
-- Résout un chemin de police utilisable : chemin explicite > clé LSM > FRIZQT.
-- Évite que la police par défaut (stockée sous forme de clé "2002 Bold") ne soit
-- jamais appliquée tant que l'utilisateur n'a pas rouvert le sélecteur.
function ns.ResolveFontPath(path, key)
    if path then return path end
    if key then
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local fetched = LSM:Fetch("font", key)
            if fetched then return fetched end
        end
    end
    return "Fonts\\FRIZQT__.TTF"
end

-- ── Hooks de rechargement de profil ─────────────────────────────────────────
-- Chaque module enregistre une fonction qui ré-applique ses réglages. Évite la
-- liste manuelle dans UnbunkProfiles_ReloadAll.

ns.reloadHooks = {}

function ns.RegisterReloadHook(fn)
    if type(fn) == "function" then
        table.insert(ns.reloadHooks, fn)
    end
end

function ns.RunReloadHooks()
    for _, fn in ipairs(ns.reloadHooks) do
        local ok, err = pcall(fn)
        if not ok then
            print("|cffff4444[UnbunkUtility]|r reload hook error: " .. tostring(err))
        end
    end
end
