package com.tianyanzhiyun.emergency_helper

import android.os.Bundle
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class MainActivity : FlutterActivity() {

    private val TAG = "MainActivity"
    private val nativeLoginExecutor = Executors.newSingleThreadExecutor()

    override fun onCreate(savedInstanceState: Bundle?) {
        val start = System.currentTimeMillis()
        Log.d(TAG, "onCreate start")
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate done in ${System.currentTimeMillis() - start}ms")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tianyanzhiyun/push_honor"
        ).setMethodCallHandler { call, result ->
            if (call.method == "registerHonorPush") {
                (application as? MainApplication)?.registerHonorPush()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tianyanzhiyun/device_brand"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getDeviceBrand") {
                result.success(Build.BRAND)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tianyanzhiyun/tuicallkit_login"
        ).setMethodCallHandler { call, result ->
            if (call.method == "nativeLogin") {
                val sdkAppId = call.argument<Int>("sdkAppId") ?: run {
                    result.error("INVALID_ARGS", "sdkAppId is required", null)
                    return@setMethodCallHandler
                }
                val userId = call.argument<String>("userId") ?: run {
                    result.error("INVALID_ARGS", "userId is required", null)
                    return@setMethodCallHandler
                }
                val userSig = call.argument<String>("userSig") ?: run {
                    result.error("INVALID_ARGS", "userSig is required", null)
                    return@setMethodCallHandler
                }

                Log.d(TAG, "nativeLogin: sdkAppId=$sdkAppId, userId=$userId")
                nativeLoginExecutor.execute {
                    nativeLogin(sdkAppId, userId, userSig, result)
                }
            } else if (call.method == "nativeLogout") {
                Log.d(TAG, "nativeLogout: called")
                nativeLoginExecutor.execute {
                    nativeLogout(result)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun nativeLogin(
        sdkAppId: Int,
        userId: String,
        userSig: String,
        result: MethodChannel.Result
    ) {
        val manager = com.tencent.imsdk.v2.V2TIMManager.getInstance()
        val currentUser = manager.loginUser

        Log.d(TAG, "nativeLogin: current loginUser=$currentUser")

        if (currentUser == userId) {
            Log.d(TAG, "nativeLogin: same user already logged in, treating as success")
            result.success(
                mapOf(
                    "success" to true,
                    "alreadyLoggedIn" to true
                )
            )
            return
        }

        if (currentUser.isNullOrEmpty()) {
            // SDK not initialized — init first using reflection to avoid API mismatch
            Log.d(TAG, "nativeLogin: SDK not initialized, initializing now")
            val initOk = initIMSDK(sdkAppId)
            if (!initOk) {
                Log.w(TAG, "nativeLogin: initSDK failed, trying login anyway")
            }
        } else {
            Log.d(TAG, "nativeLogin: switching user from $currentUser to $userId, logout first")
            val logoutOk = blockingLogout(manager)
            if (!logoutOk) {
                Log.w(TAG, "nativeLogin: logout before switch timed out/failed, continue login")
            }
        }

        // Now perform login
        val latch = CountDownLatch(1)
        var loginResult: Map<String, Any>? = null

        manager.login(userId, userSig, object : com.tencent.imsdk.v2.V2TIMCallback {
            override fun onSuccess() {
                Log.d(TAG, "nativeLogin: login onSuccess")
                loginResult = mapOf("success" to true)
                latch.countDown()
            }
            override fun onError(code: Int, msg: String) {
                Log.e(TAG, "nativeLogin: login onError code=$code msg=$msg")
                val latestLoginUser = manager.loginUser
                val alreadyLoggedInAsTarget =
                    latestLoginUser != null && latestLoginUser == userId
                if (alreadyLoggedInAsTarget || isAlreadyLoginError(code, msg)) {
                    Log.w(
                        TAG,
                        "nativeLogin: onError but session is already ready, treat as success. " +
                                "code=$code, loginUser=$latestLoginUser"
                    )
                    loginResult = mapOf(
                        "success" to true,
                        "alreadyLoggedIn" to true,
                        "errorCode" to code,
                        "errorMessage" to msg
                    )
                } else {
                    loginResult = mapOf(
                        "success" to false,
                        "errorCode" to code,
                        "errorMessage" to msg
                    )
                }
                latch.countDown()
            }
        })

        // Wait for result with timeout
        val completed = latch.await(15, TimeUnit.SECONDS)
        if (completed && loginResult != null) {
            result.success(loginResult)
        } else {
            result.success(mapOf("success" to false, "errorMessage" to "Login timed out after 15s"))
        }
    }

    private fun blockingLogout(
        manager: com.tencent.imsdk.v2.V2TIMManager,
        timeoutSeconds: Long = 8L
    ): Boolean {
        val latch = CountDownLatch(1)
        var success = false
        manager.logout(object : com.tencent.imsdk.v2.V2TIMCallback {
            override fun onSuccess() {
                Log.d(TAG, "blockingLogout: onSuccess")
                success = true
                latch.countDown()
            }

            override fun onError(code: Int, msg: String) {
                Log.e(TAG, "blockingLogout: onError code=$code msg=$msg")
                latch.countDown()
            }
        })
        val completed = latch.await(timeoutSeconds, TimeUnit.SECONDS)
        return completed && success
    }

    private fun isAlreadyLoginError(code: Int, msg: String?): Boolean {
        val normalized = msg?.lowercase() ?: ""
        return normalized.contains("already login") ||
                normalized.contains("already logged") ||
                normalized.contains("has login") ||
                normalized.contains("repeated login") ||
                normalized.contains("重复登录")
    }

    private fun initIMSDK(sdkAppId: Int): Boolean {
        return try {
            val manager = com.tencent.imsdk.v2.V2TIMManager.getInstance()
            val config = com.tencent.imsdk.v2.V2TIMSDKConfig()
            config.logLevel = com.tencent.imsdk.v2.V2TIMSDKConfig.V2TIM_LOG_NONE
            val ok = manager.initSDK(applicationContext, sdkAppId, config)
            Log.d(TAG, "initIMSDK: result=$ok")
            ok
        } catch (e: Exception) {
            Log.e(TAG, "initIMSDK: failed", e)
            false
        }
    }

    private fun nativeLogout(result: MethodChannel.Result) {
        try {
            val manager = com.tencent.imsdk.v2.V2TIMManager.getInstance()
            manager.logout(object : com.tencent.imsdk.v2.V2TIMCallback {
                override fun onSuccess() {
                    Log.d(TAG, "nativeLogout: onSuccess")
                }
                override fun onError(code: Int, msg: String) {
                    Log.e(TAG, "nativeLogout: onError code=$code msg=$msg")
                }
            })
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "nativeLogout: exception ${e.message}", e)
            result.success(null)
        }
    }
}
