local dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"

return dofile(dir .. "../i18n/po.lua")
