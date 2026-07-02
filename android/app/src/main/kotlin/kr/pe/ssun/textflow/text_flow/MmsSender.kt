package kr.pe.ssun.textflow.text_flow

import android.content.Context
import android.telephony.SmsManager
import android.util.Log
import androidx.core.content.FileProvider
import java.io.ByteArrayOutputStream
import java.io.File

private const val mmsSendTag = "TextFlowMms"
private const val FILE_PROVIDER_AUTHORITY = "kr.pe.ssun.textflow.text_flow.fileprovider"

/**
 * SMS/LMS 전송 담당.
 * 단문(단일 SMS 범위 이내)은 sendTextMessage로 발송하고,
 * 장문(LMS)은 MMS PDU를 직접 조립해 sendMultimediaMessage로 발송한다.
 * 이렇게 하면 국내 통신사가 UDH 헤더를 제거하여 수신측에서 메시지가 분리되는 문제를 방지한다.
 */
object MmsSender {

    fun send(context: Context, destination: String, body: String) {
        @Suppress("DEPRECATION")
        val smsManager = SmsManager.getDefault()
        val parts = smsManager.divideMessage(body)

        if (parts.size <= 1) {
            smsManager.sendTextMessage(destination, null, body, null, null)
            return
        }

        // 단일 SMS 한도 초과 → MMS로 발송하여 수신측 분리 방지
        runCatching {
            sendAsMms(context, destination, body)
        }.onFailure { error ->
            Log.e(mmsSendTag, "MMS 발송 실패 ($destination), 멀티파트 SMS로 폴백", error)
            // 폴백: 멀티파트 SMS (일부 통신사에서 분리 수신될 수 있음)
            smsManager.sendMultipartTextMessage(destination, null, ArrayList(parts), null, null)
        }
    }

    private fun sendAsMms(context: Context, destination: String, body: String) {
        val pdu = buildMmsPdu(destination, body)
        val pduFile = writePduFile(context, pdu)
        val contentUri = FileProvider.getUriForFile(context, FILE_PROVIDER_AUTHORITY, pduFile)

        @Suppress("DEPRECATION")
        SmsManager.getDefault().sendMultimediaMessage(
            context,
            contentUri,
            null,  // locationUrl: APN 설정에서 자동 사용
            null,  // configOverrides
            null,  // sentIntent
        )
    }

    private fun writePduFile(context: Context, pdu: ByteArray): File {
        val dir = File(context.cacheDir, "mms_send").also { it.mkdirs() }
        // 이전 PDU 파일 정리
        dir.listFiles()?.forEach { it.delete() }
        return File(dir, "send_${System.currentTimeMillis()}.mms").also { it.writeBytes(pdu) }
    }

    /**
     * WAP/MMS M-Send.req PDU를 조립한다.
     *
     * 참조 규격: OMA MMS Encapsulation Specification v1.3, WAP-230-WSP
     *
     * PDU 구조:
     *   8C 80            X-Mms-Message-Type: m-send-req
     *   98 [txn-id] 00   X-Mms-Transaction-ID
     *   8D 92            X-Mms-MMS-Version: 1.2
     *   97 [to] 00       To: <번호>/TYPE=PLMN
     *   84 A3            Content-Type: application/vnd.wap.multipart.mixed
     *   [multipart body]
     */
    private fun buildMmsPdu(destination: String, body: String): ByteArray {
        val out = ByteArrayOutputStream()

        // X-Mms-Message-Type: m-send-req
        out.write(0x8C)
        out.write(0x80)

        // X-Mms-Transaction-ID (text-string)
        out.write(0x98)
        writeTextString(out, System.currentTimeMillis().toString())

        // X-Mms-MMS-Version: 1.2  (short-integer: 0x12 | 0x80 = 0x92)
        out.write(0x8D)
        out.write(0x92)

        // To: <번호>/TYPE=PLMN  (text-string)
        out.write(0x97)
        writeTextString(out, "$destination/TYPE=PLMN")

        // Content-Type: application/vnd.wap.multipart.mixed
        // WAP Content Type 0x23 → short-integer: 0x23 | 0x80 = 0xA3
        out.write(0x84)
        out.write(0xA3)

        // --- Multipart body ---
        val bodyBytes = body.toByteArray(Charsets.UTF_8)

        // 파트 Content-Type 헤더: text/plain; charset=utf-8
        //   value-length : 0x04  (이하 4바이트)
        //   text/plain   : 0x83  (well-known type 0x03 | 0x80)
        //   charset 토큰 : 0x81  (well-known param 0x01 | 0x80)
        //   long-int len : 0x01  (이하 1바이트)
        //   UTF-8 MIB    : 0x6A  (IANA charset 106)
        val partContentType = byteArrayOf(0x04, 0x83.toByte(), 0x81.toByte(), 0x01, 0x6A)

        writeUintVar(out, 1)                      // 파트 수 = 1
        writeUintVar(out, partContentType.size)   // 파트 헤더 길이
        writeUintVar(out, bodyBytes.size)          // 파트 데이터 길이
        out.write(partContentType)                 // 파트 헤더
        out.write(bodyBytes)                       // 파트 데이터 (UTF-8)

        return out.toByteArray()
    }

    /** WSP text-string: ASCII 바이트 + null 종료자 */
    private fun writeTextString(out: ByteArrayOutputStream, text: String) {
        out.write(text.toByteArray(Charsets.US_ASCII))
        out.write(0x00)
    }

    /** WSP uintvar (variable-length unsigned integer) */
    private fun writeUintVar(out: ByteArrayOutputStream, value: Int) {
        val bytes = mutableListOf<Int>()
        var remaining = value
        bytes.add(remaining and 0x7F)
        remaining = remaining ushr 7
        while (remaining > 0) {
            bytes.add((remaining and 0x7F) or 0x80)
            remaining = remaining ushr 7
        }
        bytes.reversed().forEach { out.write(it) }
    }
}
