local ContentType = require("novel.catalog.shared.contenttype")
local Manifest = require("novel.storage.manifest")
local util = require("util")

local ChapterDoc = {}

local function escapeHtml(value)
    return util.htmlEscape(tostring(value or ""))
end

local function textBody(text)
    local paragraphs = {}
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    for raw_line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw_line:match("^%s*(.-)%s*$")
        if line ~= "" then
            table.insert(paragraphs, "<p>" .. escapeHtml(line) .. "</p>")
        end
    end
    if #paragraphs == 0 then
        table.insert(paragraphs, "<p></p>")
    end

    return table.concat(paragraphs, "\n")
end

local function htmlBody(html)
    html = tostring(html or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    if html:match("^%s*$") then
        return "<p></p>"
    end
    return html
end

function ChapterDoc.isNovelPath(path)
    path = tostring(path or "")
    local root = Manifest.root_dir
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

function ChapterDoc.chapterByFile(file)
    if not ChapterDoc.isNovelPath(file) then
        return nil
    end
    return Manifest:new():findChapterByFile(file)
end

function ChapterDoc.currentReaderFile()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader_ui = ok and ReaderUI.instance
    return reader_ui and reader_ui.document and reader_ui.document.file
end

function ChapterDoc.currentChapter(plugin)
    if not plugin or not plugin.ui or not plugin.ui.document then
        return nil
    end
    return ChapterDoc.chapterByFile(plugin.ui.document.file)
end

function ChapterDoc.expectedContentType(manifest)
    local rule = manifest and manifest.source and manifest.source.ruleContent
    return ContentType.typeForRule(rule and rule.content)
end

function ChapterDoc.expectedImageStyle(manifest)
    local rule = manifest and manifest.source and manifest.source.ruleContent
    return ContentType.normalizeImageStyle(rule and rule.imageStyle)
end

function ChapterDoc.contentIsCurrent(manifest, chapter)
    return ContentType.isCurrent(ChapterDoc.expectedContentType(manifest),
        chapter and chapter.content_type)
        and ContentType.normalizeImageStyle(chapter and chapter.image_style)
            == ChapterDoc.expectedImageStyle(manifest)
end

local function imageStyleCss(image_style)
    if ContentType.normalizeImageStyle(image_style) == ContentType.image_full then
        return "img{display:block;width:100%;max-width:100%;height:auto;margin:0 auto;}"
    end
    return "img{display:block;max-width:100%;height:auto;margin:0 auto;}"
end

function ChapterDoc.html(chapter, content, content_type, options)
    chapter = chapter or {}
    options = options or {}
    content_type = ContentType.normalizeType(content_type)
    local body = content_type == ContentType.html and htmlBody(content)
        or textBody(content)

    return table.concat({
        "<!doctype html>",
        "<html>",
        "<head>",
        '<meta charset="utf-8"/>',
        "<title>", escapeHtml(chapter.title), "</title>",
        "<style>",
        "body{line-height:1.8;margin:5%;}",
        "h1{font-size:1.25em;line-height:1.4;margin:0 0 1.2em 0;}",
        "p{margin:0 0 0.9em 0;}",
        imageStyleCss(options.image_style),
        "</style>",
        "</head>",
        "<body>",
        "<h1>", escapeHtml(chapter.title), "</h1>",
        body,
        "</body>",
        "</html>",
    })
end

return ChapterDoc
