local _ = require("novel.i18n")
local Chapter = require("novel.model.chapter")
local Dialog = require("novel.widget.dialog")
local Manifest = require("novel.books.manifest")
local Menu = require("novel.widget.menu")
local NetworkMgr = require("ui/network/manager")
local ReaderChapter = require("novel.reader.chapter")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Chapters = {}

local FILTER_ALL = "all"
local FILTER_UNREAD = "unread"
local FILTER_READ = "read"
local FILTER_DOWNLOADED = "downloaded"

local FILTERS = {
    FILTER_ALL,
    FILTER_UNREAD,
    FILTER_READ,
    FILTER_DOWNLOADED,
}

local function invalidate(plugin)
    plugin.chapters_request_id = (plugin.chapters_request_id or 0) + 1
    plugin.content_request_id = (plugin.content_request_id or 0) + 1
end

local function refreshManifest(manifest_store, manifest, source, book)
    if not manifest or not source then
        return manifest
    end
    local refreshed = manifest_store:ensureBook(source, book or manifest.book,
        manifest.chapters or {})
    return refreshed or manifest
end

local function bookTitle(book)
    if book and book.name and book.name ~= "" then
        return book.name
    end
    return book and book.bookUrl or _("Book")
end

local function manifestTitle(manifest)
    return bookTitle(manifest and manifest.book)
end

local function chapterTitle(chapter)
    if chapter.isVip then
        return _("Locked: ") .. tostring(chapter.title or "")
    end
    return tostring(chapter.title or "")
end

local function filterLabel(filter)
    if filter == FILTER_UNREAD then
        return _("Unread")
    elseif filter == FILTER_READ then
        return _("Read")
    elseif filter == FILTER_DOWNLOADED then
        return _("Downloaded")
    end
    return _("All")
end

local function chapterStatus(manifest, chapter)
    if chapter.isVolume then
        return _("Volume")
    elseif chapter.isVip then
        return _("Locked")
    elseif manifest.current_position == chapter.position then
        return _("Current")
    elseif chapter.read then
        return _("Read")
    elseif chapter.downloaded then
        return _("Downloaded")
    end
    return _("Unread")
end

local function matchesFilter(filter, chapter)
    if filter == FILTER_READ then
        return chapter.read == true
    elseif filter == FILTER_UNREAD then
        return chapter.read ~= true and Chapter.isOpenable(chapter)
    elseif filter == FILTER_DOWNLOADED then
        return chapter.downloaded == true
    end
    return true
end

function Chapters.close(plugin)
    invalidate(plugin)
    Dialog.closeWidget(plugin, "chapters_menu")
end

local function filterMenu(plugin, manifest, current_filter)
    local item_table = {}
    for filter_index = 1, #FILTERS do
        local filter = FILTERS[filter_index]
        table.insert(item_table, {
            text = filterLabel(filter),
            mandatory = filter == current_filter and _("Current") or nil,
            callback = function()
                plugin.novel_chapters_filter = plugin.novel_chapters_filter or {}
                plugin.novel_chapters_filter[manifest.book_id] = filter
                Chapters.showManifest(plugin, manifest, { filter = filter })
            end,
        })
    end
    return item_table
end

local function buildChapterItems(plugin, manifest, filter)
    local item_table = {}
    local shown_count = 0

    for position = 1, #(manifest.chapters or {}) do
        local chapter = manifest.chapters[position]
        if matchesFilter(filter, chapter) then
            shown_count = shown_count + 1
            table.insert(item_table, {
                text = chapterTitle(chapter),
                mandatory = chapterStatus(manifest, chapter),
                select_enabled = Chapter.isOpenable(chapter),
                dim = not Chapter.isOpenable(chapter),
                callback = function()
                    Chapters.openChapter(plugin, manifest, position, {
                        from_reader = plugin.ui and plugin.ui.document ~= nil,
                        jump = "start",
                    })
                end,
            })
        end
    end

    if shown_count == 0 then
        table.insert(item_table, {
            text = _("No chapters."),
            select_enabled = false,
            dim = true,
        })
    end

    item_table[#item_table].separator = true
    table.insert(item_table, {
        text = _("Filter: ") .. filterLabel(filter),
        mandatory = tostring(#(manifest.chapters or {})),
        sub_item_table = filterMenu(plugin, manifest, filter),
    })

    return item_table
end

function Chapters.showManifest(plugin, manifest, options)
    options = options or {}
    manifest = Manifest:new():load(manifest.book_id) or manifest
    Dialog.closeWidget(plugin, "chapters_menu")

    plugin.novel_chapters_filter = plugin.novel_chapters_filter or {}
    local filter = options.filter
        or plugin.novel_chapters_filter[manifest.book_id]
        or FILTER_ALL
    plugin.novel_chapters_filter[manifest.book_id] = filter

    local chapters_menu
    chapters_menu = Menu:new{
        title = manifestTitle(manifest) .. " (" .. tostring(#manifest.chapters)
            .. " / " .. filterLabel(filter) .. ")",
        item_table = buildChapterItems(plugin, manifest, filter),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            if plugin.chapters_menu == chapters_menu then
                plugin.chapters_menu = nil
            end
        end,
    }
    plugin.chapters_menu = chapters_menu
    UIManager:show(chapters_menu)
end

function Chapters.openChapter(plugin, manifest, position, options)
    return ReaderChapter.open(plugin, manifest, position, options)
end

function Chapters.showList(plugin, source, book, result, options)
    options = options or {}
    if not result or not result.ok then
        local existing = Manifest:new():loadByBook(source, book)
        if existing then
            Chapters.showManifest(plugin, existing, options)
            Dialog.message(_("Chapters failed: ")
                .. tostring(Dialog.errorText(result, _("Chapters failed."))))
            return
        end
        Dialog.message(_("Chapters failed: ")
            .. tostring(Dialog.errorText(result, _("Chapters failed."))))
        return
    end

    local manifest, err = Manifest:new():ensureBook(
        source, result.book or book, result.chapters or {})
    if not manifest then
        Dialog.message(_("Chapters failed: ") .. tostring(err))
        return
    end
    if options.open_position then
        Chapters.openChapter(plugin, manifest, options.open_position, {
            from_reader = options.from_reader,
            jump = options.jump,
        })
        return
    end
    Chapters.showManifest(plugin, manifest, options)
end

function Chapters.show(plugin, source, book, options)
    options = options or {}
    if not plugin.app then
        return
    end

    local manifest_store = Manifest:new()
    local existing = refreshManifest(manifest_store,
        manifest_store:loadByBook(source, book), source, book)
    if options.local_only and existing then
        Chapters.showManifest(plugin, existing, options)
        return
    end

    local has_toc_html = book and book.tocHtml ~= nil and book.tocHtml ~= ""
    if not has_toc_html and NetworkMgr:willRerunWhenOnline(function()
        Chapters.show(plugin, source, book, options)
    end) then
        if existing then
            Chapters.showManifest(plugin, existing, options)
        end
        return
    end

    plugin.chapters_request_id = (plugin.chapters_request_id or 0) + 1
    local request_id = plugin.chapters_request_id

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local ChapterCatalog = require("novel.catalog.chapters")
            return ChapterCatalog.run(source, book)
        end, _("Loading chapters... (tap to cancel)"))

        if not plugin.app or plugin.chapters_request_id ~= request_id then
            return
        end
        if not completed then
            Dialog.message(_("Chapter list loading canceled."))
            return
        end
        Chapters.showList(plugin, source, book, result, options)
    end)
end

function Chapters.resume(plugin, source, book, position)
    position = tonumber(position)
    local manifest_store = Manifest:new()
    local manifest = refreshManifest(manifest_store,
        manifest_store:loadByBook(source, book), source, book)
    if manifest and position and manifest.chapters[position] then
        Chapters.openChapter(plugin, manifest, position)
        return
    end
    Chapters.show(plugin, source, book, {
        open_position = position,
    })
end

function Chapters.showCurrent(plugin)
    local file = plugin and plugin.ui and plugin.ui.document
        and plugin.ui.document.file
    local current_chapter = Manifest:new():findChapterByFile(file)
    if not current_chapter then
        Dialog.message(_("No novel chapters for this document."))
        return
    end
    Chapters.showManifest(plugin, current_chapter.manifest)
end

return Chapters
