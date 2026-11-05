package com.dinamix.dinamix

import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.telephony.SmsManager
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.sin

/**
 * Native side of the alert (report §12.3, §12.6):
 * - alarm tone on the ALARM stream at the maximum volume allowed by Android,
 *   previous volume restored on stop; the user keeps every system control;
 * - SMS through SmsManager, with the result of the sent PendingIntent.
 */
class AlertChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    private var track: AudioTrack? = null
    private var savedVolume: Int? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startAlarm" -> {
                startAlarm()
                result.success(null)
            }
            "stopAlarm" -> {
                stopAlarm()
                result.success(null)
            }
            "sendSms" -> {
                val number = call.argument<String>("number")
                val text = call.argument<String>("text")
                if (number.isNullOrBlank() || text.isNullOrBlank()) {
                    result.error("bad_args", "Numero o testo mancanti", null)
                } else {
                    sendSms(number, text, result)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun startAlarm() {
        try {
            stopAlarm()
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            try {
                savedVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
                audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0)
            } catch (e: SecurityException) {
                // Do Not Disturb policy: play at the current volume.
                Log.w(TAG, "Volume allarme non modificabile: ${e.message}")
            }
            val rate = 44100
            val samples = tone(rate)
            val t = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(rate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build(),
                )
                .setTransferMode(AudioTrack.MODE_STATIC)
                .setBufferSizeInBytes(samples.size * 2)
                .build()
            t.write(samples, 0, samples.size)
            t.setLoopPoints(0, samples.size, -1)
            t.play()
            track = t
            vibrate(true)
        } catch (e: Exception) {
            Log.e(TAG, "Allarme non avviato", e)
        }
    }

    /** 0.9 s pattern: two pulses alternating 2.0 and 2.6 kHz, with short pauses. */
    private fun tone(rate: Int): ShortArray {
        val total = (rate * 0.9).toInt()
        val out = ShortArray(total)
        for (i in 0 until total) {
            val t = i.toDouble() / rate
            val slot = t % 0.45
            val freq = if (t < 0.45) 2000.0 else 2600.0
            val on = slot < 0.32
            val ramp = minOf(1.0, slot / 0.01, (0.32 - slot) / 0.01).coerceAtLeast(0.0)
            val v = if (on) sin(2 * PI * freq * t) * ramp * 0.9 else 0.0
            out[i] = (v * Short.MAX_VALUE).toInt().toShort()
        }
        return out
    }

    private fun vibrate(on: Boolean) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (!on) {
                vibrator.cancel()
                return
            }
            val pattern = longArrayOf(0, 600, 300)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, 0)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Vibrazione non disponibile: ${e.message}")
        }
    }

    fun stopAlarm() {
        try {
            track?.let {
                it.stop()
                it.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "Arresto audio: ${e.message}")
        }
        track = null
        vibrate(false)
        savedVolume?.let { volume ->
            try {
                val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                audio.setStreamVolume(AudioManager.STREAM_ALARM, volume, 0)
            } catch (e: Exception) {
                Log.w(TAG, "Volume non ripristinato: ${e.message}")
            }
        }
        savedVolume = null
    }

    private fun sendSms(number: String, text: String, result: MethodChannel.Result) {
        val manager: SmsManager = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                context.getSystemService(SmsManager::class.java)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
        } catch (e: Exception) {
            result.success("failed:no_sms_manager")
            return
        }
        val parts = manager.divideMessage(text)
        val action = "com.dinamix.dinamix.SMS_SENT.${System.nanoTime()}"
        var pending = parts.size
        var worst = Activity.RESULT_OK
        var answered = false
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                if (resultCode != Activity.RESULT_OK) worst = resultCode
                pending--
                if (pending > 0 || answered) return
                answered = true
                try {
                    context.unregisterReceiver(this)
                } catch (_: Exception) {
                }
                val code = when (worst) {
                    Activity.RESULT_OK -> "sent"
                    SmsManager.RESULT_ERROR_NO_SERVICE -> "no_service"
                    SmsManager.RESULT_ERROR_RADIO_OFF -> "radio_off"
                    else -> "failed:$worst"
                }
                main.post { result.success(code) }
            }
        }
        try {
            val filter = IntentFilter(action)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(receiver, filter)
            }
            val intents = ArrayList<PendingIntent>()
            for (i in parts.indices) {
                val intent = Intent(action).setPackage(context.packageName)
                intents.add(PendingIntent.getBroadcast(context, i, intent, PendingIntent.FLAG_IMMUTABLE))
            }
            manager.sendMultipartTextMessage(number, null, parts, intents, null)
        } catch (e: SecurityException) {
            if (!answered) {
                answered = true
                result.success("failed:permission")
            }
        } catch (e: Exception) {
            if (!answered) {
                answered = true
                result.success("failed:${e.javaClass.simpleName}")
            }
        }
    }

    companion object {
        private const val TAG = "DYNAMIX"
    }
}
