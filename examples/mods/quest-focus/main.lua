local rewards = require("rewards")
function experience_reward(value, context, options)
    return rewards.quest(value, context.source, options.bonus)
end
