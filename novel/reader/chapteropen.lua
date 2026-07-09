local _ = require("novel.i18n")
local ChapterRecord = require("novel.reader.chapterrecord")
local ChapterDoc = require("novel.reader.chapterdoc")
local Dialog = require("novel.ui.widget.dialog")
local Loading = require("novel.ui.widget.loading")
local Manifest = require("novel.storage.manifest")
local NetworkMgr = require("ui/network/manager")
local ReturnController = require("novel.reader.returncontroller")
local ReaderSettings = require("novel.reader.settings")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")

local ChapterOpen = {}

local function nextContentRequest(plugin)
    plugin.content_request_id = (plugin.content_request_id or 0) + 1
    return plugin.content_request_id
end

local function closeLoading(plugin, widget)
    Loading.close(plugin, "novel_chapter_loading", widget)
end

local function showLoading(plugin)
    return Loading.show(plugin, "novel_chapter_loading")
end

local function resetSwitch(plugin)
    closeLoading(plugin)
    plugin.novel_switching_chapter = nil
end

local function alreadyAtStart(reader_ui)
    local paging = reader_ui and reader_ui.paging
    if paging then
        if paging.view and paging.view.page_scroll then
            return false
        end
        local current_page = paging.current_page
            or (reader_ui.document and reader_ui.document:getCurrentPage())
            or 1
        return current_page <= 1
    end

    local rolling = reader_ui and reader_ui.rolling
    if rolling then
        if rolling.view and rolling.view.view_mode == "scroll" then
            return (tonumber(rolling.current_pos) or 0) <= 0
        end
        local current_page = tonumber(rolling.current_page)
            or (reader_ui.document and reader_ui.document:getCurrentPage())
            or 1
        return current_page <= 1
    end
    return false
end

local function jumpAfterOpen(reader_ui, jump)
    if not jump then
        return
    end
    UIManager:nextTick(function()
        if not reader_ui or not reader_ui.document then
            return
        end
        if jump == "start" and alreadyAtStart(reader_ui) then
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
        resetSwitch(plugin)
        return
    end

    local function afterOpen(reader_ui)
        closeLoading(plugin)
        plugin.novel_switching_chapter = nil
        jumpAfterOpen(reader_ui or plugin.ui, jump)
    end

    if plugin.ui.document then
        plugin.novel_switching_chapter = true
        if plugin.ui.document.file == file then
            afterOpen(plugin.ui)
            return
        end
        local DocumentRegistry = require("document/documentregistry")
        local provider, is_provider_forced = DocumentRegistry:getProvider(file, true)
        plugin.ui:switchDocument(file, true, afterOpen, provider, is_provider_forced)
    elseif plugin.ui.openFile then
        ReturnController.captureEntry(plugin)
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
    plugin.app:getBookshelfStore():updateProgress(
        manifest.source, manifest.book, chapter, position, 0)
end

local function openDownloadedChapter(plugin, manifest_store, manifest, position, options)
    manifest_store:updateCurrent(manifest, position)
    updateProgress(plugin, manifest, position)
    local chapter = manifest.chapters[position]
    ReaderSettings.syncBeforeOpen(plugin, manifest, chapter.file_path)
    openFile(plugin, chapter.file_path, options and options.jump)
end

function ChapterOpen.open(plugin, manifest, position, options)
    options = options or {}
    if not plugin or not plugin.app then
        return
    end
    if not manifest or not manifest.book_id then
        Dialog.message(_("Chapter not found."))
        resetSwitch(plugin)
        return
    end
    local manifest_store = Manifest:new()
    manifest = manifest_store:load(manifest.book_id) or manifest
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter then
        Dialog.message(_("Chapter not found."))
        resetSwitch(plugin)
        return
    end
    if not ChapterRecord.isOpenable(chapter) and options.from_reader then
        local step = options.jump == "end" and -1 or 1
        local target_chapter, target_position = ChapterRecord.nextOpenable(
            manifest.chapters, position, step)
        if target_chapter then
            ChapterOpen.open(plugin, manifest, target_position, options)
            return
        end
    end
    if not ChapterRecord.isOpenable(chapter) then
        Dialog.message(_("Chapter cannot be opened."))
        resetSwitch(plugin)
        return
    end
    if Manifest.chapterFileExists(manifest, position)
        and ChapterDoc.contentIsCurrent(manifest, chapter) then
        if options.from_reader then
            showLoading(plugin)
        end
        openDownloadedChapter(plugin, manifest_store, manifest, position, options)
        return
    end
    if NetworkMgr:willRerunWhenOnline(function()
        ChapterOpen.open(plugin, manifest, position, options)
    end) then
        resetSwitch(plugin)
        return
    end

    local request_id = nextContentRequest(plugin)
    local next_chapter = ChapterRecord.nextOpenable(manifest.chapters, position, 1)
    local loading_widget = showLoading(plugin)
    local settings = plugin.app and plugin.app.settings

    Trapper:wrap(function()
        local completed, result = Trapper:dismissableRunInSubprocess(function()
            local ChapterContent = require("novel.catalog.reading.chaptercontent")
            return ChapterContent.run(manifest.source, manifest.book, chapter, {
                next_chapter_url = next_chapter and next_chapter.url or nil,
                settings = settings,
            })
        end, loading_widget)

        if not plugin.app or plugin.content_request_id ~= request_id then
            closeLoading(plugin, loading_widget)
            return
        end
        if not completed then
            resetSwitch(plugin)
            Dialog.message(Dialog.canceledMessage())
            return
        end
        if not result or not result.ok then
            resetSwitch(plugin)
            Dialog.message(Dialog.failureMessage(result))
            return
        end

        local image_style = result.image_style
            or ChapterDoc.expectedImageStyle(manifest)
        local html = ChapterDoc.html(chapter, result.text, result.content_type, {
            image_style = image_style,
        })
        local file, err = manifest_store:saveChapter(manifest, position, html, {
            content_type = result.content_type,
            image_style = image_style,
        })
        if not file then
            resetSwitch(plugin)
            Dialog.message(Dialog.failureMessage(err))
            return
        end
        manifest = manifest_store:load(manifest.book_id) or manifest
        openDownloadedChapter(plugin, manifest_store, manifest, position, options)
    end)
end

function ChapterOpen.close(plugin, force)
    if not plugin then
        return
    end
    if not force and plugin.novel_switching_chapter then
        return
    end
    closeLoading(plugin)
end

return ChapterOpen
