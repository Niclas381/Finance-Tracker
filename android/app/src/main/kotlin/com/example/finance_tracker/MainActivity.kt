package com.example.finance_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import com.example.finance_tracker.inbound.InboundMessageBus
import com.example.finance_tracker.inbound.InboundMessageStore

class MainActivity : FlutterActivity() {

    private val METHOD = "inbound_messages/method"
    private val EVENTS = "inbound_messages/events"

    private var eventSink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPending" -> {
                        val arr: JSONArray = InboundMessageStore.drain(applicationContext)
                        result.success(arr.toString())
                    }
                    "clearPending" -> {
                        InboundMessageStore.clear(applicationContext)
                        result.success(null)
                    }
                    "openNotificationListenerSettings" -> {
                        try {
                            startActivity(
                                Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        } catch (_: Throwable) {
                        }
                        result.success(null)
                    }
                    "isNotificationListenerEnabled" -> {
                        result.success(isNotificationListenerEnabled())
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENTS)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    registerInboundReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterInboundReceiver()
                }
            })
    }

    private fun registerInboundReceiver() {
        if (receiver != null) return

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val payload = intent.getStringExtra(InboundMessageBus.EXTRA_PAYLOAD) ?: return
                eventSink?.success(payload)
            }
        }

        val filter = IntentFilter(InboundMessageBus.ACTION_NEW_MESSAGE)

        // Android 13+ requires explicit export flags for dynamic receivers.
        try {
            ContextCompat.registerReceiver(
                this,
                receiver,
                filter,
                ContextCompat.RECEIVER_NOT_EXPORTED
            )
        } catch (_: Throwable) {
            // fallback for older API levels / edge cases
            try {
                registerReceiver(receiver, filter)
            } catch (_: Throwable) {
            }
        }
    }

    private fun unregisterInboundReceiver() {
        val r = receiver ?: return
        receiver = null
        try {
            unregisterReceiver(r)
        } catch (_: Throwable) {
        }
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val pkg = packageName
        val flat = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        ) ?: return false
        return flat.contains(pkg)
    }
}
