function revival_seconds(value, context, options)
    return math.max(1, math.min(30, value * 25 / math.max(1, context.helper_intelligence)))
end

function revival_health(value, context, options)
    return math.max(value, math.min(1000000, math.floor(context.target_max_health * options.health_percent / 100)))
end
