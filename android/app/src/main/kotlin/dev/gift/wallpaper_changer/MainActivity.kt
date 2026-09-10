package dev.gift.wallpaper_changer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.WallpaperManager
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelId = "wallpaper_changer/wallpaper"

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, channelId)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "screenSize" -> {
                        val m = resources.displayMetrics
                        result.success(mapOf("w" to m.widthPixels, "h" to m.heightPixels))
                    }
                    "set" -> {
                        val bytes = call.argument<ByteArray>("bytes")
                        if (bytes == null) {
                            result.error("bad_args", "bytes missing", null)
                            return@setMethodCallHandler
                        }
                        val home = call.argument<Boolean>("home") ?: false
                        val lock = call.argument<Boolean>("lock") ?: false
                        try {
                            val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                ?: throw IllegalArgumentException("undecodable")
                            val wm = WallpaperManager.getInstance(this)
                            var flags = 0
                            if (home) flags = flags or WallpaperManager.FLAG_SYSTEM
                            if (lock) flags = flags or WallpaperManager.FLAG_LOCK
                            wm.setBitmap(bmp, null, true, flags)
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "notifyStale" -> {
                        val label = call.argument<String>("label") ?: "provider"
                        postStaleNotification(label)
                        result.success(null)
                    }
                    "requestNotifPermission" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(
                                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1
                            )
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun postStaleNotification(label: String) {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    "stale", "Provider health",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }
        val text = "No new wallpaper from $label for 3 days — open the app and pick another source."
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, "stale")
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val n = builder
            .setSmallIcon(android.R.drawable.stat_notify_error)
            .setContentTitle("Wallpaper Changer")
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setAutoCancel(true)
            .build()
        nm.notify(1001, n)
    }
}
