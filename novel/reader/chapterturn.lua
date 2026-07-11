local Manifest = require("novel.storage.manifest")
local ChapterDoc = require("novel.reader.chapterdoc")
local ChapterOpen = require("novel.reader.chapteropen")
local ChapterRecord = require("novel.reader.chapterrecord")
local ReturnController = require("novel.reader.returncontroller")
local UIManager = require("ui/uimanager")

local ChapterTurn = {}

local function restoreWrapper(wrapper)
    if wrapper and wrapper.owner and wrapper.method
        and wrapper.owner[wrapper.method] == wrapper.wrapper then
        wrapper.owner[wrapper.method] = wrapper.original
    end
end

local function pageScrollAtEnd(paging)
    local states = paging.view and paging.view.page_states
    local last_state = states and states[#states]
    if not last_state or not last_state.visible_area or not last_state.page_area then
        return false
    end
    return paging.ui.document:getNextPage(last_state.page) == 0
        and last_state.visible_area.y + last_state.visible_area.h
            >= last_state.page_area.h
end

local function pageScrollAtStart(paging)
    local states = paging.view and paging.view.page_states
    local first_state = states and states[1]
    if not first_state or not first_state.visible_area then
        return false
    end
    return paging.ui.document:getPrevPage(first_state.page) == 0
        and first_state.visible_area.y <= 0
end

local function pagingAtBoundary(paging, diff)
    if not paging or type(diff) ~= "number" or diff == 0 then
        return nil
    end
    if paging.view and paging.view.page_scroll then
        if diff > 0 and pageScrollAtEnd(paging) then
            return 1
        elseif diff < 0 and pageScrollAtStart(paging) then
            return -1
        end
        return nil
    end

    local current_page = paging.current_page
        or (paging.ui and paging.ui.document and paging.ui.document:getCurrentPage())
        or 1
    local page_count = paging.number_of_pages
        or (paging.ui and paging.ui.document and paging.ui.document:getPageCount())
        or 1
    if diff > 0 and current_page >= page_count then
        return 1
    elseif diff < 0 and current_page <= 1 then
        return -1
    end
    return nil
end

local function rollingMaxPos(rolling)
    local document = rolling.ui and rolling.ui.document
    if not document or not document.info then
        return 0
    end
    local footer_height = rolling.view and rolling.view.footer
        and rolling.view.footer.getHeight and rolling.view.footer:getHeight()
        or 0
    local max_pos = (document.info.doc_height or 0)
        - (rolling.ui.dimen and rolling.ui.dimen.h or 0)
        + footer_height
    return math.max(max_pos, 0)
end

local function rollingAtBoundary(rolling, diff)
    if not rolling or type(diff) ~= "number" or diff == 0 then
        return nil
    end
    if rolling.view and rolling.view.view_mode == "scroll" then
        local current_pos = tonumber(rolling.current_pos) or 0
        local max_pos = rollingMaxPos(rolling)
        if diff > 0 and current_pos >= max_pos then
            return 1
        elseif diff < 0 and current_pos <= 0 then
            return -1
        end
        return nil
    end

    local current_page = tonumber(rolling.current_page) or 1
    local page_count = rolling.ui and rolling.ui.document
        and rolling.ui.document:getPageCount() or 1
    if diff > 0 and current_page >= page_count then
        return 1
    elseif diff < 0 and current_page <= 1 then
        return -1
    end
    return nil
end

local function updateFinalProgress(plugin, manifest, position)
    local chapter = manifest and manifest.chapters and manifest.chapters[position]
    if not chapter or not plugin.app then
        return
    end
    plugin.app:getBookshelfStore():updateProgress(
        manifest.source, manifest.book, chapter, position, 0)
end

local function finishReading(plugin, current_chapter, manifest)
    local position = current_chapter.position
    local manifest_store = Manifest:new()
    manifest = manifest_store:load(manifest.book_id) or manifest
    if not manifest.chapters or not manifest.chapters[position] then
        return false
    end

    plugin.novel_switching_chapter = true
    manifest_store:updateCurrent(manifest, position)
    manifest_store:markRead(manifest, position)
    manifest = manifest_store:load(manifest.book_id) or manifest
    updateFinalProgress(plugin, manifest, position)

    local reader_ui = plugin.ui
    if not ReturnController.requestFinishExit(reader_ui, current_chapter) then
        plugin.novel_switching_chapter = nil
        return false
    end
    UIManager:nextTick(function()
        if reader_ui and reader_ui.document then
            reader_ui:onClose()
        end
    end)
    return true
end

local function switchChapter(plugin, direction)
    if plugin.novel_switching_chapter then
        return true
    end

    local current_chapter = plugin.novel_reader_chapter
        or ChapterDoc.currentChapter(plugin)
    local manifest = current_chapter and current_chapter.manifest
    if not manifest then
        return false
    end
    local target_chapter, target_position = ChapterRecord.nextOpenable(
        manifest.chapters, current_chapter.position, direction)
    if not target_chapter then
        if direction > 0 then
            return finishReading(plugin, current_chapter, manifest)
        end
        return false
    end

    plugin.novel_switching_chapter = true
    if direction > 0 then
        Manifest:new():markRead(manifest, current_chapter.position)
    end
    UIManager:nextTick(function()
        if not plugin.app then
            return
        end
        ChapterOpen.open(plugin, manifest, target_position, {
            from_reader = true,
            jump = direction > 0 and "start" or "end",
        })
    end)
    return true
end

local function installWrapper(plugin, owner, method, boundary_func, key)
    if not owner or type(owner[method]) ~= "function" or plugin[key] then
        return
    end

    local original = owner[method]
    local wrapper
    wrapper = function(owner_self, diff, no_page_turn, ...)
        if no_page_turn == true then
            return original(owner_self, diff, no_page_turn, ...)
        end
        local direction = boundary_func(owner_self, diff)
        if direction and switchChapter(plugin, direction) then
            return true
        end
        return original(owner_self, diff, no_page_turn, ...)
    end

    owner[method] = wrapper
    plugin[key] = {
        owner = owner,
        method = method,
        original = original,
        wrapper = wrapper,
    }
end

function ChapterTurn.close(plugin)
    if not plugin then
        return
    end
    restoreWrapper(plugin.novel_paging_wrapper)
    restoreWrapper(plugin.novel_rolling_wrapper)
    plugin.novel_paging_wrapper = nil
    plugin.novel_rolling_wrapper = nil
    plugin.novel_reader_chapter = nil
    plugin.novel_switching_chapter = nil
end

function ChapterTurn.setup(plugin)
    ChapterTurn.close(plugin)
    local current_chapter = ChapterDoc.currentChapter(plugin)
    if not current_chapter then
        return false
    end

    plugin.novel_reader_chapter = current_chapter
    installWrapper(plugin, plugin.ui.paging, "onGotoViewRel",
        pagingAtBoundary, "novel_paging_wrapper")
    installWrapper(plugin, plugin.ui.rolling, "onGotoViewRel",
        rollingAtBoundary, "novel_rolling_wrapper")
    return true
end

return ChapterTurn
