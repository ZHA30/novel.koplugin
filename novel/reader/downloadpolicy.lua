local DownloadPolicy = {
    max_attempts = 3,
    retry_delays = { 2, 5 },
    checkpoint_changes = 20,
}

function DownloadPolicy.retryAt(failed_attempts, timestamp)
    failed_attempts = tonumber(failed_attempts) or 0
    local delay = DownloadPolicy.retry_delays[failed_attempts]
    if not delay or failed_attempts >= DownloadPolicy.max_attempts then
        return nil
    end
    return (tonumber(timestamp) or os.time()) + delay
end

function DownloadPolicy.shouldCheckpoint(changes)
    return (tonumber(changes) or 0) >= DownloadPolicy.checkpoint_changes
end

return DownloadPolicy
