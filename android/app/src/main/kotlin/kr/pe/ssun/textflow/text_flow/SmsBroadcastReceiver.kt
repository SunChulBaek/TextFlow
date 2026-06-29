package kr.pe.ssun.textflow.text_flow

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Telephony

class SmsBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }
        val safeContext = context?.applicationContext ?: return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) {
            return
        }

        val address = messages.firstOrNull()?.originatingAddress ?: "알 수 없음"
        val bodyPart = messages.joinToString(separator = "") { smsMessage ->
            smsMessage.displayMessageBody ?: smsMessage.messageBody ?: ""
        }
        val receivedAt = messages.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()

        SmsPartBuffer.addPart(safeContext, address, bodyPart, receivedAt)
    }
}

/**
 * 멀티파트 SMS/LMS가 여러 브로드캐스트로 분할 도착할 때 합쳐서 단일 이벤트로 dispatch.
 * 같은 발신자 번호의 파트가 DISPATCH_DELAY_MS 이내로 연속 도착하면 합산 후 일괄 처리.
 */
private object SmsPartBuffer {
    private val handler = Handler(Looper.getMainLooper())
    private val pendingParts = mutableMapOf<String, MutableList<String>>()
    private val pendingReceivedAt = mutableMapOf<String, Long>()
    private val pendingRunnables = mutableMapOf<String, Runnable>()
    private val lock = Any()

    private const val DISPATCH_DELAY_MS = 1000L

    fun addPart(context: Context, address: String, bodyPart: String, receivedAt: Long) {
        synchronized(lock) {
            pendingRunnables.remove(address)?.let { handler.removeCallbacks(it) }

            pendingParts.getOrPut(address) { mutableListOf() }.add(bodyPart)
            pendingReceivedAt.putIfAbsent(address, receivedAt)

            val runnable = Runnable { dispatchPending(context, address) }
            pendingRunnables[address] = runnable
            handler.postDelayed(runnable, DISPATCH_DELAY_MS)
        }
    }

    private fun dispatchPending(context: Context, address: String) {
        val body: String
        val receivedAt: Long
        synchronized(lock) {
            body = pendingParts.remove(address)?.joinToString(separator = "") ?: return
            receivedAt = pendingReceivedAt.remove(address) ?: System.currentTimeMillis()
            pendingRunnables.remove(address)
        }
        val event = mapOf(
            "messageType" to "sms",
            "address" to address,
            "body" to body,
            "receivedAt" to receivedAt,
        )
        SmsStorage.save(context, event)
        SmsForwardingEngine.forwardIfMatched(context, event)
        SmsEventBridge.dispatch(event)
    }
}


