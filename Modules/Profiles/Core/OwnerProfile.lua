-- Modules/Profiles/Core/OwnerProfile.lua
-- The baked-in UnbunkUtility profile backup + a one-click "restore" that imports it into
-- a NEW profile (non-destructive). It lives in its own file under the Profiles module
-- because it belongs to the addon's PROFILE system, not to any feature module (it used to
-- be embedded in the Details! panel). The owner-gated "Personal utilities" panel just calls
-- ns.RestoreOwnerProfile().
--
-- To refresh the backup: in-game do Profiles > Export, copy the "!UU1!..." blob, and replace
-- the string below — KEEP the [=====[ ... ]=====] long-string wrapper (it stores the blob
-- verbatim, no escaping). An empty string means there is nothing to restore (the button
-- reports that in chat). If the blob ever contained "]=====]", widen the wrapper by one '='
-- on each side.

local ADDON, ns = ...

local OWNER_PROFILE = [=====[!UU1!T3vxtTnsZ6)oV7fHYFdCUddKa1MytHCYU5uPeiln2wViK8rAmjSxWV9t3ZxA0mJSLXWUHnUQT2GL0mQNE6(PFME(q(T9N47fefLL67950PRsV7Z04Ky6J(EpqYlIHRpQTVxuanaFYPb5FipB1Yc8hZItsoJmlyvcT4lT9hcvurr88u4EuFVS8iso8NJAZ)FJ61UxN((J6W(Rb9pYFux4)61PtVbWLG)RFVUhbLCulwfavrk5h0lJWIGVyp6JjKQVV0aA8dKX4BIFH4WS0tNnNlbK0GPjKiMGLgUil3lmNqsfvbVaZLTgMy6vSi77NTkhQwOHRk3Km4oSYYeKliXZxaYzNwWpNFAwswotlY0u5G8Fq7wGipx9xtL)fiufuOYdplUyzsWJ(tHlSmimofFyFVWzy1LeSSGl2mnCCojKjpExF5hUaErlZk(k7XH)4pbvyl4pJJyVDq6MakTv5eFVHekLK)0TdtI)R)kipIDxxsRuw737yMS2gLZvPjzH3bIXuMs67Gy47D24)yexjnk4EcVha(xpMnXt3cvyCky2qFpi3ybZjjxLvavkjj778ENpeSK9MX)gUxmVL9XZFp366pIJOlavlOBPCJGlibj0ff0SuYK8aqKyIFy09NqppLjEGkn8oJggRzGnlEJK1KMb9GN)dAEqbk5yRWdlj(JPmRv76Ofx1WvuIUVW7EFwk1l(ViWtb6oA89KCTl1J34eTKUTQyiwKTkn63jp(5cIHd3)Zt3Q1uF62)ZfGv2VXLZRYjffJbnRWMHgttiMsbCjMYEY4R4LAcEjMcs8sVMee94gETSNP8TZACSQ90Zhn58Rb9b0vwNIsArD8auxXk74v0K4uOXo(Zt(4LJoxiPJNn7pzLcvvshkuxXUlAd77PPAbH3379X5bpD7NYsZe9dqLuqO86rwRFv7xwVAUwbQtwxbwfNWCWbNLXtMm(tchm2RTbguGr4zKcQW((kOZbQzHO5Uz7STK9qfNEuiHNzACAub27XTnf908BFzihEIda8UU9AX7xM84s4vUm(hKerRyYcW0zrwsujgxyDw5hCuNY2gwA4p7dVq(B(ae(cGIxxnywCTs3Rp3D2qQoxZ1q0LY7bz)Iz4vPRr5)zPf5OIVJHgkRkUPbQXoH()sYZq1j0PDnagXWGsdtwfrUm90O7rjGlBXqCVYacHbjIwVxaLRqAKcuQRuvaOay1W6QaTstLD8AAO4uOHLgsa4vkhgmAv6Cc3wipiM9qzROrzzml8PbuWMddXLI3IkqcgNIOpd5MmAvpIpw1sK)0CyJHct4g4xO5C(vbUjejili6K0uOkdjyXLGItFjAxHlcstjjmAjldYPpQxYIGh5pLgLe(nrMf8hh4IWEoQGsa6jXQn2VQuBq7heA4bVhaLdMdoCxZACqq8do4awGMSWvfdxbka9g6qELhSCXNzfdU13JfKLy8oINndFbHlxXVyCkOnEiiHzZCp5EjTOZib0fNKaXzX6ybGEZGObvDNd7lVWLBJoDQHoL18IwwS5kz6MRKRyGuTKcMNiyK74qiHLZIjrLrGGAG1wv0YWonE1ITy0HmsPqygNcYHWZOfI8iW8ni9U6F7tG7A(U5sm3fXtyTv5IAxOwYdh0TFNJlzqaILvzvQi1nvVnuO)K0qJlJrGmklPtOqSmSqevS(4uUanLV3LOL1SGqY3ojcCWl(wfLX3(ejko4Bynu8n8vIkLdOZdyGScgBalJBKucwiIFpOfAsZO9GODRkiNUcOvCp3uGlW2bg5xx1gLwb6TYxQgdVUBAZPVwZPLvZbvYggMD5xT0QRZa(v42QD7Z7HFPAnNDLxtBkD7RAkDS7zqr0H57b9AJUnmB4oh3tn4MJh0wwkh0CqBVncB0aSNATS18EKydFoLpYtE4ezFGvPHhVE)FqB6293UtgQNnmubUppv17R8UTvyWfv2(mzGB4x2snaE0SUydOe4ZmePFIKAa55(G0vbjNRfCvnKyhdL695W434eDShyJglQUvON9U2MSCNCXLN(7AuDTgr0BnYO3Ct2dEes0xW2o8KxLH9(cTgxpIVZkpMfN119c(jwHuTNZ2WWuDCA29Gh8VYQJRdcJds09PS1gVzAH12jrnanpJmJKwe)aHLeV(7rr2ikIB1x729aIc71EppThpTX71EBq7r9BEsonY4ejnsBW8L)KtQ5MBwsYhUcq(ePu3kTfZYbfPQhQMC60K0kSXm2MR1yMkAmo7k3U0NQz30X2oRL4DSPmDQ4IpqtOSz42GmxYkDtuyUZezLem6QdR(uv(I4e0ANCc6Unobvt9hVBs2FW(vLuBlVp3oxmEjS7QO2SoA4Quj71AOpOzdHsJtNxujdBoYADt6xnNsawSzWV8FmNSOG87iPJtpn6pIPlyLVqPX378T357vX5RQd2ADfFTD(0TVY0cwMPfPSSnbfy4h1MnZD0NDntSPDk8TCi1sdvJziSHzuC4hDmrI7IBV2eQIPI75IcOpzJy9OMf5HRhvyB84LMJ1GLu1SuhyXAc8utViySrsPWimRfvH7e(tZmxzmJMbjFp4XcpOX6eXRWEgnB3RLP)PWsE4hDKUaJkZC6YRcevpEIykeB33javHX8YkNiXo1nrI7is9RWyfQlYYUpbCgGVnAMfbXa6nTbpsYYIswvqnapAGhyJxBcuw3x5szQ0dBs1LRbf)tqq)u8CEcG3WcDQMLVuipB7SN3yjhDh3KQ(aC2XfKlRMGPzpqAEyILAUf6poMTA3LOXXdCGUxjmu1G7vbLnx0tocrXWTbi7Eg4NcDNdwwvPEBhYEBc(SmjiKGoYK8k4hBm4J5IJskULSzr3apA2sT81xFCinlfn1SC5J1U2qog0x1bvTxFBSiTCvDnXASXV5TIGCQwZWabWCrSyUk4wkNJKMgS9fbI9VrYW1t411IurejQtNoRlELyr)vpUU(I4ZCGhQf1hxEU5cCUJ(XvKCwqTbo4JiS)AqNJ4jLUx8v3xP1VgbPguzBbOo(0TfRVZVEYYLjXe10RkMdSRU8xG00RgCX)MBKtYJtVJqfT0o)s0kB)VZwjvr6sFXzdxDLyXOp5vNvM4n9H2F15cdFhyPjw8Z)YWsR7EwAVAS00YeGGOw39e12i(0RorTw7zPTDS0eOTxtkW4ymaxXLo3ooqLD1dFS7zPfzjmInlGQVDNdHRTymDbMamm1mlovUGGrFvah68Oykp3fHl4luF2T(oUsfHchKaIVhjrStByXEumfXxZRxgATYnIbYkUlJ0xR0vZe6waq24EO6akxFUuRhrCD5S0WrBZPmTXb72I0PwDge0WcmYJzvu5nVVmAFulFR0g2q8WCPvehpCQkeEJ5RvwdMfFRwhbwHL3LeQ2axf9CYx3E1yQgCAzqwJiz7EsnDWHWokTBtEEYQV6s1J1GwUmPOqPSsk6vxQYgkvyRDglZLfljjjSMlLWY98)3k0ih(J0LHsWtEZzjmucQAVheeI7DsgKI((mqT7dKB4a2ltS3eGFDAqbDyaRLixYXxtsy7dt0LGIeQfUgtwehExky5WALinRgOeqWA2o9ei0flW)dIcws5GEy)081TfhBk8Gj)vW(zrCervtdRoXy5bIqQInxW63OLLcSbPnujyojyoXAx0mKvDRrSU)6y28nU9e00lydMGMw8xNTCl2io19ABDWHDeHAylCsf9PqWSQ(c1VVEHwLYSyZxTKgpTEplZIXI6UmiNf1vTy47lua)Pub8UU1q4w23z3lGvQMXEhH2rvLDx3wFnHmtjCGRSyJ1YbchlgeRRfykQ1QzbD3JXmSMBI7)6AVzxggqn3CG)OJQ9MhXXhDTWGXqR1uQd9hDCT3SV)OdxZIwhvRUww2CR6Q5nb1HKxYqduE13(1LB4R0S3VnCix)e9l0YwZ2Fnu(ELPG(YoD(Ckr)0mN6njTbgmGEguGRNsZUXfUM5uVHKH)Ni5L1sgwNm)ZHiCrsgA6013j161UQcStFx1H4vzKsv3RVowvU1mN8opAcuo6B7uYBZHUe9SZE0Z9ONnWrFp65X7rpRIE27xx0t4YWifirYKYxLA7SYhEGsZ1VFxvsP6J7s7mlpHzou8uCR1tdItkGXlrdxy8QwMNnloHOB3j3iGAjSeNbbc2DWWofeVnQjnQ2Ytvanc52Bp4zbrKZ4sg(S3NTQGGwbJXPzbpnhAJNci4tv9kQhuB(pWrSoNCfVTW87zN4dtmo2EsYkVNMyQnfIuLgHngoVRGo9W4Lbjq3E0)9308T2rT00YXOi1st)5rlnvEpnXSHAj8Xz6PUU1tdv6jqv0afLdZPnQOg2mfLl10qt100MymnTrgtY4yaahFN7ZN6B5KNuj)a()9XQAQtwvSCsIAM84iEIk0A9o3G6Ahww7aFkUwWnDQgnvW1tqQBRTGH4Asy36IsifFPC74eDARjX0u6AR7OSQ2PhrerPNQBRjmAwtsZndh)2IDJ(rsNnxTnYUHFWvvZKT87ow35TT54uLqLdgp7EIV04fn1GY0pzu(RzuunL6vJhTfYskUandu9sBGNK29kdYbA9XZezmfrftf)9qZaDBXzPcRS3rEu8Q9oL5hp5eXrrLi0KvCi1rCLqtYLeoeZKAyBIj9wY28iNDswA4D3yunzeGldHoUQgeNoh9lnClO9wjVYgT5DsSvNes8ZpKx4JXsZmEml4HS8ykHTE361UBRELxtd5IOhVWcZyhciZZi)t3YvNBmWC9th26dmBXGO2WVIimQTKxdooolL(kdEBJlGllwrVeHI)zFJFXKYQNPMMudQokBRuD8UEQdWrn6RV9ydOrDQ16I(xnKToxal6FA8JATwAaoyF4iZlw8mQKXJ6PP5inznkozJJ8Q5L(vbJ6YWK)DJyEeFLvi(DNJoY38CB7LzSl8Gu1cvwx2REbqpDeqylqqDc0Tz8XTXQ5va20f(sfMSvrSEJGXU2EmTUR3qWOBZaPEnGsBcWP8uy(WwMGO6H3mGnxlZdtWGNvAJRGGIdsHmD18plxRXiX0vZMvUfy138eHj4VM94haz(lT5h1(LBBcZZmF3PAQbBs1CnrFQu0x8Co)r20UtOJte01cxxnzeoWRKyuLnGYK)S5DzW2TPcmW6pQwqwNWy1VG9D1di3ybd8nY)JdFrTT1GC3FmW3XciRYUiyOV7DIGnb63kavtDd(0zDOvC7ezNJo6ao6)TzpdiRjoyMJDmGXwJPA0TAIqAKbpTT9HneKlRixlHoQo2cU2)PFPp2xRd3aY1xaFZHMp4Hmmu1M7KN2B9ePu5Pp2(shzFPESlPTjWQSPXgHFZsg0Q)XTWEYr961VxpCQjaOJEdoCWXSpAjTpUvVEhI2k4Lp8q2P(6i1Mnt((gP)HkPLTKmW(sTDS1hezIXJnjit4jjYYyg5Kmx8VLPArd57iT1Dz2kA17eNABlWlTLnO20xPok0Vmvg9AhtuYqzWaJS6OmeX8LzjPIMJ90VxwjCWrOOpDB2SsHfEcx6YEvyK2tgjvC2dUdjiYOXQPhW2nobkmmVYJwt9LNXZBGpmxxjXrveVQ7(p71xqvU9nN3U(KBAmLrgJAYfNQggAULDC9bwrlF2JmsEx7b70KXfzfiEZJi6fEIBSEHcMQDqoXB5xDe7bDO(yPS2rEytm8nvKDftKFUg(3Mg)Zq14Fy91nEMl1hWYAtWKYXqNeH0pY9gpvnPr1mVMshAhBiUN7OEgPoCyFRIEoCp65E0Z9ON(7rp)ha9uDWKVh9Cp6PJU49ON7rp3JEwBg3P81mAUabf)hnGPCYdKGKjb5ZjS1Mc(OrNKSCraxRWUD5sxP(Kkm136tXg88ow1jzpWlOU36WYZyjwHY5hk1SVDDd1YDh(lwlAjVC)S0wwkBgmHdGCUZxU5zpvMypg2k6arlNgdwN2WRjf6FtzH6NAGMxolnrooPsVM8xpDlEVNU9)GFzUwD)VHcrH7KqT1WQA7Ze9iWwM4Rj0GX0BVXDAcF7bOVfNa0HCwKA6QcpC986DnlkLRi0MhsdAMiOwzSy)qFu5SZHvpElEnpKFuzHxaC)LHdX0sQbiSHjsN3PiN(CvVsnbHXx1PzaQB23tpVaEimZQJgW(Kk3K04TwRuwB2oBQ677Q(6aukfvvTkEfTE7McOsLFl9Ugxt6gESAlCVoYEd2QCV(qjT6FCPnkwVu13TSrz8vlL71t32PjN6stAVW9Kwb2gasHPCAtdQ(fCRVwwKzNogtSwthB93IVrz4RSrFk(6uEsW3X6tXhxo8ktbohNM9j)0qov5Wpin((kFF6Wl8XSm2gvHPN0SEW79(R84WB4pUmnI8dwFTsPuVU99NCXf8IPCoBjKa5xU7(IFx(o5qAFjM8DEN)n3GN6tCXPYbV8J4M8c)eM(dbLaTJ)p8EDqSPFugEL67)))d]=====]

-- Import the baked-in profile into a NEW profile (non-destructive): prompt for a name, then
-- ns.profiles.ImportAs creates + switches to it. ImportAs's 2nd return (the error message) is
-- read OUTSIDE the nil-guard so an `and`-chain can't truncate it to a single value (err=nil).
function ns.RestoreOwnerProfile()
    local L = ns.L or {}
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
            local ok, err = ns.profiles.ImportAs(name, OWNER_PROFILE)
            if ok then
                print("|cff338cff[UnbunkUtility]|r " .. (L["Profile imported."] or "Profile imported."))
            else
                print("|cff338cff[UnbunkUtility]|r " .. (err or (L["Import failed."] or "Import failed.")))
            end
        end,
    })
end

-- True when a backup is actually baked in (lets a panel disable the button if it is empty).
function ns.HasOwnerProfile()
    return OWNER_PROFILE ~= nil and OWNER_PROFILE ~= ""
end
