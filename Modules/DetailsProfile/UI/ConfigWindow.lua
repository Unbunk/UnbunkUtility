-- Modules/DetailsProfile/UI/ConfigWindow.lua
-- The owner-only "Personal utilities" sub-tab (gated in Core.lua by debug-unlock AND
-- IsAccountOwner). Hosts the Details! profile auto-switch (ns.DetailsProfile) and a
-- one-click restore of a hardcoded UnbunkUtility profile backup.

local _, ns = ...
local L = ns.L

-- Your UnbunkUtility profile export (Profiles > Export, the "!UU1!..." blob), baked in so
-- you can restore it if you lose it. To refresh it: re-export and replace the string below
-- (keep the [=====[ ... ]=====] long-string wrapper). Empty string = nothing to restore.
local OWNER_PROFILE = [=====[!UU1!TZ1wZjoow4FlZB78qNciHoP334wsZ2qclM0zMPsrIalaTXyXilN00pKF775CKST8fiKo9S1SvLAMkfwwxox(oF6izPEA9PtM6X89LHt9UoCwC4dxRfbc92PEpYvrcO8lRp1ZNPzynNldJKbC8NRGxu7StGYwDLEfu3PZM6900lpPrTPEA(3098fAPAABSgJcyBTvz(QoRyHH8a6jwqG8jpEaFUghR2t1t9g1FIIn)bUIgr)1T09c9X(rlwZvDKbs6nmsYu0Fxs)Dg(xn1MU8i4h8OiEOwWcOY8cKACmNjv(CLN478Px2yQx0k5t9NtdU3gz0Vn9Ypu)0A2r7CzO2wtOiEiBwa3h7eOM)ouZgNaflGwFJWxdMe8ryOglFIKir48GyFE)Wo(Rj1nC(kPAO0Np1BHIZteMEzDmnSxfRdeHWRV66jd6FzVK6vq5bfUgP81idrnu5rH5ZCXYvAJ0ejJd9VkCu)uliQtFHdE4g1Q1457Bld8rjnsdsh)CrG2y59JdxYnMfftqoGzmToGVuHDj(Smw7ljFS2oqq)cJuEO0)857h1)57)hFgeQFfR5N5Sa9QiTmK74PJ2Wdc67p9Yp24JOBrdV5aC2w9BmN5VfLPeX46iEz5WzKtfitlgX0ROM0pe0)fS58BB5d9B0T56JBhY9fSB9WMeDl2b360N4ZhTEZXziL25qhhFsM8ze49lHuDCeu0KKHiR3yNOfna)7gRyuqfbDDHfOySBKqvrzZCm8QIrzZ4qmSjc3kJLfODe(vVYWVJpTUJYwsatc9AEIP1T0)bxjjULDe51UYOzHMVgXBnBIwYdkaidWxmwidjIOO2VIawxgUxIFOTdA1cGEl4vQlsbTGSSrjc1xhXwsu8mGu(rozy3eJfKFgcJsdoGUIflqrBnF9oQLafYhbEyGW1OYTrqZvOUHnP9alrW5k2AdUyKebV2InYCgWlTHLPsOEOoW9n1BcOnpW12xuNy7hZMdZhuA0EjbOJCn4WHqNDiyKA1LdULwbCLMGpBIgctaH2sVUJ8E(EFb4b9wbTGR6)AqBZkG2MHdg09VCNm7f6eO5p4LaO(bWstG23fuRmIpJ65zj5QMFJRE(ESvzmBGYq2TmoRMuHJOq9g1np5q9DMJSx54GswXrXHu2iMMWkVKPZCl0PGDXfw7OMzrXG4vQHJi6SAoVmDOqHpfDyKveE8ljnTAMzOEev5KstW8k8FypeL65osVKruQcYU7n5Qr31P3Lt6ngffZ8fFeuHNS53aQCCeVtmeYT2GHmcCzkFqPFlqliKPkKvQrlbiLZS9ZY6y68d1(00X(uRK9b9AvcU)zjSwl1HiPh3mvsBu2tIsQZuKF0uIjg8yujja4ls68smxyVSZ5fTXu1tQyL4k3aRDgP4eoMqVCDilksSm0MPTvDl16eKBLelevEEEfd2RsF8U5ooZWDC0jjAQRsvwRtzuq(WtB6QIf4VC8G0Ss5MVQiE714mlM0tA0paNCZFVEJJp50pE2FrzsEWRlasmXdRlPN2u9ACs9JRDs(KolUaIkYuC35IUG9Oub9UBNNuMda0XKNpJv3Cz)rwOaS0kY9wATc7jv4uTXW0G)k6wuPAF0KjN)AwMr(mElUeJslDVsl4bSETmLmr7Slu4KJ)eHFmjNvad(Xp9PtoCmyvWQDwVkSeUOTsljT8sCoPwZ38cp7IP3Mn)yEG1EwVdGtBC2z5bLh0ITkcqFjC0(bWMuQ3jaUiQTIOQFIa1k4F2nKTqqpzm3lmM8uo7acmuEB4C)UIOnWOvGuErMg9XuhqDmjml4HYhErQHphWbtiyemh0ho(OA3UGCjNluSHYq5hgZxghWuhP1liw9cgPfj6k2GNVhBckPThZJ2XgYTRLREaR6Ta(S(j5dh8FDXd4dXRVfe1VJn28OjSiqePVAXIio4Spl)E1108wGNmbnGRRGAqjJdwAhj4(Lpf2lcKEMMJzgxBNyUCBexZ9HNMdkH(8CEDh4KFz8eQNpFp(oauzu2F1iIh8o6SNTsJgZ2VY9SPztmXnIeuhh5jqiXys5j5YuqRzYh5Pq6MNADaw)bm750302B4GcOw7cd2ZMY(c8ugJDc7uQ1U0gZCq5svibQk2bvN5nsCO7GF1HYiPMzeHyjocxfBjoUOv(S4LxhgiHGBQAPBdsXi9dDA09T17iHrWtSTrEa8HmgL2BRDSv8wdt7b7i)mEHThZXgMm)vTY7t)BbQnqg7FB7bulXFNhK14LbvdYGuy7)1SwaAz5QhiL(bWs1YMFCxSohckCVBJzHy9IFpHxpdFfFRH8tT7onso85sfBZQ0TJ8jbTCz7ErIXY1p9u6drD6NAIv3U)J4Bo2(MZA20mFR7(u6UBKjD3eMAjxZ99WmiJWAb5bGwq4xERykZKkS7gsSkmtXI1GkMeXaLmCe4JMG6n(uVWvON4Fljy7yW2Zv9Vc)91WBa3J)1HcnTHJrU14UUTV7AV7gt9il6pJ531Hjaul88ab6UUrSm6oqQGjJcyaCSWBgWxA(yAE)s74LxOyZMzLptV1luRKB2MxgDuYcD3Kv8ByQBajqqDAxUMjcIatbuYCuLXs7OKrrxWwpdaKlPcaO7fXiVp2DCMwj(2Dj1UB7HFyetP3(HcDDWJCiXWnSqRgyf5ZJJSf4XEK7NSjerUYZer42jRuWir24aZK0dL0UCOIm49XGw6nh)aK0J3WwkBTztUHmP)Ocv8gKH8xOCRgPKlebMM2wSSsZJRB8lJnUXK6wWN1oEXIX81IqF8JJAnl3ivb(9EeIcQcvmmV1RDNcIYxLc)Oncfz1hjv0oWNQsDzAMNwQWikN21ja3xK5fhUoxE35jgPR772ayuMZnD8CP6R8qFJ115rASCgBYzE8Xp0kwXIUAdMZpv2KNe65R6TwQnEZwkGmiCcKQLwSjrzrPk6ddf(HerewTyT8FhZJn6bxdHQNlIwzXETde)X3f3rm6Q4nAR1EPNDfAaLe9ndgjH8Hfg5qfZXKx(kliUC8i4ily5ZcYUyY5xvWl0fqHRvIfKOobyugYVzfpmhuyJuXxWccidJbLdbDGmWj1gPrqU9C4JZhbia4)LHjFBDxHS31g)fjKpoICDCMXIJMv8J5Gsai)CSlpjPYDa6Oaomnbnif)(nfHG0y4WpaOFyYa)ORw0vX4HYCrhzMjm2by3HNG5)3Sb8udGCuseHlmaSm7Bha(mpyB068f7IbMixd)p(lVTH(I5mRnPlJmyzmRocRduprehcIbi8JGwbGbcZ2HrcizbzB3iXVkgjFFgQ02ltWQEI1WcQqO8CfZ4St602XQqOh6OIJy(2qftmyVqkFFUYjWWraRqASOJUsajiP63hqf81aR(VlJXNBftNFIedGTbxfU9BK)73greXguDNbsjSuM4W5IGkqqeFvYkDgYcbQcvhokVMeSku9H5SKmaLDviexga(awKX(bmSHSGTAXCtGwA4WDo0aokxMZgWtlLHlcsC49yrB79TnCLGdK)aoMgGei(e(6n4C2MrHbaA9ajW3gRTQr(o)gPEWxCC2Ustc)aAQkQ0avafbKsMHjUeG5rAyzGLlpaYuZjTGep)xzHlJzkFhtg58TZnAsT01E2rA4XhiM5m9mU0(evPTI9uGLCWfL7g8msX36NgBGH72UT1wX)bYTO7qxvVdlS)q5Y(68wR2lALZtBddPjRC8FGihUqS0oSRbO)fqQLBISPJ2Ua)oHHYpqGrseeq4EGsEH4IoDjRTnriH6pnC(PMFASypz4ycIxplZrtPtKFEJK(jGZcZpNMJnyelsZlysBtjkFUu167CL0KnwRzehzcvTRDyS0WSJIHznXaCLsn0mtisbebjJyPytbXUHeqt)6OV2JcX(fuFNOelxM0dJNqIqKwXcq8QJ21AdGgZnXVNgNrknlWiiens3AgqYyZQkdEbj6qFbjwqgGCiBUsI(SheA6Jorgo2swgLt72ChjWdOlcT6MTOl4mvH47BKDtkW1h1bjtbUv839c4BGuuD9DE)zmoP9kJ(LLWXf4KykNHSGhSiBskKLzMgAOieYyCt7yne6B(lwmbGxqZbFEaZeYAs9TRzLvODPKvkNtLEzcE1zMyuXNWJYnXXUM3tsZNFP8rwsYVommMm0UZj1UehpYC1zf3K2tYyu5m2UCCtUXWXLStIUnUOzSqgJJtKBBWxUCJVesiDfxf69WwSzPwo34SkM4CoK(UJjZyrkKlnfr9VKqRzb2v1KJycs)yPcY)i)W5QyvfHxWOKB2oGSzPWMeRcKvVhaIRHi1r(5LYp)aGdsXeUjrbw6vxTaYDCGy(QVyt(OWW7SKqid3V)922iQu)ALDsknp(qHL5LLptkL(eGPikwvohyW5IDr2cTFFnZVVM53xZ87Rz(91m)(AMFFnZVVM53xZCER17Rz(91m)(AMFFnZVVM53xZSU41r5N(jXvB6(6)vC0nM9chwJd4m06ORMJ2bDYo21XZO5lCI6S2YYN31x(OxK20ch4Wd(GneHwKlRF8pWPne1RcNVIDFmjkF66kCWjYC6n()sNEX7o7pStV()ZC6N83aNUgpbQ(PNrRcejk(JCwGzR5WNXQ63kasiWOp0RTxNT9Y7mR8DiRsEhtpsBzK8rdn(k6htYFGAHYJTRpMUwiMRd(S4flOFKcaJsuYnM293y1BtIMPnsSzCnBM5KDDeBZIosohK4vR5TECER6W7EytQS3l19MKlLcm3ghpwSxTWACb72kyEo3IANZtn)fpWPACUsNRJ5BMel353(qoDHNC6XvFHpWD0(kWlRW9I9Y9CedFt3HdJ2VZ7UrJYhvUIhe39rxM07zNO(danCO3W5zLpg97GyC3CDhm57AwymMHQXfqHLMBO3ywO5SbU3qTgj(O6yAgZ35vpRwZpLbQWUxNEBdVuAUmkobA5yTlD3VEvg7kVMCLM709iR(6oTQ01f5sjQao3xel2PmWjrzDGo)KUQIgz4GUPInsVPI4plCtf55U4BA6dpTf3DqM5UOL3297KTJbRu15Ftemf0hwI63sF6MKRgPT6NpYZC7xXhkEh8R00DERp)z77DQp280RyqTAoou8ndKYngTWWJIB9Xoa1IqNt59zunYxWlt6c9r5y0kN9iviHrP8ThaV5Iz9S9Emw6FGu(jmZMrNljDRtcn7hMCxIijnz2Oj8VbfaQ6Z3lxKvdr4UUie1oQHvvORnjoBrHj3Sw7sIcoQ7H)b9lheDW(Mj28Ft)V]=====]

local function dcfg() return ns.DetailsProfile and ns.DetailsProfile.Cfg() end
local function dset(field, v)
    local c = dcfg(); if c then c[field] = v end
    if ns.DetailsProfile and ns.DetailsProfile.Apply then ns.DetailsProfile.Apply() end
end

-- The three context modes, presented in the dropdown by label.
local MODES = {
    { key = "group",    label = L["By group type"] },
    { key = "instance", label = L["By instance type"] },
    { key = "both",     label = L["By group or instance"] },
}
local function modeLabel(key)
    for _, m in ipairs(MODES) do if m.key == key then return m.label end end
    return MODES[3].label
end
local function modeKey(label)
    for _, m in ipairs(MODES) do if m.label == label then return m.key end end
    return "both"
end

-- Restore the baked-in profile into a NEW profile (non-destructive): asks for a name,
-- then ns.profiles.ImportAs creates + switches to it. Surfaces the import result in chat.
local function ImportOwnerProfile()
    if not OWNER_PROFILE or OWNER_PROFILE == "" then
        print("|cff338cff[UnbunkUtility]|r " .. (L["No backup profile is baked in."] or "No backup profile is baked in."))
        return
    end
    ns.ui.ShowPrompt({
        title      = L["Import my profile"],
        text       = L["Name the profile to create from your baked-in backup:"],
        default    = "Unbunk",
        acceptText = L["Import"] or L["OK"],
        maxLetters = 32,
        onAccept   = function(name)
            if not name or name:gsub("%s", "") == "" then return end
            if not (ns.profiles and ns.profiles.ImportAs) then
                print("|cff338cff[UnbunkUtility]|r " .. (L["Import failed."] or "Import failed."))
                return
            end
            -- Call OUTSIDE the nil-guard so ImportAs's 2nd return (the error message) is
            -- preserved — an `and`-chain would truncate it to a single value (err = nil).
            local ok, err = ns.profiles.ImportAs(name, OWNER_PROFILE)
            if ok then
                print("|cff338cff[UnbunkUtility]|r " .. (L["Profile imported."] or "Profile imported."))
            else
                print("|cff338cff[UnbunkUtility]|r " .. (err or (L["Import failed."] or "Import failed.")))
            end
        end,
    })
end

local function CreatePersonalPanel(parent)
    local options = {
        { type = "label", font = "UnbunkUtilityH2", height = 28, text = L["Personal utilities"] },

        { type = "group", title = L["Details! profile auto-switch"], build = function()
            return {
                { type = "label", font = "UnbunkUtilityH6", height = 32,
                  text = L["Switches your Details! profile by context: a raid context applies the raid profile, otherwise the dungeon profile."] },

                -- Warn (at build time) if Details! isn't available.
                { type = "custom", height = 18, build = function(host)
                    if not (ns.DetailsProfile and ns.DetailsProfile.DetailsReady()) then
                        local fs = host:CreateFontString(nil, "ARTWORK", "UnbunkUtilityH6")
                        fs:SetPoint("LEFT", host, "LEFT", 0, 0)
                        fs:SetTextColor(1, 0.5, 0.2)
                        fs:SetText(L["Details! not detected — install / enable it for this to work."])
                    end
                    return { frame = host, height = 18 }
                end },

                { type = "checkbox", label = L["Enable"],
                  get = function() local c = dcfg(); return c and c.enabled end,
                  set = function(v) dset("enabled", v and true or false) end },

                { type = "dropdown", label = L["Switch based on"], width = 220,
                  getList       = function() local t = {} for _, m in ipairs(MODES) do t[#t + 1] = m.label end return t end,
                  getCurrentKey = function() local c = dcfg(); return modeLabel(c and c.mode or "both") end,
                  onSelect      = function(lbl) dset("mode", modeKey(lbl)) end },

                { type = "textinput", label = L["Raid profile name"], width = 240, maxLetters = 64,
                  get = function() local c = dcfg(); return c and c.raidProfile or "" end,
                  set = function(v) dset("raidProfile", v or "") end },

                { type = "textinput", label = L["Dungeon profile name"], width = 240, maxLetters = 64,
                  get = function() local c = dcfg(); return c and c.dungeonProfile or "" end,
                  set = function(v) dset("dungeonProfile", v or "") end },

                { type = "button", label = L["Apply now"], width = 120, hostHeight = 28,
                  onClick = function() if ns.DetailsProfile and ns.DetailsProfile.Apply then ns.DetailsProfile.Apply() end end },
            }
        end },

        { type = "group", title = L["Restore my profile"], build = function()
            return {
                { type = "label", font = "UnbunkUtilityH6", height = 44,
                  text = L["Imports the UnbunkUtility profile hardcoded in the addon into a new profile (non-destructive), in case you lose your settings."] },
                { type = "button", label = L["Import my profile"], width = 180, hostHeight = 28,
                  onClick = ImportOwnerProfile },
            }
        end },
    }
    return ns.ui.BuildMenu(parent, options, { gap = 12, width = 518 })
end

local initDP = CreateFrame("Frame")
initDP:RegisterEvent("ADDON_LOADED")
initDP:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "UnbunkUtility" then return end
    UnbunkUtility.RegisterModule(L["Personal utilities"], nil, CreatePersonalPanel)
    self:UnregisterEvent("ADDON_LOADED")
end)
