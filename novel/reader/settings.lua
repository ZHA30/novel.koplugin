local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local LuaSettings = require("luasettings")
local ChapterDoc = require("novel.reader.chapterdoc")

local ReaderSettings = {
    path = DataStorage:getSettingsDir() .. "/novel_reader_settings.lua",
}

local allowed_exact = {
    css = true,
    font_face = true,
    font_family_fonts = true,
    floating_punctuation = true,
    hyph_force_algorithmic = true,
    hyph_soft_hyphens_only = true,
    hyph_trust_soft_hyphens = true,
    hyphenation = true,
    inverse_reading_order = true,
    invert_ui_layout = true,
    page_overlap_style = true,
    render_mode = true,
    show_overlap_enable = true,
    style_tweaks_enabled = true,
    style_tweaks = true,
    book_style_tweak = true,
    book_style_tweak_enabled = true,
    text_lang = true,
    text_lang_embedded_langs = true,
    zoom_mode = true,
}

local denied_exact = {
    annotations = true,
    cache_file_path = true,
    doc_pages = true,
    doc_path = true,
    doc_props = true,
    highlight = true,
    last_page = true,
    last_percent = true,
    last_xpointer = true,
    metadata_arc = true,
    page_positions = true,
    partial_md5_checksum = true,
    percent_finished = true,
    stats = true,
    summary = true,
    tile_cache_validity_ts = true,
}

local allowed_prefixes = {
    "copt_",
    "kopt_",
}

local denied_prefixes = {
    "book_map_",
    "page_browser_",
    "pagemap_",
}

local function now()
    return os.time()
end

local function startsWith(value, prefix)
    return value:sub(1, #prefix) == prefix
end

local function clone(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, item in pairs(value) do
        copy[key] = clone(item)
    end
    return copy
end

local function isAllowedKey(key)
    key = tostring(key or "")
    if denied_exact[key] then
        return false
    end
    for _, prefix in ipairs(denied_prefixes) do
        if startsWith(key, prefix) then
            return false
        end
    end
    if allowed_exact[key] then
        return true
    end
    for _, prefix in ipairs(allowed_prefixes) do
        if startsWith(key, prefix) then
            return true
        end
    end
    return false
end

local function extract(settings)
    local data = settings and settings.data
    if type(data) ~= "table" then
        return nil
    end

    local extracted = {}
    for key, value in pairs(data) do
        if isAllowedKey(key) then
            extracted[key] = clone(value)
        end
    end
    return extracted
end

local function openStore()
    return LuaSettings:open(ReaderSettings.path)
end

local function loadBooks(store)
    local books = store:readSetting("books")
    if type(books) ~= "table" then
        return {}
    end
    return books
end

local function saveTemplate(book_id, template)
    local store = openStore()
    local books = loadBooks(store)
    books[book_id] = {
        updated_at = now(),
        settings = template or {},
    }
    store:saveSetting("books", books)
    store:flush()
end

local function loadTemplate(book_id)
    local store = openStore()
    local books = loadBooks(store)
    local record = books[book_id]
    if type(record) ~= "table" or type(record.settings) ~= "table" then
        return nil
    end
    return record.settings
end

local function saveCurrentReaderState(plugin)
    local ui = plugin and plugin.ui
    if not ui then
        return
    end

    if type(ui.handleEvent) == "function" then
        plugin.novel_skip_reader_settings_capture = true
        local ok = pcall(ui.handleEvent, ui, Event:new("SaveSettings"))
        plugin.novel_skip_reader_settings_capture = nil
        if ok then
            return
        end
    end

    if type(ui.saveSettings) == "function" then
        pcall(ui.saveSettings, ui)
    end
end

function ReaderSettings.capture(plugin, current_chapter)
    current_chapter = current_chapter or ChapterDoc.currentChapter(plugin)
    if not current_chapter or not current_chapter.book_id
        or not plugin or not plugin.ui or not plugin.ui.doc_settings then
        return false
    end

    local template = extract(plugin.ui.doc_settings)
    if not template then
        return false
    end
    saveTemplate(current_chapter.book_id, template)
    return true
end

function ReaderSettings.applyTo(file, template)
    if not file or type(template) ~= "table" then
        return false
    end

    local doc_settings = DocSettings:open(file)
    local data = doc_settings.data or {}
    for key in pairs(data) do
        if isAllowedKey(key) and template[key] == nil then
            doc_settings:delSetting(key)
        end
    end
    for key, value in pairs(template) do
        if isAllowedKey(key) then
            doc_settings:saveSetting(key, clone(value))
        end
    end
    doc_settings:flush()
    return true
end

function ReaderSettings.syncBeforeOpen(plugin, manifest, target_file)
    if not plugin or not plugin.ui or not manifest or not manifest.book_id
        or not target_file then
        return false
    end

    local current_chapter = ChapterDoc.currentChapter(plugin)
    if current_chapter and current_chapter.book_id == manifest.book_id then
        saveCurrentReaderState(plugin)
        ReaderSettings.capture(plugin, current_chapter)
    end

    local template = loadTemplate(manifest.book_id)
    if not template then
        return false
    end
    return ReaderSettings.applyTo(target_file, template)
end

function ReaderSettings.deleteStorage()
    os.remove(ReaderSettings.path)
    os.remove(ReaderSettings.path .. ".old")
end

return ReaderSettings
