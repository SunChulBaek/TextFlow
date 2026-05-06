package kr.pe.ssun.textflow.text_flow

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

private const val smsEventsChannel = "textflow/sms_events"
private const val smsStoreChannel = "textflow/sms_store"

private const val smsStoreName = "textflow_sms_store"
private const val keyAddress = "address"
private const val keyBody = "body"
private const val keyReceivedAt = "receivedAt"
private const val keyMessageType = "messageType"

object SmsStorage {
	fun save(context: Context, event: Map<String, Any?>) {
		context.getSharedPreferences(smsStoreName, Context.MODE_PRIVATE)
			.edit()
			.putString(keyMessageType, event[keyMessageType] as? String ?: "sms")
			.putString(keyAddress, event[keyAddress] as? String ?: "알 수 없음")
			.putString(keyBody, event[keyBody] as? String ?: "")
			.putLong(
				keyReceivedAt,
				when (val value = event[keyReceivedAt]) {
					is Long -> value
					is Int -> value.toLong()
					is Number -> value.toLong()
					is String -> value.toLongOrNull() ?: System.currentTimeMillis()
					else -> System.currentTimeMillis()
				}
			)
			.apply()
	}

	fun latest(context: Context): Map<String, Any?>? {
		val prefs = context.getSharedPreferences(smsStoreName, Context.MODE_PRIVATE)
		if (!prefs.contains(keyReceivedAt)) {
			return null
		}

		return mapOf(
			keyMessageType to (prefs.getString(keyMessageType, "sms") ?: "sms"),
			keyAddress to (prefs.getString(keyAddress, "알 수 없음") ?: "알 수 없음"),
			keyBody to (prefs.getString(keyBody, "") ?: ""),
			keyReceivedAt to prefs.getLong(keyReceivedAt, System.currentTimeMillis())
		)
	}
}

object SmsEventBridge {
	private val mainHandler = Handler(Looper.getMainLooper())
	private var eventSink: EventChannel.EventSink? = null
	private val pendingEvents = mutableListOf<Map<String, Any?>>()

	fun attachSink(sink: EventChannel.EventSink?) {
		mainHandler.post {
			eventSink = sink

			if (sink != null && pendingEvents.isNotEmpty()) {
				pendingEvents.forEach(sink::success)
				pendingEvents.clear()
			}
		}
	}

	fun dispatch(event: Map<String, Any?>) {
		mainHandler.post {
			eventSink?.success(event) ?: pendingEvents.add(event)
		}
	}
}

class MainActivity : FlutterActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)

		EventChannel(flutterEngine.dartExecutor.binaryMessenger, smsEventsChannel)
			.setStreamHandler(
				object : EventChannel.StreamHandler {
					override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
						SmsEventBridge.attachSink(events)
					}

					override fun onCancel(arguments: Any?) {
						SmsEventBridge.attachSink(null)
					}
				}
			)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsStoreChannel)
			.setMethodCallHandler { call, result ->
				when (call.method) {
					"getLatestMessage" -> result.success(SmsStorage.latest(applicationContext))
					"getLatestSms" -> result.success(SmsStorage.latest(applicationContext))
					else -> result.notImplemented()
				}
			}
	}
}
