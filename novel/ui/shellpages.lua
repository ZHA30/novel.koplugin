local ShellRoutes = require("novel.ui.shellroutes")

local ShellPages = {}

local ENTRIES = {
    bookshelf = {
        module = "novel.ui.bookshelf.bookshelfpage",
        default_route = ShellRoutes.bookshelf,
    },
    discover = {
        module = "novel.ui.discover.discoverpage",
        default_route = ShellRoutes.discover,
    },
    settings = {
        module = "novel.ui.settings.settingspage",
        default_route = ShellRoutes.settings,
    },
    sources = {
        module = "novel.ui.sources.sourcespage",
    },
    downloads = {
        module = "novel.ui.downloads.downloadspage",
    },
    chapters = {
        module = "novel.ui.chapters.chapterspage",
    },
    discover_results = {
        module = "novel.ui.discover.resultspage",
    },
    search_sources = {
        module = "novel.ui.search.sourcespage",
    },
    search_results = {
        module = "novel.ui.search.resultspage",
    },
}

local function entryFor(key)
    return ENTRIES[key] or ENTRIES.bookshelf
end

function ShellPages.defaultRouteForTab(tab)
    local entry = entryFor(tab)
    if type(entry.default_route) == "function" then
        return entry.default_route()
    end
    return ShellRoutes.bookshelf()
end

function ShellPages.build(shell, plugin, route, runtime)
    local entry = entryFor(route and route.key)
    local page = require(entry.module)
    return page.build(shell, plugin, route, runtime)
end

return ShellPages
