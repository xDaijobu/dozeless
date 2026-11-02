package io.github.xdaijobu.dozeless

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

/**
 * Optional Quick Settings tile; the app opts in by declaring it in its manifest. SystemUI binding the tile starts
 * the app process, which also takes a force-stopped app out of the stopped state. The jobs are repaired when the
 * tile becomes visible and when it is tapped, without opening the app.
 */
class DozelessTileService : TileService() {
    override fun onStartListening() {
        Reconciler.reconcile(applicationContext)
        render()
    }

    override fun onClick() {
        Reconciler.reconcile(applicationContext)
        Log.i(TAG, "tile clicked")
        render()
    }

    private fun render() {
        val tile = qsTile ?: return
        val jobs = JobStore(applicationContext).all()
        tile.state = when {
            jobs.isEmpty() -> Tile.STATE_UNAVAILABLE
            jobs.any { it.state.mode == Mode.STOPPED } -> Tile.STATE_INACTIVE
            else -> Tile.STATE_ACTIVE
        }
        tile.updateTile()
    }
}
