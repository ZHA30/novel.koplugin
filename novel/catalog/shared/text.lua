local Text = {}

function Text.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function Text.isBlank(value)
    return value == nil or Text.trim(value) == ""
end

return Text
