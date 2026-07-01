local _ = dofile((debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "i18n/po.lua")

return {
    fullname = _("Novel"),
    description = _("Read online novels in KOReader."),
}
