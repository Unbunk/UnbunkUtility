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

local OWNER_PROFILE = [=====[!UU1!T3vwZTTUs6)oZ9H4s7wEEZYljUUjYUSuY5KPsPekrijoMMudjKt85H8BF6gBeBKck2jxForvLkwIlanA09x)HglAw7ztNnjkoopB2K3NnFB2DVNMKMqFC2KhifLjW1h3E2K4iAe(KZJkEDr(2nL4xwMKMEozz02uA5hApB0SjjlYZoB5k4M0ztYlIjfWhh3M)FJ71UxN(Zg3H9Pb9hoBCx4F960P3a4sW)63R7q4nh3IvaqrKr(g9Qy8vWAEc9XuIzfUskmSkzs568VE(2Iikk3WTJYwSoVyAoCNffesgRyEdjz1AOw60c(6QZYtZlykbwdDou7h1UfuHRuFQq(jqIkPqHV48KYnPrpoBoCHnrlsYWhE2KflXIlnAtjjgREMckPGSGjptU9Qx)gOI2Kx(r2JdF4pbfql4JjX8ApQyk0K3wqMnzeHsjfF)lJst(R)kQiMDxxPTTqs737eHKYKtSN4M8YeEn)2lUCktz9vqCMn58R)JXCL14O7jOKMH)DcRR97FPn)1FD0gwXxqsHscQmsA(xHBLbgg0lHMg283MLMV4oO5oNjF)rsmDnOAbDlVde0wpqUgTe4DyKSO5PCTdVZzcRJr0RYFMOYYKvzsBG3qIsPRlP5zKPfrqDXA)lIV)u6fzS6f6twCNLMPqQzKAjOKwc10fFJwevI1c28NGVj(L5mJv3YOfx7YTlWYGMCpPGPoo7IXtV4wOCY3Mf)Vjp((sILl0)93)IMW)9V8F9gWW7FXvUcfv3wgQeuMUPGuwEnOJLgyOmEzEgDsYFra5Qdke0uINlXKRPxFdVGMIxIvccj8wsu8J7qgzptLOUc6YVOs(WV6rjD0jd001v6PR3sttYa1Y1VF6BVA8fcX86Ll)tMsfvesVrutWLA4fX6IvcyJeK8ztUmPi67F5D5z5cncuiLekVCW3dEQ5jzXLydMxl(RC0)A2ezpUqbkQTaSHa7UZjLuH3WnqFeiTcjYFf6TjK)GbqHuTWXf4I2fMMfxTGdPXbnEv3ET4DhtFCduLBs(gjv0kMUgSGwNNgxHlUOMgwRJg2XSpdUtFOc5Qfguca(2ujy)6AVDV(CpylPsVHj6j5TBLLUBpoOaoL()qkYXUxoa6RyaNYs4pRkbMxWORNo963jqCHoTBbOluKtYwKUnMCv2zX3RSYMMaH6ukRiQqjSikvOfctbk1vybO)(GEia9hveEzXDNYagTAdjzW9YwqaGxkhcmEB2kc3OOikHPpNhrbdjmOyg775BPX55O7evadCDgItnIdgAzdk83e(e9uVbh3qAMgGtIMd6hfghqqK8O4tZYGICbbFDjS38NJ22I1rzzKugTKnrf0h1FZYOh5pLgJe(nrIf8hhOIWEo4PUhWFJwbov3YKzi4(rhDKGQb6TXQe23mQeqTaTfwV4Y8fBlhTfua6nuMiSQiAZ63ZkF4wFnHhMJtCjz5sSKsYaLWdrPmPBXMT8N4EY9YiINtIORpnfIcJLXAa(Mfscu1DoUV8cxT3605v6uSDmjEt5UlK57UqUHHy1skyterJ8hicz8CEcjUkeeucS2QIxhQw4fl2Irp1yLcHzCk4gcpJM58qW8nk7U6R9PWDTRBUeZbSMin80VO2fQL8WrD735KkysqSCExLksDtvTHc97KwKCzmgKr5B6fUeFhw8cdRpoNqqtnBYvOj2YOfKpDAm4Gx(jdLXNEhjoj6tyju(jSkrLYr0vrmOxbLsGMXNLuGwlIHpaAbBljNTfitCpAk8volhwGaHa7gLKFDvBuAfO3kFUAm8Yo0Mt)6Ao8WDGIXYWSl)QvwDDgWVc3wTBFEp8ZvR58BMeAtPBF)nLo9LnfF06AFYazyUoN0to6OETBpu(wE48ax1Yew4i61mvZvq6O)(m(aa4XgKkuN3gECLndOjKgmWLDfk4I(AFChtlwm8UlDel3EzO8QhiHjmM4imhYDILUla5kpEH1fBKEa5MrixuKHJPr19rzBJsVqloRA45Egv1LfWya5JI2DehF(Z5pmHqI)a3iVwcDVGjGArTPI3yxdEOVQTnD(PV5QZ(3stjQv)nmWvswjmgxEYloO92L27MC0lsyZDw(9GfFnAnBY87qp(YvBvBho843gTijkv3feR3)b2q971WY(x)dUn70TXV6RD7EafJdAVDP9maD4H((ng0HISeI1tG2Yc4DvAe3eOugygwnYPktcmsvQxXC)sLPwVEh3oWwI6yxjEurlEGMq5Yp1FAeDZsziAMgYqy9j(R(ei(Syh26jzh2Tg7q)z6ZidE8ojvw70tF7OznKhqXOwWUnVzSNjGcHTqiSoj6vljWAqkO1eHstYwv6MwmvpuWzaZor(JeED)8DYIJkUJKDD2zX)rcDn7blv68FND(KDZh85(v7Z1e4NYv8NTZNw74ZFEdPy0wGmGyghDmcY1cog8CdQByNxL9BBTHk2Rm34JERVj2Cu4icnmXMUPW3bfqlJbotkGLlV2mx2R1oalAEshh9wN5A00l9N4unQeDBOV6WImaDSMs0qMRXAa8df(snNJGjnjJcJxSbxQ7FjnDwwtZzu6xJESCcOnRC6QajCNKZ2ypLWcE0BFHpyLAHGRDc9dBAoB33gUwcMBe2xohND8nhN6b8Qp(2tFA4CMqAhG1GbtL4hq)Ul4rAEEC62sQwgwdn2GdPfUdw1QAQYjBQb2O4J1TsvmxUt1SiMSwUs3X7r9Bl4hZqUyCIMN)aj8ieB0Sb1FCmh4(FJW7OCJ2Agcs0kROz7YB0EHt5jkLfSRbKSSgCGdDx)xpnkV3h9TBifm)SbpdHOSx1vvAkjfB0jycnFJws8RpmLM5uvRBJCUmcjqflkjeGSNhxzwSF(9Qj4JnGUCLX1EMdDt3L4I96QBh0WdWM)zjwX)XORlq)70Pttrmmj17gvqSUcf2rrfundj9LUNzic1cfKxmF(nG4KgTGGsmPq3VG7rlm8cOpr8KsVn(6s8hJLVb)o5INbABGo6DjR4twNyrI2waA)Xt3SjnHRT1MlSBU63G8VRgKX)KBKtlsYGb1jAPD(TOv2(FMTsKwgF1kiOrTvSU0NAUIzRXNV(vI(pDQzI1j9bQzbsntBuThyNfa7SUnWoR7tND28dSZcMDwF2yZpWoZx3Rn7mb(9RB)r3XolU3TKsmgg72IlDHNrDBexaJtKNvMNY40SgQ(2DogU26RPRX0GHR1nCficxJc(rxeNqzzRaEc(Q3N9ilwFMCfedFlkfCVMqsfBChwqxfjrSAQjcqOq(nKV2DTSSXnTK(kNEpsiRjy5tgECx5xToCWGJE56Ve2CcPHy6atwFQuLElYupoSLt6l3nmPwkmRhHSXu3UtaX5knfdqSqdoDwyK2MRPRnF99l1MUCf(rYSPV0PBgJSUDVXCZjlj0app9SC6qRYbI2owlpf23CLQfgGCktak8woja9MRuz(uipxDol5LLBiPPm(Vucl3V)FBrZD4dzBwi5fZBfBGrrqv7eHOf4g1JPtz74aRndQQDl3Kc8TJGVNsF7laF9SOs6OiwBvUeLVLKY2wGOEIIi5c9101jlUld0Rm9as)ka1K5gDmLSeUwuC0gkhwe7lx10EQCVqJmnmxNetuL0iJHLmViseXvSzeAENDwjWweIrLGNzPY3IOpeSxdKsSS)iFMiR4NeGgNfVAtuH2gNSgmqf7wSQCLzXM2XxuOociUJ7uvVQ9n7cWKQPxQFFnEiGsNTVHbosjc(d8ga4Oi39RQfdFFHw4pLQLx1TMrQi7yCvXOMrZsUJO5RkYUM7Uww9P3nSnJ5bvSDdnzUpKcVnukdm8AXaD9TSsXYUMv9Dp2aMQ5M421UH1lo2EQ5MdMnEyT3CipKHVLdmggUM364zJpP2B2F24JR9MDzH38Tqa5gkMjvb1H6BpJNCmdkV45r0)5of)nUHKfnZQjoRPz)FFyx2809RQwR58NJq02yyu75YjQwMNwPzQMrOrRB1GfczZAghqOiP7Xe77Ucvm5MArJQH5wFxetvJqiqcP)NilI1SqMDOo(JqiTmnhxXeD9ZZRHPz3E4b(g)Y9VKwDgMBiypBMCxkTbrukm(Tbpa0k0Zohqp9HEEYb0ZdONVSqp7Da98fd6j80WODiXY03BsTDzvx(aT8A3vLjS(4U6EPpRGCB)mkUv8PrjPLWqQOlwBvvBkYxMKs09fKB)pTuAIZ1abTpWIts82QKQOwRofc0iKBTjAr8)OyY5CjdF27Z3wsqZYRXjbbp9hAJNLi4tzEf1dQLyECuRRi3WBlSUE2rbHPaYoniu3ttmnNttHgHno0j3aO8ls2eLca8X)V)ln)9NOwAE1yuKAP5VC0sZL3ttmdulHpotp11VEAKspbQIauuEmN2PIAuykkFQPr2QP5HymnpiJjPNVXaETk39FuTZTgv7A1wP7z(84YMv2YOhYlsOe2K13RD3w9QUMM606evq7q26jW(INMGV)fUQ0)YwpOC0vpZRU7lZljzJQJaRMOTA3cmw0S7ysN9WlyVjOfYzLvWb08Va8vNHugemdJ4M305)3l2B7M9KxkBSJqlhQlAmzBnRPdpRgiiwnya5Gtm2uTMKNemn6PoqVmpbSEXr9lusAAEPY96ZcZt8atLYVaCZH8Pgs89odh(tc0KNk3Abn9a29CHJgoqYEaV6cjgY0q)lc2uNpHwyytGXxyUq)(cnBcexpe6ZdeTNabgqZYJtYJBzdk7fiUrAg2(8sNDpe1(XrqHlo6wsP(oMeKj6LgdJvtmJ9S9HUL8xF)l49azepqT2EpiLPjL0AYY1E63QNpkLk1xILKvPgiOf(DatVkFa6yrnjjMn7YSLFAblQaDBj)Q3Yai9H7Qz8Ofjalp5KsoSYye9W1ZRzF(tcfGecgpO9yVSl(yZrm49kY4eQULN(GuqP5SCWRm)RzxucAaCeHJh0QvTbySxMjgjjT)m3LDIx7gSEDsQ4Utbe1A2B9Xv45B9MzyWnFho4C5sBOp4KOJqZfOng2gi6U4oMAEpqYEE4BifnpNFXHrgWM(r9wh7AyCgmf2fddTSLxFk23bxdluL6x0BHqO4fgpHN8bLCpvNIh2y)nIgXUgrxyej8rOYMGsdSjCYYt18DS)40JQ)8jEE4rDTia7z9ZggtJ9aEMFkIElM5o8r9MmDCB7Xv8SCbwVvvR(ANnSy5svNQLJZ5PUPM0VV)A85whOKojWxHY6cWkfg7zFSLqQRoFmfueSun)qNWPJZXQmOd40o(pGt7YweIC5qEGKcxioPeVIYSFAZtuH29QgapO9UEPyjlHXYYeFwSkiRY08U6wgz1TOYbStcFvhY04s1xiEtoJfcz6PJeyMyZJmF7Q3l3bby9TD5YQT4ETBBD4)aWXEdoEWjyHoU3aW8SfMFD8YhFCNt4)qD0RFVEyhno3Z96Dmc9fWEQQgwmbSL2NR5WwiCynOX4IoUR9TuNAIk0adetaplcdddKVW(TPHS3dsHqhWdNN5sCmn(piCJVv2OCNenOwkcMCxSyFi3Ksd8fE2yBensPmm35lA7jQ)gfI2FcxmtbAdHN7ygjdXt4BoizXWluNDfK3ImGDi0AZJgkQ9pmg1za1seueDa12bz(IY6ZP1xuDpphtrVifXPwY2vq0p0Nb(kU0RbvfOt(a4YoY(bpM5dO2Y3o)SZy(0NiJnX3SOk0VPZQBTQySCecGyrndstSkEVS3j963UZjTA1zqRodp5KzlFfo57Mjar6cACUwwhcO7IPz3(qv9V)62vjvyNdAY)qZpQZmReFzpOTHog61GjBMemBVH6qJ18f9SeFQ8D5MVvtoRLnxpxZWb6xAS(pAsTST7)q72UVVVRnKZeHZkzcBEWNYPPuh8Pa98i(VGuzwkw5YVh4QyENKmFPqXRguBfmO(z24QmzQd)r40oYAueASY4iAGS99VKVSQouXxeneFRRf)HyV2KXh8C(8R7PNAb4BcgzIJS3NWuXRTmfSubm0ysk73)KXvNPYp9LkjdxxMeyfLO97iE1kjp6lIfFJg1YL2dpTbbZtRLDq5WZhuqK58M8hZ5nAxjas9O1ScYAE25Th7EObL2RuczXWlK1oP9(e07pPrnmVpgWZbgd7LbpqPxXlNuOPfDButbALN4qy(kcnBigzCRXPHs5yOf52LUIiPDmzWmFqgSXCpNkTsJDOz9rZlum)sJv)qo8Ig9C0b0ZdONhqppGE(cd9u9lsXb0ZdONhqppGEEa9mC0tMkd32afceu8pAywfKhirPtJkwryNPh4JgFA6M1rS2f)2QzHAY68h4LKUJ2iTK9ZpkwJk4)L97v6OQdApJ5XYnXeAtlvtl)gklLCp6KXJF02YgzZ4zs4a8M74LgOVptMZog6k6crRMqR2gpe)8guEAvjs4eZgzADtjClLDE)Hn4cPzIeuAHAmDyQKDvG5e0kbw4byI(LgThB0lU5e7NIwRwSkrHrzj3RbnHF9T55Bu(mw37YBMmJfGf)IXp3IvZ0mCh5pX89fFxTWZu(TEN)6lp9nVH)cxLft(wv35hsiFv0RPFYF)iUJgXFoD)MaT5ZFgpCY4IR2zrj(CDWvG33Q8HPZM9))]=====]

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
