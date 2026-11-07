package app.best.best_app.download

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundContractTest {
    @Test fun aColdEngineCannotFinishBeforeItsDatabaseSnapshot() {
        assertFalse(DownloadSnapshot().canFinish)
    }

    @Test fun aPendingQueueWithUnknownPageCountStillNeedsItsEngine() {
        assertFalse(DownloadSnapshot(ready = true, pending = true).canFinish)
    }

    @Test fun onlyAnAcknowledgedIdleSnapshotCanEndTheLifetime() {
        assertTrue(DownloadSnapshot(ready = true, pending = false).canFinish)
    }
}
