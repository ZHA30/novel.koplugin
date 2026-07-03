local ContentRule = require("novel.rule.content")
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

function ChapterDoc.expectedContentType(manifest)
    local rule = manifest and manifest.source and manifest.source.ruleContent
    return ContentRule.typeForRule(rule and rule.content)
end

function ChapterDoc.contentIsCurrent(manifest, chapter)
    return ContentRule.isCurrent(ChapterDoc.expectedContentType(manifest),
        chapter and chapter.content_type)
end

function ChapterDoc.html(chapter, content, content_type)
    chapter = chapter or {}
    content_type = ContentRule.normalizeType(content_type)
    local body = content_type == ContentRule.html and htmlBody(content)
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
        "img{max-width:100%;height:auto;}",
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
