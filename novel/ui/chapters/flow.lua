local _ = require("novel.i18n")
local ChapterListing = require("novel.ui.chapters.listing")
local Dialog = require("novel.ui.widget.dialog")
local Loading = require("novel.ui.widget.loading")
local Manifest = require("novel.storage.manifest")
local NetworkMgr = require("ui/network/manager")
local ChapterOpen = require("novel.reader.chapteropen")
local ShellRoutes = require("novel.ui.shellroutes")
local Shell = require("novel.ui.shell")
local Trapper = require("ui/trapper")

local ChaptersFlow = {}

local function invalidate(plugin)
    plugin.chapters_request_id = (plugin.chapters_request_id or 0) + 1
    plugin.content_request_id = (plugin.content_request_id or 0) + 1
end

function ChaptersFlow.close(plugin)
    invalidate(plugin)
    Loading.close(plugin, "chapters_loading")
end

function ChaptersFlow.showManifest(plugin, manifest, options)
    options = options or {}
    manifest = Manifest:new():load(manifest.book_id) or manifest

    local filter, sort = ChapterListing.resolveState(plugin, manifest, options)
    local route = ShellRoutes.chapters{
        tab = options.tab or "bookshelf",
        source = manifest.source,
        book = manifest.book,
        manifest = manifest,
        filter = filter,
        sort = sort,
    }
    local current = Shell.currentRoute(plugin)
    if current and current.key == "chapters"
        and current.manifest
        and current.manifest.book_id == manifest.book_id then
        Shell.replace(plugin, route)
    else
        Shell.push(plugin, route)
    end
end

function ChaptersFlow.openChapter(plugin, manifest, position, options)
    return ChapterOpen.open(plugin, manifest, position, options)
end

function ChaptersFlow.showList(plugin, source, book, result, options)
    options = options or {}
    if not result or not result.ok then
        local existing = Manifest:new():loadByBook(source, book)
        if existing then
            ChaptersFlow.showManifest(plugin, existing, options)
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
        ChaptersFlow.openChapter(plugin, manifest, options.open_position, {
            from_reader = options.from_reader,
            jump = options.jump,
        })
        return
    end
    ChaptersFlow.showManifest(plugin, manifest, options)
end

function ChaptersFlow.show(plugin, source, book, options)
    options = options or {}
    if not plugin.app then
        return
    end

    local manifest_store = Manifest:new()
    local existing = ChapterListing.refreshManifest(manifest_store,
        manifest_store:loadByBook(source, book), source, book)
    if options.local_only and existing then
        ChaptersFlow.showManifest(plugin, existing, options)
        return
    end

    local has_toc_html = book and book.tocHtml ~= nil and book.tocHtml ~= ""
    if not has_toc_html and NetworkMgr:willRerunWhenOnline(function()
        ChaptersFlow.show(plugin, source, book, options)
    end) then
        if existing then
            ChaptersFlow.showManifest(plugin, existing, options)
        end
        return
    end

    plugin.chapters_request_id = (plugin.chapters_request_id or 0) + 1
    local request_id = plugin.chapters_request_id

    Trapper:wrap(function()
        local loading_widget = Loading.show(plugin, "chapters_loading")
        local settings = plugin.app and plugin.app.settings
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local Toc = require("novel.catalog.reading.toc")
            return Toc.run(source, book, {
                settings = settings,
            })
        end, loading_widget)
        Loading.close(plugin, "chapters_loading", loading_widget)

        if not plugin.app or plugin.chapters_request_id ~= request_id then
            return
        end
        if not completed then
            Dialog.message(_("Chapter list loading canceled."))
            return
        end
        ChaptersFlow.showList(plugin, source, book, result, options)
    end)
end

function ChaptersFlow.resume(plugin, source, book, position)
    position = tonumber(position)
    local manifest_store = Manifest:new()
    local manifest = ChapterListing.refreshManifest(manifest_store,
        manifest_store:loadByBook(source, book), source, book)
    if manifest and position and manifest.chapters[position] then
        ChaptersFlow.openChapter(plugin, manifest, position)
        return
    end
    ChaptersFlow.show(plugin, source, book, {
        open_position = position,
    })
end

function ChaptersFlow.showCurrent(plugin)
    local file = plugin and plugin.ui and plugin.ui.document
        and plugin.ui.document.file
    local current_chapter = Manifest:new():findChapterByFile(file)
    if not current_chapter then
        Dialog.message(_("No novel chapters for this document."))
        return
    end
    ChaptersFlow.showManifest(plugin, current_chapter.manifest)
end

return ChaptersFlow
