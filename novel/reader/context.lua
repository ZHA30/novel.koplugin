local Store = require("novel.library.store")

local Context = {}

function Context.isNovelPath(path)
    path = tostring(path or "")
    local root = Store.root_dir
    return path == root or path:sub(1, #root + 1) == root .. "/"
end

function Context.byFile(file)
    if not Context.isNovelPath(file) then
        return nil
    end
    return Store:new():findContextByFile(file)
end

function Context.currentReaderFile()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader_ui = ok and ReaderUI.instance
    return reader_ui and reader_ui.document and reader_ui.document.file
end

function Context.current(plugin)
    if not plugin or not plugin.ui or not plugin.ui.document then
        return nil
    end
    return Context.byFile(plugin.ui.document.file)
end

return Context
