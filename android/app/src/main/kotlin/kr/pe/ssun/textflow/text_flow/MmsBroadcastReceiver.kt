package kr.pe.ssun.textflow.text_flow

import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Telephony

class MmsBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val safeContext = context ?: return
        val action = intent?.action ?: return
        val mimeType = intent.type

        val isMmsPush = action == Telephony.Sms.Intents.WAP_PUSH_RECEIVED_ACTION ||
            action == Telephony.Sms.Intents.WAP_PUSH_DELIVER_ACTION
        val isMmsMime = mimeType == null || mimeType.equals(MMS_MIME_TYPE, ignoreCase = true)
        if (!isMmsPush || !isMmsMime) {
            return
        }

        // MMS 파트가 아직 DB에 완전히 기록되기 전 브로드캐스트가 도착할 수 있어,
        // 짧게 지연 후 조회하고 MMS ID 기반으로 중복 처리를 막습니다.
        val pendingResult = goAsync()
        Handler(Looper.getMainLooper()).postDelayed({
            try {
                val mmsEvent = runCatching { buildLatestMmsEvent(safeContext) }.getOrNull() ?: return@postDelayed
                if (isDuplicateMms(safeContext, mmsEvent.id, mmsEvent.receivedAt)) {
                    return@postDelayed
                }

                markProcessedMms(safeContext, mmsEvent.id, mmsEvent.receivedAt)
                val event = mmsEvent.toChannelMap()
                SmsStorage.save(safeContext, event)
                SmsForwardingEngine.forwardIfMatched(safeContext, event)
                SmsEventBridge.dispatch(event)
            } finally {
                pendingResult.finish()
            }
        }, MMS_QUERY_DELAY_MS)
    }

    private fun buildLatestMmsEvent(context: Context): MmsEvent? {
        val resolver = context.contentResolver
        val inboxUri = Uri.parse("content://mms/inbox")
        val projection = arrayOf("_id", "date")

        resolver.query(inboxUri, projection, null, null, "date DESC")?.use { cursor ->
            if (!cursor.moveToFirst()) {
                return null
            }

            val id = cursor.getString(cursor.getColumnIndexOrThrow("_id"))
            val timestampSeconds = cursor.getLong(cursor.getColumnIndexOrThrow("date"))
            val receivedAt = if (timestampSeconds > 0L) {
                timestampSeconds * 1000L
            } else {
                System.currentTimeMillis()
            }

            val address = queryMmsAddress(context, id)
            val body = queryMmsTextBody(context, id)

            return MmsEvent(
                id = id,
                address = address,
                body = body,
                receivedAt = receivedAt,
            )
        }

        return null
    }

    private fun isDuplicateMms(context: Context, mmsId: String, receivedAt: Long): Boolean {
        val prefs = context.getSharedPreferences(MMS_RECEIVER_PREFS, Context.MODE_PRIVATE)
        val lastId = prefs.getString(KEY_LAST_MMS_ID, null)
        val lastReceivedAt = prefs.getLong(KEY_LAST_MMS_RECEIVED_AT, -1L)
        return lastId == mmsId && lastReceivedAt == receivedAt
    }

    private fun markProcessedMms(context: Context, mmsId: String, receivedAt: Long) {
        context.getSharedPreferences(MMS_RECEIVER_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LAST_MMS_ID, mmsId)
            .putLong(KEY_LAST_MMS_RECEIVED_AT, receivedAt)
            .apply()
    }

    private fun queryMmsAddress(context: Context, messageId: String): String {
        val uri = Uri.parse("content://mms/$messageId/addr")
        val projection = arrayOf("address", "type")
        val selection = "type=137"

        context.contentResolver.query(uri, projection, selection, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val address = cursor.getString(cursor.getColumnIndexOrThrow("address")) ?: continue
                if (address.isNotBlank() && address != "insert-address-token") {
                    return address
                }
            }
        }

        return "알 수 없음"
    }

    private fun queryMmsTextBody(context: Context, messageId: String): String {
        val uri = Uri.parse("content://mms/part")
        val projection = arrayOf("_id", "ct", "text")
        val selection = "mid=?"
        val selectionArgs = arrayOf(messageId)
        val textParts = mutableListOf<String>()

        context.contentResolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val contentType = cursor.getString(cursor.getColumnIndexOrThrow("ct")) ?: continue
                if (!contentType.startsWith("text/")) {
                    continue
                }

                val directText = cursor.getString(cursor.getColumnIndexOrThrow("text"))
                if (!directText.isNullOrBlank()) {
                    textParts.add(directText)
                    continue
                }

                val partId = cursor.getString(cursor.getColumnIndexOrThrow("_id"))
                val partIdLong = partId.toLongOrNull() ?: continue
                val partUri = ContentUris.withAppendedId(Uri.parse("content://mms/part"), partIdLong)
                context.contentResolver.openInputStream(partUri)?.bufferedReader()?.use { reader ->
                    val text = reader.readText()
                    if (text.isNotBlank()) {
                        textParts.add(text)
                    }
                }
            }
        }

        return textParts.joinToString(separator = "\n").ifBlank { "(MMS 본문 없음 또는 첨부 전용)" }
    }

    companion object {
        private const val MMS_RECEIVER_PREFS = "textflow_mms_receiver_store"
        private const val KEY_LAST_MMS_ID = "last_mms_id"
        private const val KEY_LAST_MMS_RECEIVED_AT = "last_mms_received_at"
        private const val MMS_QUERY_DELAY_MS = 1200L
        private const val MMS_MIME_TYPE = "application/vnd.wap.mms-message"
    }
}

private data class MmsEvent(
    val id: String,
    val address: String,
    val body: String,
    val receivedAt: Long,
) {
    fun toChannelMap(): Map<String, Any?> {
        return mapOf(
            "messageType" to "mms",
            "address" to address,
            "body" to body,
            "receivedAt" to receivedAt,
        )
    }
}

