package net.ohrtech.device.flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import net.ohrtech.device.push.OhrPushMessage
import net.ohrtech.device.push.OhrPushService
import net.ohrtech.device.push.PushToken
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The plugin's push service (declared in its manifest): the library checks and opens each message,
 * then the app's Dart handler runs in a background isolate. The service waits for the handler (up
 * to [PushDispatcher.HANDLER_MS]) so the process stays up while it works.
 */
class OhrDevicePushService : OhrPushService() {
    /** A message the Dart handler didn't take is reported to the hub as dropped (see [PushDispatcher.deliver]'s reasons). */
    override fun onMessage(message: OhrPushMessage) {
        val failed = PushDispatcher.deliver(applicationContext, "message") { api, h ->
            if (h.onMessage == 0L) throw NotHandled("no_handler")
            api.onMessage(h.onMessage, message.toPigeon())
        }
        if (failed != null) throw NotHandled(failed)
    }

    override fun onTokenChanged(token: PushToken?) {
        PushDispatcher.deliver(applicationContext, "token") { api, h -> if (h.onTokenChanged != 0L) api.onTokenChanged(h.onTokenChanged, token?.toPigeon()) }
    }

    override fun onDropped(pushId: String, reason: String) {
        PushDispatcher.deliver(applicationContext, "dropped") { api, h -> if (h.onDropped != 0L) api.onDropped(h.onDropped, pushId, reason) }
    }
}

/**
 * The background isolate for push: started on the first message with the plugin's dispatcher entry
 * point, kept for the life of the process. The app registers its handlers' callback handles from
 * Dart ([setHandlers]); they are kept in the app's preferences, for a process started by a message.
 */
internal object PushDispatcher : OhrPushBackgroundHostApi {
    private const val TAG = "OhrDevicePush"
    private const val PREFS = "net.ohrtech.device.flutter.push"
    const val HANDLER_MS = 25_000L

    data class Handles(val dispatcher: Long, val onMessage: Long, val onTokenChanged: Long, val onDropped: Long)

    fun setHandlers(context: Context, h: Handles) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong("dispatcher", h.dispatcher).putLong("onMessage", h.onMessage)
            .putLong("onTokenChanged", h.onTokenChanged).putLong("onDropped", h.onDropped).apply()
    }

    private fun handles(context: Context): Handles = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).let {
        Handles(it.getLong("dispatcher", 0), it.getLong("onMessage", 0), it.getLong("onTokenChanged", 0), it.getLong("onDropped", 0))
    }

    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var api: OhrPushFlutterApi? = null

    @Volatile
    private var ready = CountDownLatch(1)

    /** The background isolate set up its side. */
    override fun ready() = ready.countDown()

    /**
     * Runs [call] in the background isolate and waits for it (on the service's worker thread). Null when it ran,
     * else why not: "no_handler" (OhrPush.setHandlers never ran), "no_engine" (the background isolate didn't start),
     * "handler_timeout", or "handler" (it threw).
     */
    fun deliver(context: Context, what: String, call: suspend (OhrPushFlutterApi, Handles) -> Unit): String? {
        val h = handles(context)
        if (h.dispatcher == 0L) {
            Log.w(TAG, "Push $what: the app registered no handler (OhrPush.setHandlers)")
            return "no_handler"
        }
        val started = CountDownLatch(1)
        var bg: OhrPushFlutterApi? = null
        main.post {
            try {
                bg = start(context, h.dispatcher)
            } catch (e: Exception) {
                Log.e(TAG, "Push $what: couldn't start the background isolate", e)
            }
            started.countDown()
        }
        started.await()
        val a = bg ?: return "no_engine"
        if (!ready.await(HANDLER_MS, TimeUnit.MILLISECONDS)) {
            Log.e(TAG, "Push $what: the background isolate didn't start in time")
            return "no_engine"
        }
        val done = CountDownLatch(1)
        var failed: String? = "handler_timeout"
        CoroutineScope(Dispatchers.Main).launch {
            try {
                if (withTimeoutOrNull(HANDLER_MS) { call(a, h) } == null) {
                    Log.w(TAG, "Push $what: the handler took longer than ${HANDLER_MS / 1000} s")
                } else {
                    failed = null
                }
            } catch (e: OhrPushService.NotHandled) {
                Log.w(TAG, "Push $what: ${e.reason}")
                failed = e.reason
            } catch (e: Exception) {
                Log.e(TAG, "Push $what: the handler threw", e)
                failed = "handler"
            } finally {
                done.countDown()
            }
        }
        done.await(HANDLER_MS + 2_000, TimeUnit.MILLISECONDS)
        return failed
    }

    /** The engine (on the main thread), started once. */
    private fun start(context: Context, dispatcher: Long): OhrPushFlutterApi {
        api?.let { return it }
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(context)
        loader.ensureInitializationComplete(context, null)
        val info = FlutterCallbackInformation.lookupCallbackInformation(dispatcher)
            ?: throw IllegalStateException("no callback for the push dispatcher: register the handlers again after an update")
        ready = CountDownLatch(1)
        val e = FlutterEngine(context)
        e.dartExecutor.executeDartCallback(DartExecutor.DartCallback(context.assets, loader.findAppBundlePath(), info))
        engine = e
        return OhrPushFlutterApi(e.dartExecutor.binaryMessenger).also { api = it }
    }
}
