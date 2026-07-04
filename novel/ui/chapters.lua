local _ = require("novel.i18n")
local ButtonDialog = require("ui/widget/buttondialog")
local Chapter = require("novel.model.chapter")
local Dialog = require("novel.widget.dialog")
local Loading = require("novel.widget.loading")
local Manifest = require("novel.books.manifest")
local Menu = require("novel.widget.menu")
local NetworkMgr = require("ui/network/manager")
local ReaderChapter = require("novel.reader.chapter")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Chapters = {}

local FILTER_ALL = "all"
local FILTER_UNREAD = "unread"

local SORT_ASCENDING = "ascending"
local SORT_DESCENDING = "descending"

local RETURN_TO_BOOKSHELF = "bookshelf"
local RETURN_TO_NOVEL_MENU = "novel_menu"

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
    end
    return _("All")
end

local function sortLabel(sort)
    if sort == SORT_DESCENDING then
        return _("Descending")
    end
    return _("Ascending")
end

local function chapterStatus(manifest, chapter)
    if chapter.isVolume then
        return _("Volume")
    elseif chapter.isVip then
        return _("Locked")
    elseif manifest.current_position == chapter.position then
        return _("Current")
    elseif chapter.downloaded then
        return _("Downloaded")
    end
    return nil
end

local function matchesFilter(filter, chapter)
    if filter == FILTER_UNREAD then
        return chapter.read ~= true and Chapter.isOpenable(chapter)
    end
    return true
end

local function normalizeFilter(filter)
    if filter == FILTER_UNREAD then
        return FILTER_UNREAD
    end
    return FILTER_ALL
end

local function normalizeSort(sort)
    if sort == SORT_DESCENDING then
        return SORT_DESCENDING
    end
    return SORT_ASCENDING
end

local function chapterListBooks(plugin)
    local settings = plugin and plugin.app and plugin.app.settings
    if type(settings) ~= "table" then
        return nil
    end
    if type(settings.chapter_list) ~= "table" then
        settings.chapter_list = {}
    end
    if type(settings.chapter_list.books) ~= "table" then
        settings.chapter_list.books = {}
    end
    return settings.chapter_list.books
end

local function chapterListBookState(plugin, book_id, create)
    if not book_id or book_id == "" then
        return nil
    end

    local books = chapterListBooks(plugin)
    if not books then
        return nil
    end

    local state = books[book_id]
    if type(state) ~= "table" then
        if not create then
            return nil
        end
        state = {}
        books[book_id] = state
    end
    return state
end

local function saveBookState(plugin, book_id, filter, sort)
    local state = chapterListBookState(plugin, book_id, true)
    if not state then
        return
    end

    local changed = false
    if state.filter ~= filter then
        state.filter = filter
        changed = true
    end
    if state.sort ~= sort then
        state.sort = sort
        changed = true
    end

    if changed and plugin and plugin.app then
        plugin.app:saveSettings()
    end
end

local function returnAfterClose(plugin, return_to)
    if return_to ~= RETURN_TO_BOOKSHELF
        and return_to ~= RETURN_TO_NOVEL_MENU then
        return
    end
    UIManager:nextTick(function()
        if not plugin or not plugin.app then
            return
        end
        if return_to == RETURN_TO_BOOKSHELF then
            if plugin.bookshelf_menu
                and UIManager:isWidgetShown(plugin.bookshelf_menu) then
                return
            end
            local Bookshelf = require("novel.ui.bookshelf")
            Bookshelf.show(plugin)
        elseif type(plugin.onShowNovelMenu) == "function" then
            if plugin.novel_menu and UIManager:isWidgetShown(plugin.novel_menu) then
                return
            end
            plugin:onShowNovelMenu()
        end
    end)
end

function Chapters.close(plugin)
    invalidate(plugin)
    Loading.close(plugin, "chapters_loading")
    Dialog.closeWidget(plugin, "chapters_menu")
end

local function buildChapterItems(plugin, manifest, filter, sort, options)
    local item_table = {}
    local chapters = manifest.chapters or {}
    local shown_count = 0
    local start_position = sort == SORT_DESCENDING and #chapters or 1
    local end_position = sort == SORT_DESCENDING and 1 or #chapters
    local step = sort == SORT_DESCENDING and -1 or 1

    for position = start_position, end_position, step do
        local chapter = chapters[position]
        if matchesFilter(filter, chapter) then
            local is_openable = Chapter.isOpenable(chapter)
            shown_count = shown_count + 1
            table.insert(item_table, {
                text = chapterTitle(chapter),
                mandatory = chapterStatus(manifest, chapter),
                select_enabled = is_openable,
                dim = chapter.read == true or not is_openable,
                callback = function()
                    Chapters.openChapter(plugin, manifest, position, {
                        from_reader = plugin.ui and plugin.ui.document ~= nil,
                        jump = "start",
                        return_to = options and options.return_to,
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

    return item_table, shown_count
end

local function showListMenu(plugin, manifest, chapters_menu, filter, sort, options)
    local dialog
    local function refresh(new_filter, new_sort)
        if UIManager:isWidgetShown(dialog) then
            UIManager:close(dialog)
        end
        Chapters.showManifest(plugin, manifest, {
            filter = new_filter,
            sort = new_sort,
            return_to = options and options.return_to,
        })
    end

    dialog = ButtonDialog:new{
        buttons = {
            {{
                text_func = function()
                    return filterLabel(filter)
                end,
                checked_func = function()
                    return filter == FILTER_UNREAD
                end,
                callback = function()
                    refresh(filter == FILTER_UNREAD and FILTER_ALL
                        or FILTER_UNREAD, sort)
                end,
                align = "left",
            }},
            {{
                text_func = function()
                    return sortLabel(sort)
                end,
                checked_func = function()
                    return sort == SORT_DESCENDING
                end,
                callback = function()
                    refresh(filter, sort == SORT_DESCENDING and SORT_ASCENDING
                        or SORT_DESCENDING)
                end,
                align = "left",
            }},
        },
        shrink_unneeded_width = true,
        anchor = function()
            return chapters_menu.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(dialog)
end

function Chapters.showManifest(plugin, manifest, options)
    options = options or {}
    manifest = Manifest:new():load(manifest.book_id) or manifest
    Dialog.closeWidget(plugin, "chapters_menu")

    local book_id = manifest.book_id
    local book_state = chapterListBookState(plugin, book_id)
    plugin.novel_chapters_filter = plugin.novel_chapters_filter or {}
    plugin.novel_chapters_sort = plugin.novel_chapters_sort or {}
    local filter = options.filter
        or (book_id and plugin.novel_chapters_filter[book_id])
        or (book_state and book_state.filter)
        or FILTER_ALL
    filter = normalizeFilter(filter)
    if book_id then
        plugin.novel_chapters_filter[book_id] = filter
    end
    local sort = options.sort
        or (book_id and plugin.novel_chapters_sort[book_id])
        or (book_state and book_state.sort)
        or SORT_ASCENDING
    sort = normalizeSort(sort)
    if book_id then
        plugin.novel_chapters_sort[book_id] = sort
    end
    if options.filter ~= nil or options.sort ~= nil
        or (book_state and (book_state.filter ~= filter
            or book_state.sort ~= sort)) then
        saveBookState(plugin, book_id, filter, sort)
    end

    local item_table, shown_count = buildChapterItems(plugin, manifest, filter,
        sort, options)

    local chapters_menu
    chapters_menu = Menu:new{
        title = manifestTitle(manifest) .. " (" .. tostring(shown_count)
            .. "/" .. tostring(#manifest.chapters) .. ")",
        item_table = item_table,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            showListMenu(plugin, manifest, chapters_menu, filter, sort, options)
        end,
        close_callback = function()
            if plugin.chapters_menu == chapters_menu then
                plugin.chapters_menu = nil
            end
            returnAfterClose(plugin, options.return_to)
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
            return_to = options.return_to,
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
        local loading_widget = Loading.show(plugin, "chapters_loading")
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local ChapterCatalog = require("novel.catalog.chapters")
            return ChapterCatalog.run(source, book)
        end, loading_widget)
        Loading.close(plugin, "chapters_loading", loading_widget)

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

function Chapters.resume(plugin, source, book, position, options)
    options = options or {}
    position = tonumber(position)
    local manifest_store = Manifest:new()
    local manifest = refreshManifest(manifest_store,
        manifest_store:loadByBook(source, book), source, book)
    if manifest and position and manifest.chapters[position] then
        Chapters.openChapter(plugin, manifest, position, {
            return_to = options.return_to,
        })
        return
    end
    Chapters.show(plugin, source, book, {
        open_position = position,
        return_to = options.return_to,
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
