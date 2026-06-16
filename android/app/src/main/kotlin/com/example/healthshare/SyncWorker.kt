package com.example.healthshare

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class SyncWorker(context: Context, params: WorkerParameters) : 
    CoroutineWorker(context, params) {
    
    override suspend fun doWork(): Result {
        return try {
            // Signal Flutter to do the sync via a method channel
            Result.success()
        } catch (e: Exception) {
            Result.failure()
        }
    }
}