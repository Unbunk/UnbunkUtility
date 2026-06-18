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

local OWNER_PROFILE = [=====[!UU1!TVvwZPTsw4)oZ9H4siKa88MXlxtnjaLfo34PsP4wOgqJfsusn2X5b)BFoNErQ1giSDY15wUsvXqVEw(oBD342XDMRdX3poY156iVTr3DnlimG9ORZ90K0aO9XDCD8jmcoY5XrPXHu8JRChp4ylOPvtyRGH66568G7yltdxhg97SZ9dyXjUdXrmnK8OCiZxD6ksuenK)nsyy8do0q6CgUvdDzUothnlHm)oAcFd9xFc78iFCDybRPjNghgZ7HWjSe()VK))E4)Z4Z5mAk8bAAknIfqcH(It8PjNhr8cP8flDv8dJMZ3tzNvxzd(kBWxzdCL5uWfXrmNGFqDhJSkvUKaZSjo9g3XFOJn0CaS0)vGpdKswgCs6Q4h4RBq08WT(0rrN6VgNfFnNSLfgerDDMC9SpoA854WszKO50lcczcrH)2OLubbNqc4mHhHXcPltI3kKqXBz(XCHoJtoFbjNbsY5sAWYvmb9KIZys00rzYvKR(puqTFrqc5PB)uCuSsWiy2oYzbdcMwrWY)(PBNo6PB)xxc7WFG79LusiBvkloIQPmLuuxPerOy9EgkwpkaBeGkGQyWguvawvbNXhTwFxf1G71jrZxbZ0z4KzZM8PRg9NxotYdZcqu(mC9W1fe2DSHjnNeIB8rMObu9CPXrdmZ2xyEMQfqF(w27yb0MntsOTqKYhxT6(sy9owVgysArdWty)xAsSMTtxJI2oDZXQxrj(pYDNKBlPaKI(QGj1qHpDlFmzy0IMHd1ees21Srltj9CDkfNNULvg1cKe29UjifL0S5NazVyrkL9fUgwRHBKq0njbrSRtjl5oLjGF07PC)SB2cnWeY5ZcwSaj2101IgH5qtUhCmc4l4RNsszdjkB0a0x8v0qcFTaJaglETRteznTfikuGmvUiUoH0finSHKC3SvbZVlc8jZb1ElNbbj2MaBWqkdOMNUDyyWp(bjXVk2dugRc8PzdyybKKhjzhRfXNSHXHtZIlesa5NwPWxP54Chklqopd7fjjCTVrOO4koc3LrjcaNHdkzkhps4N0qSmvPN5IaOL0fEsDXf9h0V3Gbwg2wDS6za(mw8b7UOU6I(DT6BynyGr3b963X(yShBzOcoEYzoaeEfxxmpah2JHuNnGfWN7OyuNn0WWXaZHn8GWu3eMIq8(fLG7dD1vFhska8XPRaqjz262vGs)tYg(KuaHkQ0TrC7KKTBybay71tWGz5eJgiAbh1a0hUFwVs(zxXD0uibQdio7bf8OrhKzoS5ACCO1JZ)GLHrTrwFZfuTH8pkeiBb5(4KagDKpSFwD6AyL3MwIe0s5uul(BFbf3DygiNmoglpsZHg5mFf(ff8SMCoEzrhNhVgStqnBT4R)omo0ngEJHVv5N3hXBm6Ajg2CWGI2T1Krwt5LxRMRInYG9AJCqjl2KDXPC0WlXUO8k8BQDbOQsavfX)KOiyJNt1da59CcanSuaO5QI8XukjjSh1Nzk5rXO4LxjG(IobiSC4yqACCmmR1uE(ToxXP5GOLhD0rs)XtKRGZvK5qsvY4PxKG5wGRAHWScVA8nPAbQ850bYYR0KeQCKEGD8mkHT6KqAc3NcgLLMmLJgn7BRAy0bl90cF7HBJ)M09ViE7FrMQsKuqyosWD9(7X0MplG6NdNHvGZRNTnHWtNhLCILf5y0nf8nnCjyhde9DnVpZGElVlcAty37Oat6nQ1qJ1SFKDUNxGMQmXmjrwNzBfsXFsbXeeOpqGQzwFXXWW4EdlL4gw7dGqCDgHjoUGmN(1t8b760Vwqs81pr9diFfxH0VIBjkroITKKx)fqktM(TtpF8SZVkVeKEahSnLE62uSKmVSKNTSvz9vFbmy7z8OszRZLVwmJyTBl7y3e7ioTnqWuc)1v0Q2rW1t0Ias21wOHBgaE2uNY4pC6nfpxHRYONQcxS1sikPrrTOgnKPY866isAAWYiHVxf)vz2WWZuHC2qO)GMRsuqJ1yQCKLkTbTkLecpD3e1lZ3VdP24v7vcMb8FBXyDTRhJzQzYOHNmXwNLeeDhL9AvDw5GJmXYZZ37xYbCxoHTAYNqJbF7LvA2XQNggJus3gpGDZQjH16t7Dp5(jbfvs67GZOdP3sNi9oYMBxj0MrskArKbpkQYHzMVdZEMWmR3Hz7eMDSSwcNnuQ)zbPBGk)k5SCrU2VxMm2gLXI1G)Xf1rrXLzvmccLrcctbx4S5RkTtBsIxeesZbtli(0ZetGFG4zhfGwHoGNCgf1L4QJtyYgOocS8JoyXLO)7nL2NuqdJ)v03W8KXNlIWmtitWcGwsNkik9WgLwU8adzlKw4KsXtzzSj)WtDMckM5bBiHGQX))9hzMb)mzDpvFE5r7EzSU2cPy9Q12SlwhNnN57wM5hwhZpmJ5bkOc33k1Ux7u7E1Z7Ev5DVdH3DZppYH4jUGUKGLFnjAlj888nrMPt3E4w7RFKavCJhR1z2yVrMuOmrQEQHDJ2A0chEfDcbnikPwCzjn6UyGM7ID4fxlE1lpXSSlEjHcSj4SDYcz5)EIBGsVPHhGJRHxrt1FvdWUZUOGRrnhW(v9adZ)hpDl2ha3XeH3UgCdhgKYA(UBFMr4ZdO4NhwllcIAlZJOFGWGwM6aUpoGa315eVy8wit4hBkBBQO1R4yY6YWaNz1WKAym(aK3eKgiJFONAr7TfJeSTuburi5oEihho8ZRe8d3VtJJd9JFi68uG3qNuqn)g7o6FZ5siGnQejYWnfYsWUMKdRfuHuNM2tEyX2ICnxMq2Sk7AOFiiYTYLpRFNZ5xpT6kPfOXtvot50yQyir0VZWJkMdz92UyXFI(Gtl56qZpSWjDEMaQu7W3RtaFHC2gfgdwJIt7efhG)nZYyupXDd66W3WNUTJMhcourFsT2ci3ri0KOYFKsTSSTSW2h3X0QFFZJ5F2QNHnKMfV5JnSS6RgrV(9owks0of1zfgPz2Q2vBowA7GD2oWVMuPIaLXNUyPqwopePXfaedSy(CxuuRui8AL9PEBxETsCc9o8J)eE)wKWhipM6aWPCNsV0xZL0NZWpwa3xBTk74PD9gRmM9wHslkg4W9KvFG0p0XYOAnj7XvgOoQ6hlmo2pemWZlbPYLmVhpHFSCbvSs3zqb0Q3ZaTw4YV2jcvDV3DF7bFQXmifFSgtUNMKGrEfjiMXwT2yBh3zxzCA7VooHcSsPYfWgpRiZLXZ7V4Bp3d7PGPi99)kWQKwFL8P9PlOrPb3tFbhyPwDOLKemjeGdq7AzAcWPsE2B7DIZcGfwDj8ZMm1T41H3AW0oCw7vbEjEywmr5yT)gzREhSWsOxd1bCdSI5w7Bbi7jJ9Y830WRn438hWAJp0o5BbipYSPHrv7EDFUnL4(WcA2BYvxnuyLSNsfUL5dGpa81icvPxoGR0TVPHAlAH2U6D3dzSB1DWBylWHVBb(Uf4)OTa70XYS37wGVBb(Uf4FpwGzNAVQQn8pAO)e69uOWosYsQ4CAHH6Fs4MveoVj6o)yCxfFVyL0Htd1o)HurAXjI)Ufif8dBL)s54Pi3Cs2AhX)oFEecQ6tXBtPC6ruiTGyEDyVnko7Nh9c2E3j(Ky)D4x0YmC)A(n2inAoYuqyxuZLayW38I9eev3pBUAXSAvhK9AchfPEpNTSePDwHyC(ndiG(aT90TXlY3d0sS0vkizP6UcHQSw2rpc928J7PJuwA5QooOXIFhpOdTofJA59Qf1QSxNAcoPFSzwVkrKSS(PerQG7RdoIK(nPSR4rzEe1Dq)7D8h(z7OEd54NBDUm)IcmvixJdkTGNBGkiRjlB73n6E3O7DJUFzgDm1tC(k8Tyuk3P8xyGPPsiYFWlnRFnSpoxQHRll7D4oow825FozquoFkbr6OLDrd3qs1dtwrgLFHwgs6n)X8AlSMljuEwVb3XX4w2QNGRz9pb3U8e(Q7ruanlsdN)dUOe1MLrijkyTgwc)6hJJ3K5BSuFxm1raqXVu49nNlTGE(l17dw(9SR)pR8QA1bxCYLxkMWOiF63L3okyK95a6dYu4ZCtbF5r8(XWF0iFxIS(23sPuFb5QkTqoo(taGpo8DqK7NktaBLltTKose)Z9))d]=====]

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
