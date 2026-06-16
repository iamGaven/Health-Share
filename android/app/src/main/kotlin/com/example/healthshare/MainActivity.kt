package com.example.healthshare

import android.content.Context
import androidx.work.*
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

class MainActivity : FlutterFragmentActivity() {

    private val CHANNEL = "com.example.healthshare/sync"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, 
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleSync" -> {
                    scheduleSyncWork()
                    result.success(null)
                }
                "cancelSync" -> {
                    cancelSyncWork()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleSyncWork() {
        // Sync every 15 minutes (minimum allowed by WorkManager)
        val syncRequest = PeriodicWorkRequestBuilder<SyncWorker>(
            15, TimeUnit.MINUTES
        )
        .setConstraints(
            Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()
        )
        .build()

        WorkManager.getInstance(applicationContext).enqueueUniquePeriodicWork(
            "healthshare_sync",
            ExistingPeriodicWorkPolicy.KEEP,
            syncRequest
        )
    }

    private fun cancelSyncWork() {
        WorkManager.getInstance(applicationContext)
            .cancelUniqueWork("healthshare_sync")
    }
}