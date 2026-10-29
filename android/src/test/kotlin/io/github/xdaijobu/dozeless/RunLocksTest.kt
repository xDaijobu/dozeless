package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNull

internal class RunLocksTest {
    private val stale = 135_000L

    @Test
    fun secondRunIsRejectedWhileTheFirstIsBusy() {
        val locks = RunLocks()
        assertNotNull(locks.tryAcquire("get", 0, stale))
        assertNull(locks.tryAcquire("get", 60_000, stale))
    }

    @Test
    fun differentJobsDoNotBlockEachOther() {
        val locks = RunLocks()
        assertNotNull(locks.tryAcquire("get", 0, stale))
        assertNotNull(locks.tryAcquire("send", 0, stale))
    }

    @Test
    fun releasedLockCanBeTakenAgain() {
        val locks = RunLocks()
        val token = locks.tryAcquire("get", 0, stale)!!
        locks.release("get", token)
        assertNotNull(locks.tryAcquire("get", 1, stale))
    }

    @Test
    fun hungRunIsOverriddenOnceStale() {
        val locks = RunLocks()
        locks.tryAcquire("get", 0, stale)
        assertNull(locks.tryAcquire("get", stale - 1, stale))
        assertNotNull(locks.tryAcquire("get", stale, stale))
    }

    @Test
    fun lateReleaseOfAStaleRunDoesNotFreeItsSuccessor() {
        val locks = RunLocks()
        val first = locks.tryAcquire("get", 0, stale)!!
        locks.tryAcquire("get", stale, stale)!!
        locks.release("get", first)
        assertNull(locks.tryAcquire("get", stale + 1, stale))
    }
}
