package io.github.xdaijobu.dozeless

/** One run per job at a time (spec §3 step 4). Main thread only. */
internal class RunLocks {
    private val heldSince = HashMap<String, Long>()

    /** Returns a token, or null while [id] is still running and younger than [staleAfterMs]. */
    fun tryAcquire(id: String, now: Long, staleAfterMs: Long): Long? {
        val since = heldSince[id]
        if (since != null && now - since < staleAfterMs) return null
        heldSince[id] = now
        return now
    }

    /** Releases only if [token] still owns the lock, so a stale run cannot free its successor. */
    fun release(id: String, token: Long) {
        if (heldSince[id] == token) heldSince.remove(id)
    }
}
