local Manifest = require("novel.books.manifest")

local ReaderDocument = {}

function ReaderDocument.isNovelPath(path)
    path = tostring(path or "")
    local root = Manifest.root_dir
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

function ReaderDocument.chapterByFile(file)
    if not ReaderDocument.isNovelPath(file) then
        return nil
    end
    return Manifest:new():findChapterByFile(file)
end

function ReaderDocument.currentReaderFile()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader_ui = ok and ReaderUI.instance
    return reader_ui and reader_ui.document and reader_ui.document.file
end

function ReaderDocument.currentChapter(plugin)
    if not plugin or not plugin.ui or not plugin.ui.document then
        return nil
    end
    return ReaderDocument.chapterByFile(plugin.ui.document.file)
end

return ReaderDocument
