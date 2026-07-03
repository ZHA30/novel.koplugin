local _ = require("novel.i18n")
local Chapter = require("novel.model.chapter")
local ChapterDoc = require("novel.library.chapterdoc")
local Dialog = require("novel.widget.dialog")
local Store = require("novel.library.store")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local Opener = {}

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

local function openDownloaded(plugin, store, manifest, position, options)
    store:updateCurrent(manifest, position)
    updateProgress(plugin, manifest, position)
    Dialog.closeWidget(plugin, "toc_menu")
    local chapter = manifest.chapters[position]
    openFile(plugin, chapter.file_path, options and options.jump)
end

function Opener.open(plugin, manifest, position, options)
    options = options or {}
    if not plugin or not plugin.app then
        return
    end
    if not manifest or not manifest.book_id then
        Dialog.message(_("Chapter not found."))
        plugin.novel_switching_chapter = nil
        return
    end
    local store = Store:new()
    manifest = store:load(manifest.book_id) or manifest
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        Dialog.message(_("Chapter not found."))
        plugin.novel_switching_chapter = nil
        return
    end
    if not Chapter.isOpenable(chapter) and options.from_reader then
        local step = options.jump == "end" and -1 or 1
        local target_chapter, target_position = Chapter.nextOpenable(
            manifest.chapters, position, step)
        if target_chapter then
            Opener.open(plugin, manifest, target_position, options)
            return
        end
    end
    if not Chapter.isOpenable(chapter) then
        Dialog.message(_("Chapter cannot be opened."))
        plugin.novel_switching_chapter = nil
        return
    end
    if Store.chapterFileExists(manifest, position)
        and ChapterDoc.contentIsCurrent(manifest, chapter) then
        openDownloaded(plugin, store, manifest, position, options)
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        Opener.open(plugin, manifest, position, options)
    end) then
        plugin.novel_switching_chapter = nil
        return
    end

    plugin.content_request_id = (plugin.content_request_id or 0) + 1
    local request_id = plugin.content_request_id
    local next_chapter = Chapter.nextOpenable(manifest.chapters, position, 1)

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local ContentService = require("novel.catalog.content")
            return ContentService.run(manifest.source, manifest.book, chapter, {
                next_chapter_url = next_chapter and next_chapter.url or nil,
            })
        end, _("Loading chapter... (tap to cancel)"))

        if not plugin.app or plugin.content_request_id ~= request_id then
            return
        end
        if not completed then
            plugin.novel_switching_chapter = nil
            Dialog.message(_("Chapter loading canceled."))
            return
        end
        if not result or not result.ok then
            plugin.novel_switching_chapter = nil
            Dialog.message(_("Content failed: ")
                .. tostring(Dialog.errorText(result, _("Content failed."))))
            return
        end

        local html = ChapterDoc.html(chapter, result.text, result.content_type)
        local file, err = store:saveChapter(manifest, position, html, {
            content_type = result.content_type,
        })
        if not file then
            plugin.novel_switching_chapter = nil
            Dialog.message(_("Save chapter failed: ") .. tostring(err))
            return
        end
        manifest = store:load(manifest.book_id) or manifest
        openDownloaded(plugin, store, manifest, position, options)
    end)
end

return Opener
