package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

internal sealed interface JobOutcome {
    data object Success : JobOutcome
    data object Timeout : JobOutcome
    data class Failed(val error: String) : JobOutcome
    data class EngineFailed(val error: String) : JobOutcome
}

/** Owns the cached headless engine that runs Dart job callbacks. Main thread only. */
internal object DartRunner {
    private const val STARTUP_TIMEOUT_MS = 15_000L
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private var starting = false
    private var startedAt = 0L
    private val waiting = ArrayList<(String?) -> Unit>()
    private val startupTimeout = Runnable { if (!ready) failAll("ENGINE_START_TIMEOUT") }

    /**
     * Calls the Dart callback behind [callbackHandle]. [onResult] fires once: when Dart returns, or when the
     * engine cannot start. If [shouldStart] is false by the time the engine is ready, the callback is skipped.
     */
    fun invoke(
        app: Context,
        callbackHandle: Long,
        jobId: String,
        ctx: Map<String, Any?>,
        shouldStart: () -> Boolean,
        onResult: (JobOutcome) -> Unit,
    ) {
        withEngine(app) { error ->
            when {
                error != null -> onResult(JobOutcome.EngineFailed(error))
                !shouldStart() -> onResult(JobOutcome.Timeout)
                else -> channel!!.invokeMethod(
                    "runJob",
                    mapOf("jobId" to jobId, "callbackHandle" to callbackHandle, "context" to ctx),
                    object : MethodChannel.Result {
                        override fun success(result: Any?) = onResult(JobOutcome.Success)
                        override fun error(code: String, message: String?, details: Any?) =
                            onResult(JobOutcome.Failed("$code: $message"))
                        override fun notImplemented() =
                            onResult(JobOutcome.Failed("NOT_IMPLEMENTED: dispatcher did not handle runJob"))
                    },
                )
            }
        }
    }

    private fun withEngine(app: Context, then: (String?) -> Unit) {
        if (ready) return then(null)
        waiting += then
        if (starting) return
        starting = true
        startedAt = SystemClock.elapsedRealtime()
        main.postDelayed(startupTimeout, STARTUP_TIMEOUT_MS)
        val handle = JobStore(app).dispatcherHandle
        if (handle == 0L) return failAll("DISPATCHER_NOT_INITIALIZED: open the app once so Dozeless.initialize() runs")
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(app)
            loader.ensureInitializationCompleteAsync(app, null, main) {
                startEngine(app, handle, loader.findAppBundlePath())
            }
        } catch (e: Exception) {
            failAll("ENGINE_START_FAILED: $e")
        }
    }

    private fun startEngine(app: Context, handle: Long, bundlePath: String) {
        val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
            ?: return failAll("DISPATCHER_NOT_FOUND: handle $handle; open the app once")
        try {
            val eng = FlutterEngine(app)
            val ch = MethodChannel(eng.dartExecutor.binaryMessenger, "dozeless/background")
            ch.setMethodCallHandler { call, result ->
                if (call.method == "dispatcherReady") {
                    result.success(null)
                    onReady()
                } else {
                    result.notImplemented()
                }
            }
            engine = eng
            channel = ch
            eng.dartExecutor.executeDartCallback(DartExecutor.DartCallback(app.assets, bundlePath, info))
        } catch (e: Exception) {
            failAll("ENGINE_START_FAILED: $e")
        }
    }

    private fun onReady() {
        main.removeCallbacks(startupTimeout)
        ready = true
        starting = false
        Log.i(TAG, "engine ready in ${SystemClock.elapsedRealtime() - startedAt}ms")
        flush(null)
    }

    private fun failAll(error: String) {
        main.removeCallbacks(startupTimeout)
        Log.e(TAG, "engine failed: $error")
        engine?.destroy()
        engine = null
        channel = null
        ready = false
        starting = false
        flush(error)
    }

    private fun flush(error: String?) {
        val callbacks = waiting.toList()
        waiting.clear()
        callbacks.forEach { it(error) }
    }
}
