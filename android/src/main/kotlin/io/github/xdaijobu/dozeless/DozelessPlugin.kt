package io.github.xdaijobu.dozeless

import android.app.Activity
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DozelessPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var app: Context

    // Only the UI engine has one; background job engines run without an activity.
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        app = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dozeless")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "initialize" -> {
                    val store = JobStore(app)
                    store.dispatcherHandle = call.long("dispatcherHandle")
                    store.stopText = StopText(call.str("notificationTitle"), call.str("notificationBody"), call.str("notificationChannel"))
                    Reconciler.reconcile(app)
                    result.success(null)
                }
                "reconcile" -> {
                    Reconciler.reconcile(app)
                    result.success(null)
                }
                "schedule" -> {
                    Jobs.schedule(app, specOf(call))
                    result.success(null)
                }
                "cancel" -> {
                    Jobs.cancel(app, call.str("id"))
                    result.success(null)
                }
                "status" -> result.success(JobStore(app).get(call.str("id"))?.let(JobCodec::statusMap))
                "runNow" -> {
                    val id = call.str("id")
                    Jobs.requireJob(app, id)
                    JobReceiver.dispatch(app, id, Triggers.MANUAL)
                    result.success(null)
                }
                "checkPrerequisites" -> result.success(PrereqReader.read(app).toMap())
                "openSettings" -> result.success(SettingsOpener.open(app, call.str("setting"), activity))
                "disableForceStopGuard" -> {
                    ForceStopGuard.deactivate(app)
                    result.success(null)
                }
                "debugFireIn" -> {
                    Jobs.debugFireIn(app, call.str("id"), call.long("delayMs"))
                    result.success(null)
                }
                "debugSimulateLostAlarm" -> {
                    Jobs.debugSimulateLostAlarm(app, call.str("id"))
                    result.success(null)
                }
                "debugRunWatchdog" -> {
                    WatchdogReceiver.check(app)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("BAD_ARGUMENT", e.message, null)
        }
    }

    private fun specOf(call: MethodCall) = JobSpec(
        id = call.str("id"),
        callbackHandle = call.long("callbackHandle"),
        everyMs = call.long("everyMs"),
        timeoutMs = call.long("timeoutMs"),
        requires = call.argument<List<String>>("requires").orEmpty().mapNotNull { Prereq.fromWire(it) }.toSet(),
    )
}

/** Dart ints arrive as Integer or Long depending on their size. */
internal fun MethodCall.long(key: String): Long =
    (argument<Number>(key) ?: throw IllegalArgumentException("missing $key")).toLong()

internal fun MethodCall.str(key: String): String =
    argument<String>(key) ?: throw IllegalArgumentException("missing $key")
