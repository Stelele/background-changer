package dev.gift.wallpaper_plugin

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.WallpaperManager
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.graphics.Point
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class WallpaperPlugin : FlutterPlugin, ActivityAware {
    private val channelId = "wallpaper_changer/wallpaper"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var activity: Activity? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        MethodChannel(binding.binaryMessenger, channelId).setMethodCallHandler { call, result ->
            when (call.method) {
                "screenSize" -> {
                    val size = physicalDisplaySize(binding.applicationContext)
                    result.success(mapOf("w" to size.first, "h" to size.second))
                }
                "set" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null) {
                        result.error("bad_args", "bytes missing", null)
                        return@setMethodCallHandler
                    }
                    val home = call.argument<Boolean>("home") ?: false
                    val lock = call.argument<Boolean>("lock") ?: false
                    val appContext = binding.applicationContext
                    worker.execute {
                        val ok = try {
                            applyWallpaper(appContext, bytes, home, lock)
                        } catch (t: Throwable) {
                            Log.e("WallpaperPlugin", "set failed", t)
                            false
                        }
                        mainHandler.post { result.success(ok) }
                    }
                }
                "notifyStale" -> {
                    val label = call.argument<String>("label") ?: "provider"
                    postStaleNotification(binding.applicationContext, label)
                    result.success(null)
                }
                "requestNotifPermission" -> {
                    val act = activity
                    if (act != null && Build.VERSION.SDK_INT >= 33 &&
                        act.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                    ) {
                        act.requestPermissions(
                            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 1
                        )
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Channel handlers die with the engine's messenger; nothing to clean up.
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    private fun applyWallpaper(
        context: android.content.Context,
        bytes: ByteArray,
        home: Boolean,
        lock: Boolean
    ): Boolean {
        val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return false
        val wm = WallpaperManager.getInstance(context)
        var flags = 0
        if (home) flags = flags or WallpaperManager.FLAG_SYSTEM
        if (lock) flags = flags or WallpaperManager.FLAG_LOCK
        return try {
            wm.setBitmap(bmp, null, true, flags)
            true
        } catch (e: Exception) {
            Log.w("WallpaperPlugin", "combined setBitmap failed, falling back", e)
            var ok = true
            if (home) {
                try {
                    wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_SYSTEM)
                } catch (e2: Exception) {
                    Log.e("WallpaperPlugin", "home set failed", e2)
                    ok = false
                }
            }
            if (lock) {
                try {
                    wm.setBitmap(bmp, null, true, WallpaperManager.FLAG_LOCK)
                } catch (e2: Exception) {
                    Log.e("WallpaperPlugin", "lock set failed", e2)
                    ok = false
                }
            }
            ok
        }
    }

    private fun physicalDisplaySize(context: android.content.Context): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                val wm = context.getSystemService(android.view.WindowManager::class.java)
                val b = wm.maximumWindowMetrics.bounds
                return Pair(b.width(), b.height())
            } catch (e: Exception) {
                Log.w("WallpaperPlugin", "maximumWindowMetrics failed", e)
            }
        }
        return fallbackSize(context)
    }

    @Suppress("DEPRECATION")
    private fun fallbackSize(context: android.content.Context): Pair<Int, Int> {
        return try {
            val dm = context.getSystemService(android.hardware.display.DisplayManager::class.java)
            val d = dm.getDisplay(android.view.Display.DEFAULT_DISPLAY)
            val p = Point()
            d.getRealSize(p)
            Pair(p.x, p.y)
        } catch (e: Exception) {
            val m = context.resources.displayMetrics
            Pair(m.widthPixels, m.heightPixels)
        }
    }

    private fun postStaleNotification(context: android.content.Context, label: String) {
        val nm = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    "stale", "Provider health",
                    NotificationManager.IMPORTANCE_DEFAULT
                )
            )
        }
        val text =
            "No new wallpaper from $label for 3 days — open the app and pick another source."
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, "stale")
        } else {
            @Suppress("DEPRECATION") Notification.Builder(context)
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
