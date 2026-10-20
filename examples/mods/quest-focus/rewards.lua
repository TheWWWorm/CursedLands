local M = {}
function M.quest(value, source, bonus)
    if source == "kill" then return value end
    return value * (1 + bonus / 100)
end
return M
