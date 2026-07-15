local _ = require("novel.i18n")
local ChapterListing = require("novel.ui.chapters.listing")
local DiscoverResultSet = require("novel.ui.discover.resultset")
local SearchSupport = require("novel.ui.search.searchsupport")

local ShellRoutes = {}

local TOP_LEVEL = {
    bookshelf = true,
    discover = true,
    settings = true,
}

function ShellRoutes.normalizeTab(tab)
    if tab == "sources" then
        return "settings"
    end
    if TOP_LEVEL[tab] then
        return tab
    end
    return "bookshelf"
end

function ShellRoutes.copy(route)
    local copied = {}
    for key, value in pairs(route or {}) do
        copied[key] = value
    end
    copied.key = copied.key or ShellRoutes.normalizeTab(copied.tab)
    copied.tab = ShellRoutes.normalizeTab(copied.tab or copied.key)
    return copied
end

function ShellRoutes.isTopLevel(route)
    return route and TOP_LEVEL[route.key] == true
end

function ShellRoutes.bookshelf()
    return {
        key = "bookshelf",
        tab = "bookshelf",
    }
end

function ShellRoutes.discover()
    return {
        key = "discover",
        tab = "discover",
    }
end

function ShellRoutes.settings()
    return {
        key = "settings",
        tab = "settings",
    }
end

function ShellRoutes.settingsList(args)
    args = args or {}
    return {
        key = "settings_list",
        tab = args.tab or "settings",
    }
end

function ShellRoutes.readingSettings(args)
    args = args or {}
    return {
        key = "reading_settings",
        tab = args.tab or "settings",
    }
end

function ShellRoutes.introSettings(args)
    args = args or {}
    return {
        key = "intro_settings",
        tab = args.tab or "settings",
    }
end

function ShellRoutes.cacheSettings(args)
    args = args or {}
    return {
        key = "cache_settings",
        tab = args.tab or "settings",
    }
end

function ShellRoutes.downloadSettings(args)
    args = args or {}
    return {
        key = "download_settings",
        tab = args.tab or "settings",
    }
end

function ShellRoutes.sources(args)
    args = args or {}
    return {
        key = "sources",
        tab = args.tab or "settings",
    }
end

function ShellRoutes.downloads(args)
    args = args or {}
    return {
        key = "downloads",
        tab = args.tab or "settings",
    }
end

function ShellRoutes.chapters(args)
    args = args or {}
    return ShellRoutes.copy{
        key = "chapters",
        tab = args.tab or "bookshelf",
        source = args.source,
        book = args.book,
        manifest = args.manifest,
        filter = args.filter,
        sort = args.sort,
        error = args.error,
    }
end

function ShellRoutes.detail(args)
    args = args or {}
    return ShellRoutes.copy{
        key = "detail",
        tab = args.tab or "bookshelf",
        source = args.source,
        book = args.book or {},
        text = args.text,
        unsupported = args.unsupported or {},
        loading = args.loading == true,
        error = args.error,
        detail_page = tonumber(args.detail_page) or 1,
    }
end

function ShellRoutes.discoverResults(args)
    args = args or {}
    return ShellRoutes.copy{
        key = "discover_results",
        tab = args.tab or "discover",
        source = args.source,
        source_name = args.source_name,
        group = args.group,
        books = args.books or {},
        unsupported = args.unsupported or {},
        first_page = tonumber(args.first_page) or tonumber(args.current_page) or 1,
        current_page = tonumber(args.current_page) or tonumber(args.first_page) or 1,
        no_more_source_pages = args.no_more_source_pages == true,
        loading = args.loading == true,
        loading_more = args.loading_more == true,
        error = args.error,
        list_page = args.list_page,
        list_page_anchor = args.list_page_anchor,
        list_item_anchor = args.list_item_anchor,
    }
end

function ShellRoutes.searchSources(args)
    args = args or {}
    return ShellRoutes.copy{
        key = "search_sources",
        tab = args.tab or "discover",
        sources = args.sources or {},
    }
end

function ShellRoutes.searchResults(args)
    args = args or {}
    return ShellRoutes.copy{
        key = "search_results",
        tab = args.tab or "discover",
        source = args.source,
        source_name = args.source_name,
        keyword = args.keyword or "",
        books = args.books or {},
        unsupported = args.unsupported or {},
        first_page = tonumber(args.first_page) or tonumber(args.current_page) or 1,
        current_page = tonumber(args.current_page) or tonumber(args.first_page) or 1,
        no_more_source_pages = args.no_more_source_pages == true,
        loading = args.loading == true,
        loading_more = args.loading_more == true,
        error = args.error,
        list_page = args.list_page,
        list_page_anchor = args.list_page_anchor,
        list_item_anchor = args.list_item_anchor,
    }
end

function ShellRoutes.title(route)
    if route and route.key == "bookshelf" then
        return _("Bookshelf")
    end
    if route and route.key == "discover" then
        return _("Discover")
    end
    if route and route.key == "search_sources" then
        return _("Search")
    end
    if route and route.key == "search_results" then
        return SearchSupport.resultTitle(
            route.keyword,
            route.first_page,
            route.current_page
        )
    end
    if route and route.key == "chapters" then
        return ChapterListing.bookTitle(
            route.manifest and route.manifest.book or route.book
        )
    end
    if route and route.key == "detail" then
        local book = route.book or {}
        return book.name or book.bookUrl or _("Book")
    end
    if route and route.key == "discover_results" then
        return DiscoverResultSet.resultTitle(
            route.group,
            route.first_page,
            route.current_page
        )
    end
    if route and route.key == "settings" then
        return _("More")
    end
    if route and route.key == "settings_list" then
        return _("Settings")
    end
    if route and route.key == "reading_settings" then
        return _("Reading")
    end
    if route and route.key == "intro_settings" then
        return _("Intro")
    end
    if route and route.key == "cache_settings" then
        return _("Cache")
    end
    if route and route.key == "download_settings" then
        return _("Download")
    end
    if route and route.key == "sources" then
        return _("Sources")
    end
    if route and route.key == "downloads" then
        return _("Download queue")
    end
    return _("Novel")
end

return ShellRoutes
