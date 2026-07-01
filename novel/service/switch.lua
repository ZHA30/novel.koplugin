local Search = require("novel.service.search")

local Switch = {}

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function normalizeText(value)
    return trim(value):lower():gsub("%s+", "")
end

local function sourceUrl(source)
    return source and source.bookSourceUrl or ""
end

local function sourceName(source)
    if source and source.bookSourceName and source.bookSourceName ~= "" then
        return source.bookSourceName
    end
    return sourceUrl(source)
end

local function isSearchable(source)
    return type(source) == "table"
        and source.enabled ~= false
        and source.searchUrl ~= nil
        and source.searchUrl ~= ""
        and type(source.ruleSearch) == "table"
end

local function compactError(error)
    if type(error) ~= "table" then
        return nil
    end
    return {
        kind = error.kind or "unknown",
        message = error.message or tostring(error.kind or ""),
    }
end

local function compactResponse(response)
    if type(response) ~= "table" then
        return nil
    end
    return {
        request_url = response.request_url,
        final_url = response.final_url or response.url,
        status = response.status,
        bytes = response.bytes,
    }
end

local function matchBook(target, candidate)
    local target_name = normalizeText(target.name)
    local candidate_name = normalizeText(candidate.name)
    if target_name == "" or candidate_name == "" or target_name ~= candidate_name then
        return nil
    end

    local target_author = normalizeText(target.author)
    local candidate_author = normalizeText(candidate.author)
    if target_author ~= "" and candidate_author ~= "" then
        if target_author ~= candidate_author then
            return nil
        end
        return 100, "name and author"
    end
    return 70, "name"
end

local function addCandidate(candidates, source, book, score, reason)
    table.insert(candidates, {
        source = source,
        source_name = sourceName(source),
        source_url = sourceUrl(source),
        book = book,
        score = score,
        reason = reason,
    })
end

local function sortCandidates(candidates)
    table.sort(candidates, function(left, right)
        if left.score ~= right.score then
            return left.score > right.score
        end
        if (left.source_name or "") ~= (right.source_name or "") then
            return (left.source_name or "") < (right.source_name or "")
        end
        return (left.book and left.book.bookUrl or "")
            < (right.book and right.book.bookUrl or "")
    end)
end

function Switch.find(record, sources, options)
    options = options or {}
    local search_run = options.search_run or Search.run
    local target = record and record.book or {}
    local keyword = trim(options.keyword or target.name)
    if keyword == "" then
        return {
            ok = false,
            candidates = {},
            checked = 0,
            skipped = 0,
            failed = 0,
            unsupported = {},
            error = {
                kind = "keyword",
                message = "book name is required",
            },
        }
    end

    local current_source_url = record and (record.source_url
        or sourceUrl(record.source)) or ""
    local candidates, failures, unsupported = {}, {}, {}
    local checked, skipped, failed = 0, 0, 0

    for source_index = 1, #(sources or {}) do
        local source = sources[source_index]
        if sourceUrl(source) == current_source_url and not options.include_current then
            skipped = skipped + 1
        elseif not isSearchable(source) then
            skipped = skipped + 1
        else
            checked = checked + 1
            local result = search_run(source, keyword, {
                page = options.page or 1,
                timeout = options.timeout,
                total_timeout = options.total_timeout,
                max_redirects = options.max_redirects,
            })
            for item_index = 1, #(result and result.unsupported or {}) do
                table.insert(unsupported, result.unsupported[item_index])
            end
            if not result or not result.ok then
                failed = failed + 1
                table.insert(failures, {
                    source = sourceName(source),
                    source_url = sourceUrl(source),
                    error = compactError(result and result.error),
                    response = compactResponse(result and result.response),
                })
            else
                for book_index = 1, #(result.books or {}) do
                    local book = result.books[book_index]
                    local score, reason = matchBook(target, book)
                    if score then
                        addCandidate(candidates, source, book, score, reason)
                    end
                end
            end
        end
    end

    sortCandidates(candidates)
    return {
        ok = true,
        keyword = keyword,
        candidates = candidates,
        checked = checked,
        skipped = skipped,
        failed = failed,
        failures = failures,
        unsupported = unsupported,
    }
end

return Switch
