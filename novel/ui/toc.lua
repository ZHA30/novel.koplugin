local _ = require("novel.i18n")
local ChapterDoc = require("novel.service.chapterdoc")
local InfoMessage = require("ui/widget/infomessage")
local Library = require("novel.storage.library")
local Menu = require("novel.ui.menu")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Toc = {}

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

local function closeWidget(plugin, key)
    if plugin[key] then
        local widget = plugin[key]
        plugin[key] = nil
        UIManager:close(widget)
    end
end

local function invalidate(plugin)
    plugin.toc_request_id = (plugin.toc_request_id or 0) + 1
    plugin.content_request_id = (plugin.content_request_id or 0) + 1
end

local function showMessage(message)
    UIManager:show(InfoMessage:new{
        text = message,
    })
end

local function errorText(result, fallback)
    if not result or not result.error then
        return fallback
    end
    return result.error.message or result.error.kind or fallback
end

local function refreshManifest(library, manifest, source, book)
    if not manifest or not source then
        return manifest
    end
    local refreshed = library:ensureBook(source, book or manifest.book,
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

local function openableChapter(chapter)
    return chapter and not chapter.isVolume and not chapter.isVip
end

local function matchesFilter(filter, chapter)
    if filter == FILTER_READ then
        return chapter.read == true
    elseif filter == FILTER_UNREAD then
        return chapter.read ~= true and openableChapter(chapter)
    elseif filter == FILTER_DOWNLOADED then
        return chapter.downloaded == true
    end
    return true
end

local function nextOpenableChapter(chapters, position)
    for chapter_index = position + 1, #(chapters or {}) do
        if openableChapter(chapters[chapter_index]) then
            return chapters[chapter_index]
        end
    end
    return nil
end

local function jumpAfterOpen(reader_ui, jump)
    if not jump then
        return
    end
    UIManager:nextTick(function()
        if not reader_ui or not reader_ui.document then
            return
        end
        local percent = jump == "end" and 100 or 0
        if reader_ui.paging and reader_ui.paging.onGotoPercent then
            reader_ui.paging:onGotoPercent(percent)
        elseif reader_ui.rolling and reader_ui.rolling.onGotoPercent then
            reader_ui.rolling:onGotoPercent(percent)
        end
    end)
end

local function openFile(plugin, file, jump)
    if not plugin.ui then
        return
    end

    local function afterOpen(reader_ui)
        jumpAfterOpen(reader_ui or plugin.ui, jump)
    end

    if plugin.ui.document then
        plugin.novel_switching_chapter = true
        if plugin.ui.document.file == file then
            afterOpen(plugin.ui)
            plugin.novel_switching_chapter = nil
            return
        end
        local DocumentRegistry = require("document/documentregistry")
        local provider, is_provider_forced = DocumentRegistry:getProvider(file, true)
        plugin.ui:switchDocument(file, true, afterOpen, provider, is_provider_forced)
    elseif plugin.ui.openFile then
        plugin.ui:openFile(file, nil, nil, nil, afterOpen)
    end
end

local function updateProgress(plugin, manifest, position)
    if not plugin.app then
        return
    end
    local chapter = manifest.chapters[position]
    if not chapter then
        return
    end
    plugin.app:getBookshelfService():updateProgress(
        manifest.source, manifest.book, chapter, position, 0)
end

function Toc.close(plugin)
    invalidate(plugin)
    closeWidget(plugin, "toc_menu")
end

local function filterMenu(plugin, manifest, current_filter)
    local item_table = {}
    for filter_index = 1, #FILTERS do
        local filter = FILTERS[filter_index]
        table.insert(item_table, {
            text = filterLabel(filter),
            mandatory = filter == current_filter and _("Current") or nil,
            callback = function()
                plugin.novel_toc_filter = plugin.novel_toc_filter or {}
                plugin.novel_toc_filter[manifest.book_id] = filter
                Toc.showManifest(plugin, manifest, { filter = filter })
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
                select_enabled = openableChapter(chapter),
                dim = not openableChapter(chapter),
                callback = function()
                    Toc.openChapter(plugin, manifest, position, {
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

function Toc.showManifest(plugin, manifest, options)
    options = options or {}
    manifest = Library:new():load(manifest.book_id) or manifest
    closeWidget(plugin, "toc_menu")

    plugin.novel_toc_filter = plugin.novel_toc_filter or {}
    local filter = options.filter
        or plugin.novel_toc_filter[manifest.book_id]
        or FILTER_ALL
    plugin.novel_toc_filter[manifest.book_id] = filter

    local toc_menu
    toc_menu = Menu:new{
        title = manifestTitle(manifest) .. " (" .. tostring(#manifest.chapters)
            .. " / " .. filterLabel(filter) .. ")",
        item_table = buildChapterItems(plugin, manifest, filter),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        close_callback = function()
            if plugin.toc_menu == toc_menu then
                plugin.toc_menu = nil
            end
        end,
    }
    plugin.toc_menu = toc_menu
    UIManager:show(toc_menu)
end

local function openDownloaded(plugin, library, manifest, position, options)
    library:updateCurrent(manifest, position)
    updateProgress(plugin, manifest, position)
    closeWidget(plugin, "toc_menu")
    local chapter = manifest.chapters[position]
    openFile(plugin, chapter.file_path, options and options.jump)
end

function Toc.openChapter(plugin, manifest, position, options)
    options = options or {}
    if not plugin.app then
        return
    end
    local library = Library:new()
    manifest = library:load(manifest.book_id) or manifest
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        showMessage(_("Chapter not found."))
        plugin.novel_switching_chapter = nil
        return
    end
    if not openableChapter(chapter) and options.from_reader then
        local step = options.jump == "end" and -1 or 1
        local target_position = position + step
        while manifest.chapters[target_position] do
            if openableChapter(manifest.chapters[target_position]) then
                Toc.openChapter(plugin, manifest, target_position, options)
                return
            end
            target_position = target_position + step
        end
    end
    if not openableChapter(chapter) then
        showMessage(_("Chapter cannot be opened."))
        plugin.novel_switching_chapter = nil
        return
    end
    if Library.chapterFileExists(manifest, position)
        and ChapterDoc.contentIsCurrent(manifest, chapter) then
        openDownloaded(plugin, library, manifest, position, options)
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        Toc.openChapter(plugin, manifest, position, options)
    end) then
        plugin.novel_switching_chapter = nil
        return
    end

    plugin.content_request_id = (plugin.content_request_id or 0) + 1
    local request_id = plugin.content_request_id
    local next_chapter = nextOpenableChapter(manifest.chapters, position)

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local ContentService = require("novel.service.content")
            return ContentService.run(manifest.source, manifest.book, chapter, {
                next_chapter_url = next_chapter and next_chapter.url or nil,
            })
        end, _("Loading chapter... (tap to cancel)"))

        if not plugin.app or plugin.content_request_id ~= request_id then
            return
        end
        if not completed then
            plugin.novel_switching_chapter = nil
            showMessage(_("Chapter loading canceled."))
            return
        end
        if not result or not result.ok then
            plugin.novel_switching_chapter = nil
            showMessage(_("Content failed: ")
                .. tostring(errorText(result, _("Content failed."))))
            return
        end

        local html = ChapterDoc.html(chapter, result.text, result.content_type)
        local file, err = library:saveChapter(manifest, position, html, {
            content_type = result.content_type,
        })
        if not file then
            plugin.novel_switching_chapter = nil
            showMessage(_("Save chapter failed: ") .. tostring(err))
            return
        end
        manifest = library:load(manifest.book_id) or manifest
        openDownloaded(plugin, library, manifest, position, options)
    end)
end

function Toc.showList(plugin, source, book, result, options)
    options = options or {}
    if not result or not result.ok then
        local existing = Library:new():loadByBook(source, book)
        if existing then
            Toc.showManifest(plugin, existing, options)
            showMessage(_("TOC failed: ") .. tostring(errorText(result, _("TOC failed."))))
            return
        end
        showMessage(_("TOC failed: ") .. tostring(errorText(result, _("TOC failed."))))
        return
    end

    local manifest, err = Library:new():ensureBook(
        source, result.book or book, result.chapters or {})
    if not manifest then
        showMessage(_("TOC failed: ") .. tostring(err))
        return
    end
    if options.open_position then
        Toc.openChapter(plugin, manifest, options.open_position, {
            from_reader = options.from_reader,
            jump = options.jump,
        })
        return
    end
    Toc.showManifest(plugin, manifest, options)
end

function Toc.show(plugin, source, book, options)
    options = options or {}
    if not plugin.app then
        return
    end

    local library = Library:new()
    local existing = refreshManifest(library, library:loadByBook(source, book),
        source, book)
    if options.local_only and existing then
        Toc.showManifest(plugin, existing, options)
        return
    end

    local has_toc_html = book and book.tocHtml ~= nil and book.tocHtml ~= ""
    if not has_toc_html and NetworkMgr:willRerunWhenOnline(function()
        Toc.show(plugin, source, book, options)
    end) then
        if existing then
            Toc.showManifest(plugin, existing, options)
        end
        return
    end

    plugin.toc_request_id = (plugin.toc_request_id or 0) + 1
    local request_id = plugin.toc_request_id

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local TocService = require("novel.service.toc")
            return TocService.run(source, book)
        end, _("Loading chapters... (tap to cancel)"))

        if not plugin.app or plugin.toc_request_id ~= request_id then
            return
        end
        if not completed then
            showMessage(_("Chapter list loading canceled."))
            return
        end
        Toc.showList(plugin, source, book, result, options)
    end)
end

function Toc.resume(plugin, source, book, position)
    position = tonumber(position)
    local library = Library:new()
    local manifest = refreshManifest(library, library:loadByBook(source, book),
        source, book)
    if manifest and position and manifest.chapters[position] then
        Toc.openChapter(plugin, manifest, position)
        return
    end
    Toc.show(plugin, source, book, {
        open_position = position,
    })
end

function Toc.showCurrent(plugin)
    local file = plugin and plugin.ui and plugin.ui.document
        and plugin.ui.document.file
    local context = Library:new():findContextByFile(file)
    if not context then
        showMessage(_("No novel chapters for this document."))
        return
    end
    Toc.showManifest(plugin, context.manifest)
end

return Toc
