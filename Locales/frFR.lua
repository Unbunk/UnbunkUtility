-- Locales/frFR.lua
-- French translation overrides. Registered into ns.locales.frFR REGARDLESS of the
-- game client locale, so the user can force French from the in-app language dropdown
-- even on a non-French client (ns.L resolves the active locale via ns.ApplyLocale).
-- Any key not listed here falls back to the English source via the ns.L identity
-- metatable. Color codes (|cff..|r) and string.format specifiers (%s / %d / %ds) are
-- preserved in the same order as the English source.

local _, ns = ...
ns.locales = ns.locales or {}
local L = ns.locales.frFR or {}
ns.locales.frFR = L

-- ── Slash commands / chat ────────────────────────────────────────────────────
-- NOTE: messages routed through ns.Print MUST use the bare (un-prefixed) key,
-- because ns.Print prepends ns.PREFIX ("|cffff4444[UnbunkUtility]|r ") itself.
-- Keying these with the prefix made the lookup miss and the chat fall back to
-- English on a frFR client. The "  |cff338cff/ubu...|r" lines below are emitted
-- via a raw print() (PrintHelp), so they intentionally have NO prefix.
L["  |cff338cff/ubu help|r — show this help"] = "  |cff338cff/ubu help|r — affiche cette aide"
L["  |cff338cff/ubu|r or |cff338cff/ubu config|r — open settings"] = "  |cff338cff/ubu|r ou |cff338cff/ubu config|r — ouvre les réglages"
L["Commands:"] = "Commandes :"
L["Config panel not ready yet."] = "Le panneau de configuration n'est pas encore prêt."
L["Unknown command. Type |cff338cff/ubu help|r for the list."] = "Commande inconnue. Tapez |cff338cff/ubu help|r pour la liste."

-- ── Profiles ─────────────────────────────────────────────────────────────────
L["Profile Management"] = "Gestion des profils"
L["Profiles"] = "Profils"
L["Current profile: |cff338cff%s|r"] = "Profil actuel : |cff338cff%s|r"
L["Switch profile"] = "Changer de profil"
L["Create"] = "Créer"
L["Create new profile"] = "Créer un nouveau profil"
L["Delete"] = "Supprimer"
L["Delete profile"] = "Supprimer le profil"
L["Export"] = "Exporter"
L["Export current profile"] = "Exporter le profil actuel"
L["Import"] = "Importer"
L["Import profile (creates a new profile)"] = "Importer un profil (crée un nouveau profil)"
L["Import profile"] = "Importer un profil"
L["Name the new profile:"] = "Nommez le nouveau profil :"
L["Reset"] = "Réinitialiser"
L["Reset current profile to defaults"] = "Réinitialiser le profil actuel aux valeurs par défaut"
-- Routed through ns.Print -> use bare keys (no |cffff4444[UnbunkUtility]|r prefix).
L["Profile loaded: %s"] = "Profil chargé : %s"
L["Profile created: %s"] = "Profil créé : %s"
L["Profile deleted: %s"] = "Profil supprimé : %s"
L["Profile already exists: %s"] = "Le profil existe déjà : %s"
L["Profile reset to defaults: %s"] = "Profil réinitialisé : %s"
L["Profile imported as: %s"] = "Profil importé sous : %s"
L["Import failed: %s"] = "Échec de l'import : %s"
L["Profile name required"] = "Nom de profil requis"
L["not an UnbunkUtility profile"] = "ce n'est pas un profil UnbunkUtility"
L["invalid profile data"] = "données de profil invalides"
L["corrupt profile data"] = "données de profil corrompues"
L["This profile needs a newer version of UnbunkUtility."] = "ce profil nécessite une version plus récente d'UnbunkUtility"

-- ── Module / tab names ───────────────────────────────────────────────────────
L["General Settings"] = "Réglages généraux"
L["Combat Utilities"] = "Utilitaires de combat"
L["Extra Utilities"] = "Utilitaires divers"
L["Debug Utilities"] = "Utilitaires de débogage"
L["Addon settings"] = "Réglages de l'addon"
L["Multi-alert combo"] = "Combo multi-alerte"
L["Cooldown Manager"] = "Cooldown Manager"
L["Below player frame"] = "Sous le cadre du joueur"
L["Combat settings"] = "Réglages de combat"
L["Item/Spell Trackers"] = "Suivis d'objets/sorts"
L["Aura Trackers"] = "Suivis d'auras"
L["Debug"] = "Débogage"
L["I know what I'm doing"] = "Je sais ce que je fais"
L["Secret settings"] = "Réglages secrets"
L["Addon usage"] = "Utilisation de l'addon"
L["Personal utilities"] = "Utilitaires personnels"
L["Change addon color"] = "Changer la couleur de l'addon"
L["Changes the blue used everywhere in the addon, live."] = "Change le bleu utilisé partout dans l'addon, en direct."
L["Change addon font"] = "Changer la police de l'addon"
L["Changes the font of all the addon's text, live."] = "Change la police de tout le texte de l'addon, en direct."
L["Default font"] = "Police par défaut"
L["LibSharedMedia-3.0 not found."] = "LibSharedMedia-3.0 introuvable."
L["List"] = "Liste"
L["Start print"] = "Démarrer le print"
L["Stop print"] = "Arrêter le print"
L["Show differential"] = "Afficher le différentiel"
L["Hidden developer settings — work in progress."] = "Réglages développeur cachés — en cours de développement."
L["Addon usage — graph (work in progress)."] = "Utilisation de l'addon — graphique (en cours de développement)."
L["Owner-only secret area — work in progress."] = "Zone secrète réservée au propriétaire — en cours de développement."
L["Tick a CPU and/or Memory box to print that addon's usage to chat on a timer."] = "Cochez CPU et/ou Mémoire pour imprimer l'usage de cet addon dans le tchat à intervalle régulier."
L["Print every"] = "Imprimer toutes les"
L["Memory"] = "Mémoire"
L["All"] = "Tout"
L["Enable CPU profiling (reload)"] = "Activer le profilage CPU (recharger)"
L["CPU profiling is off — CPU usage will read 0 until enabled."] = "Le profilage CPU est désactivé — l'usage CPU affichera 0 jusqu'à activation."
L["Console mode"] = "Mode console"
L["Console Mode"] = "Mode console"
L["Open Console Mode"] = "Ouvrir le mode console"
L["Clear"] = "Effacer"
L["Text editor"] = "Éditeur de texte"
L["Allow selection"] = "Autoriser la sélection"
L["Channels"] = "Canaux"
L["Activate players messages"] = "Activer les messages des joueurs"
L["Activate channels"] = "Activer les canaux"
L["Activate others"] = "Activer les autres"
L["say, emote, yell, guild, officer, guild announce, whisper, party + leader, raid + leader + warning, instance + leader"] = "dire, émote, cri, guilde, officier, annonce de guilde, chuchotement, groupe + chef, raid + chef + avertissement, instance + chef"
L["general, trade, local defense, services"] = "général, commerce, défense locale, services"
L["everything else"] = "tout le reste"
L["Enable"] = "Activer"
L["(nothing here yet)"] = "(rien ici pour l'instant)"
L["Healer Range"] = "Portée de soin"
L["Death Alerts"] = "Alertes de mort"
L["Enable Death Alerts"] = "Activer les alertes de mort"
L["BL Tracker"] = "Suivi BL"
L["Potion Tracker"] = "Suivi des potions"
L["Healthstone Tracker"] = "Suivi des pierres de soin"
L["Trinket Tracker"] = "Suivi des bijoux"
L["PI Tracker"] = "Suivi PI"
L["BRez Tracker"] = "Suivi BRez"
L["Death Anim"] = "Anim. mort"
L["Racial Tracker"] = "Suivi raciale"

-- ── Common labels ────────────────────────────────────────────────────────────
L["Test"] = "Test"
L["Test Alert"] = "Tester l'alerte"
L["Stop Test"] = "Arrêter le test"
L["Lock"] = "Verrouiller"
L["Unlock"] = "Déverrouiller"
L["Show icon"] = "Afficher l'icône"
L["Always show"] = "Toujours afficher"
L["Show at 0 stacks"] = "Afficher à 0 stack"
L["General"] = "Général"
L["Sound"] = "Son"
L["Icon"] = "Icône"
L["Placement"] = "Placement"
L["Border"] = "Bordure"
L["Display"] = "Affichage"
L["Alert position"] = "Position de l'alerte"
L["Below player frame CDM row"] = "Rangée CDM sous le cadre du joueur"
L["Offset"] = "Décalage"
L["Icon size"] = "Taille de l'icône"
L["Show border"] = "Afficher la bordure"
L["Border color"] = "Couleur de la bordure"
L["C"] = "C"
L["Border thickness"] = "Épaisseur de la bordure"
L["Icon position (offset from screen center)"] = "Position de l'icône (décalage depuis le centre)"
L["Position"] = "Position"
L["Position (offset from screen center)"] = "Position (décalage depuis le centre)"
L["Anchor to"] = "Ancrer à"
L["Include in cdm"] = "Inclure dans le Cooldown Manager"
L["Below player frame"] = "Sous le cadre du joueur"
L["Icon at the end of the row"] = "Icône à la fin de la rangée"
L["Row"] = "Rangée"
L["Row %d"] = "Rangée %d"
L["Move in row"] = "Déplacer dans la rangée"
L["Cooldown Manager: Essential"] = "Cooldown Manager : Essentiel"
L["Cooldown Manager: Utility"] = "Cooldown Manager : Utilitaire"
L["Size"] = "Taille"
L["Color"] = "Couleur"
L["Font"] = "Police"
L["Text"] = "Texte"
L["Outline"] = "Contour"
L["Section"] = "Section"
L["Duration"] = "Durée"
L["Active in"] = "Actif dans"
L["W"] = "L"
L["H"] = "H"
L["X offset"] = "Décalage X"
L["Y offset"] = "Décalage Y"
L["sec"] = "sec"
L["seconds"] = "secondes"
L["fps"] = "fps"
L["None"] = "Aucun"

-- ── Instance filter ──────────────────────────────────────────────────────────
L["Dungeon"] = "Donjon"
L["Raid"] = "Raid"
L["Battleground"] = "Champ de bataille"
L["Outdoor"] = "Extérieur"

-- ── Positions / sides ────────────────────────────────────────────────────────
L["Left"] = "Gauche"
L["Right"] = "Droite"
L["Above"] = "Au-dessus"
L["Below"] = "En dessous"
L["Top Left"] = "Haut gauche"
L["Top Center"] = "Haut centre"
L["Top Right"] = "Haut droite"
L["Bottom Left"] = "Bas gauche"
L["Bottom Center"] = "Bas centre"
L["Bottom Right"] = "Bas droite"

-- ── Outline modes ────────────────────────────────────────────────────────────
L["No outline"] = "Sans contour"
L["Thick outline"] = "Contour épais"
L["Monochrome"] = "Monochrome"
L["Monochrome + Outline"] = "Monochrome + Contour"
L["Monochrome + Thick outline"] = "Monochrome + Contour épais"

-- ── Pickers / inputs ─────────────────────────────────────────────────────────
L["Button"] = "Bouton"
L["(select...)"] = "(sélectionner...)"
L["(select a font)"] = "(choisir une police)"
L["(no icons available)"] = "(aucune icône disponible)"
L["Custom icon ID"] = "ID d'icône personnalisée"
L["LibSharedMedia-3.0 not found — enter sound ID manually:"] = "LibSharedMedia-3.0 introuvable — saisir l'ID du son manuellement :"

-- ── Sounds ───────────────────────────────────────────────────────────────────
L["Alert sound"] = "Son d'alerte"
L["Sound on use"] = "Son à l'utilisation"
L["Sound when ready"] = "Son quand prêt"
L["Sound on death"] = "Son à la mort"
L["Sound on PI"] = "Son sur PI"
L["Sound on Bloodlust"] = "Son sur Bloodlust"
L["Sound when Bloodlust ready"] = "Son quand Bloodlust est prêt"
L["Sound on charge regained"] = "Son quand une charge est regagnée"
L["Sound on BRes used"] = "Son quand une BRez est utilisée"

-- ── Text editors ─────────────────────────────────────────────────────────────
L["Alert text"] = "Texte de l'alerte"
L["Timer text"] = "Texte du timer"
L["Stack text"] = "Texte du compteur"
L["Player name text"] = "Texte du nom de joueur"

-- ── Healer Range ─────────────────────────────────────────────────────────────
L["Enable Healer Range"] = "Activer la portée de soin"
L["No Heal"] = "Pas de soin"
L["Alert!"] = "Alerte !"
L["Alert position (offset from screen center)"] = "Position de l'alerte (décalage depuis le centre)"
L["Alert duration"] = "Durée de l'alerte"
L["|cff00ff00Combat range detection available. Note: Evoker healers are ignored unless other healers are present in the group.|r"] = "|cff00ff00Détection de portée en combat disponible. Note : les soigneurs Évoker sont ignorés sauf si d'autres soigneurs sont présents dans le groupe.|r"
L["|cffff4444Combat range detection unavailable — your class has no friendly spell probe usable in combat. The alert will not trigger.|r"] = "|cffff4444Détection de portée en combat indisponible — votre classe n'a aucun sort allié utilisable en combat. L'alerte ne se déclenchera pas.|r"

-- ── Death Alert ──────────────────────────────────────────────────────────────
L["Tank Death Alert"] = "Alerte de mort des tanks"
L["Healer Death Alert"] = "Alerte de mort des soigneurs"
L["DPS Death Alert"] = "Alerte de mort DPS"
L["Tank died"] = "Tank mort"
L["Healer died"] = "Soigneur mort"
L["DPS died"] = "DPS mort"
L["Also alert deaths with no assigned role (treat as DPS)"] = "Alerter aussi les morts sans rôle assigné (comme DPS)"
L["Death alert anti-spam"] = "Anti-spam des alertes de mort"
L["Wipe detection: silence ALL death alerts when many people die at once"] = "Détection de wipe : coupe TOUTES les alertes de mort quand beaucoup meurent en même temps"
L["DPS spam guard: silence DPS death alerts on burst DPS deaths"] = "Anti-spam DPS : coupe les alertes de mort DPS lors de morts DPS rapprochées"
L["|cffaaaaaa%d+ deaths in %ds, silence for %ds|r"] = "|cffaaaaaa%d+ morts en %ds, coupées pendant %ds|r"
L["|cffaaaaaa%d+ DPS deaths in %ds, silence DPS alerts for %ds|r"] = "|cffaaaaaa%d+ morts DPS en %ds, alertes DPS coupées pendant %ds|r"

-- ── Combo sounds (General Settings) ──────────────────────────────────────────
L["Multi-alert combo sounds"] = "Sons combo multi-alertes"
L["Enable combo sounds (collapse near-simultaneous tracker sounds into one)"] = "Activer les sons combo (fusionne les sons quasi simultanés en un seul)"
L["BL combo (Bloodlust + Potion / Trinket)"] = "Combo BL (Bloodlust + Potion / Bijou)"
L["Potion combo (Potion + Trinket, without BL)"] = "Combo potion (Potion + Bijou, sans BL)"

-- ── Boss reset sound (General Settings) ──────────────────────────────────────
L["Boss reset sound"] = "Son de reset de boss"
L["Play a sound when a boss is reset (raid/party wipe)"] = "Jouer un son quand un boss est reset (wipe du groupe/raid)"

-- ── Player speed display (General Settings) ──────────────────────────────────
L["Player speed display"] = "Affichage de la vitesse"
L["Show player movement speed on screen"] = "Afficher la vitesse de déplacement à l'écran"
L["|cffaaaaaaText colour changes with speed.|r"] = "|cffaaaaaaLa couleur du texte change selon la vitesse.|r"
L["Speed text appearance"] = "Apparence du texte de vitesse"
L["Speed display position (offset from screen center)"] = "Position de l'affichage de vitesse (décalage depuis le centre)"

-- ── BL Tracker ───────────────────────────────────────────────────────────────
L["Enable BL Tracker"] = "Activer le suivi BL"

-- ── PI Tracker ───────────────────────────────────────────────────────────────
L["Enable PI Tracker"] = "Activer le suivi PI"

-- ── Potion / Trinket trackers ────────────────────────────────────────────────
L["Enable Potion Tracker"] = "Activer le suivi des potions"
L["Enable Trinket Tracker"] = "Activer le suivi des bijoux"
L["Health Potion"] = "Potion de soin"
L["Combat Potion"] = "Potion de combat"
L["Potion"] = "Potion"
L["Favorite potion"] = "Potion favorite"
L["Use favorite when in bag"] = "Utiliser le favori s'il est dans le sac"
L["Show stack count below icon"] = "Afficher le nombre sous l'icône"
L["Trinket 1 (slot 1)"] = "Bijou 1 (emplacement 1)"
L["Trinket 2 (slot 2)"] = "Bijou 2 (emplacement 2)"
L["active"] = "actif"
L["passive"] = "passif"
L["No trinket"] = "Aucun bijou"

-- ── Healthstone tracker ──────────────────────────────────────────────────────
L["Enable Healthstone Tracker"] = "Activer le suivi des pierres de soin"

-- ── Racial tracker ───────────────────────────────────────────────────────────
L["Enable Racial Tracker"] = "Activer le suivi raciale"
L["Tracked racial :"] = "Raciale suivie :"
L["No racial detected"] = "Aucune raciale détectée"
L["Manual racial detection"] = "Détection manuelle de la raciale"
L["Spell ID"] = "ID du sort"

-- ── BRez tracker ─────────────────────────────────────────────────────────────
L["Enable BRez Tracker"] = "Activer le suivi BRez"
L["Player list"] = "Liste des joueurs"
L["Enable player list"] = "Activer la liste des joueurs"
L["List position relative to icon"] = "Position de la liste par rapport à l'icône"
L["Status icon / timer position relative to name"] = "Position de l'icône / du timer par rapport au nom"
L["Estimated BRes cooldown (seconds)"] = "Cooldown BRez estimé (secondes)"

-- ── Player Death Animation ───────────────────────────────────────────────────
L["Enable Player Death Animation"] = "Activer l'animation de mort du joueur"
L["Show animation on death"] = "Afficher l'animation à la mort"
L["Animation"] = "Animation"
L["Animation size"] = "Taille de l'animation"
L["Animation duration"] = "Durée de l'animation"
L["Animation position (offset from screen center)"] = "Position de l'animation (décalage depuis le centre)"
L["Loop animation until duration ends"] = "Boucler l'animation jusqu'à la fin de la durée"
L["Frames per second"] = "Images par seconde"

-- ── Minimap ──────────────────────────────────────────────────────────────────
L["Minimap icon"] = "Icône de minicarte"
L["Show minimap button (left-click to open settings, drag to reposition)"] = "Afficher le bouton de minicarte (clic gauche pour ouvrir, glisser pour déplacer)"
L["Welcome message"] = "Message de bienvenue"
L["Show the login message in chat"] = "Afficher le message de connexion dans le chat"
L["Open UnbunkUtility"] = "Ouvrir UnbunkUtility"
L["|cff338cffLeft-click|r to open settings"] = "|cff338cffClic gauche|r pour ouvrir les réglages"
L["|cff338cffDrag|r to reposition"] = "|cff338cffGlisser|r pour repositionner"

-- ── Position editor (shared) ─────────────────────────────────────────────────
-- Routed through ns.Print -> bare key (no prefix).
L["Alert unlocked — drag to reposition, then click Lock to save."] = "Alerte déverrouillée — glissez pour repositionner, puis cliquez sur Verrouiller pour sauvegarder."

-- ── Combat settings (Combat state text + Combat timer) ───────────────────────
L["Combat state text"] = "Texte d'état de combat"
L["Enable combat state text"] = "Activer le texte d'état de combat"
L["In-combat text"] = "Texte en combat"
L["Show text out of combat"] = "Afficher un texte hors combat"
L["Out-of-combat text"] = "Texte hors combat"
L["Combat state text position"] = "Position du texte d'état de combat"
L["Combat timer"] = "Minuteur de combat"
L["Enable combat timer"] = "Activer le minuteur de combat"
L["Timer text"] = "Texte du minuteur"
L["Combat timer position"] = "Position du minuteur de combat"
L["Hide out of combat"] = "Masquer hors combat"
L["Reset out of combat"] = "Réinitialiser hors combat"

-- ── Prompt dialog ────────────────────────────────────────────────────────────
L["OK"] = "OK"
L["Cancel"] = "Annuler"

-- ── Sub-cadre titles / misc UI ───────────────────────────────────────────────
L["Speed display"] = "Affichage de la vitesse"
L["Speed display position"] = "Position de l'affichage de vitesse"
L["Cooldown Manager row"] = "Rangée du Cooldown Manager"
L["CDM: Below player frame"] = "CDM : Sous le cadre du joueur"
L["Row icon order"] = "Ordre des icônes de la rangée"
L["Manual mode"] = "Mode manuel"
L["Enable manual positioning"] = "Activer le positionnement manuel"
L["(no icons in the row)"] = "(aucune icône dans la rangée)"
L["Essentials"] = "Essentiels"
L["Utility"] = "Utilitaire"
L["CDM: Essentials"] = "CDM : Essentiels"
L["CDM: Utility"] = "CDM : Utilitaire"
L["Front of the row"] = "Début de la rangée"
L["End of the row"] = "Fin de la rangée"
L["No icons"] = "Aucune icône"
L["Copy the link (Ctrl+C)"] = "Copier le lien (Ctrl+C)"
L["Count text size"] = "Taille du compteur"
L["List offset"] = "Décalage de la liste"
L["List row height"] = "Hauteur de ligne de la liste"
L["Combat State Text"] = "Texte d'état de combat"
L["Out of Combat"] = "Hors combat"

-- ── Login greeting (Welcome) ──────────────────────────────────────────────────
L["|cff33aaffUnbunkUtility|r v%s loaded - type |cff338cff/ubu|r to open settings."] = "|cff33aaffUnbunkUtility|r v%s chargé — tapez |cff338cff/ubu|r pour ouvrir les réglages."

-- ── PI Tracker banner ─────────────────────────────────────────────────────────
L["|cffff4444Feature unavailable since Midnight changes.\nWorking on it...|r"] = "|cffff4444Fonctionnalité indisponible depuis les changements de Midnight.\nCorrection en cours...|r"

-- ── Language selector ─────────────────────────────────────────────────────────
L["Language :"] = "Langue :"
L["Language set — type /reload to apply."] = "Langue définie — tapez /reload pour appliquer."

-- Apply now so a frFR client shows French at load time (before ns.db exists). Core/
-- DB.lua re-applies once the saved account-wide override is known.
ns.ApplyLocale()
