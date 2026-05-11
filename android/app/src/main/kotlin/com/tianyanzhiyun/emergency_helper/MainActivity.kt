package com.tianyanzhiyun.emergency_helper

import android.app.NotificationManager
import android.content.Context
import android.os.Bundle
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
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
        // Custom channel for TRTC incoming call workaround
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tianyanzhiyun/trtc_workaround"
        ).setMethodCallHandler { call, result ->
            if (call.method == "stopIncomingCallAndFinish") {
                stopIncomingCallAndFinish(result)
            } else if (call.method == "queryCallState") {
                queryCallState(result)
            } else {
                result.notImplemented()
            }
        }
        // EventChannel: streams native TUICallObserver callbacks to Flutter.
        // This bypasses the rtc_room_engine FFI bug that doesn't forward
        // onCallNotConnected events (e.g., otherDeviceAccepted).
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.tianyanzhiyun/trtc_call_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                CallStateTracker.setEventSink(events)
                Log.d(TAG, "trtc_call_events: Flutter listener attached")
            }
            override fun onCancel(arguments: Any?) {
                CallStateTracker.setEventSink(null)
                Log.d(TAG, "trtc_call_events: Flutter listener removed")
            }
        })
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

    /**
     * Query the current call state via TUICallEngine.callExperimentalAPI.
     * Tries multiple experimental API names to find one that returns call state.
     * This accesses the same native .so that the Flutter FFI uses.
     */
    private fun queryCallState(result: MethodChannel.Result) {
        try {
            val candidateClasses = listOf(
                "com.tencent.cloud.tuikit.engine.call.TUICallEngine",
            )
            for (className in candidateClasses) {
                try {
                    val engineClass = Class.forName(className)
                    // TUICallEngine uses createInstance(Context) and destroyInstance()
                    // We need the existing instance, not create a new one.
                    // Try to get the sInstance field from TUICallEngineImpl
                    val implClass = Class.forName(
                        "com.tencent.cloud.tuikit.engine.impl.call.TUICallEngineImpl"
                    )
                    val sInstanceField = implClass.getDeclaredField("sInstance")
                    sInstanceField.isAccessible = true
                    val engine = sInstanceField.get(null)
                    if (engine == null) {
                        Log.d(TAG, "queryCallState: TUICallEngineImpl.sInstance is null")
                        result.success("idle")
                        return
                    }

                    // Try callExperimentalAPI with various API names
                    val expApiMethod = engineClass.getMethod(
                        "callExperimentalAPI",
                        String::class.java
                    )

                    val apiNames = listOf(
                        "getCallState",
                        "getCurrentCallState",
                        "getCallInfo",
                        "status",
                        "getCallStatus",
                        "checkCallState",
                        "queryCallState",
                        "engineStatus",
                        "getEngineStatus",
                    )

                    for (apiName in apiNames) {
                        try {
                            val jsonParam = "{\"api\":\"$apiName\"}"
                            val expResult = expApiMethod.invoke(engine, jsonParam)
                            Log.d(TAG, "queryCallState: $apiName → $expResult")
                        } catch (e: Exception) {
                            // API not available
                        }
                    }

                    // Also try the query(String, String) method
                    try {
                        val queryMethod = engineClass.getMethod(
                            "query",
                            String::class.java,
                            String::class.java
                        )
                        val queryResult = queryMethod.invoke(engine, "callState", "")
                        Log.d(TAG, "queryCallState: query(\"callState\",\"\") → $queryResult")
                    } catch (e: Exception) {
                        Log.d(TAG, "queryCallState: query method not available")
                    }

                    // Fallback: check CallStateTracker (native observer)
                    val state = CallStateTracker.callState
                    Log.d(TAG, "queryCallState: tracker state=$state")
                    result.success(state)
                    return
                } catch (e: ClassNotFoundException) {
                    // Class not found
                }
            }
            Log.w(TAG, "queryCallState: TUICallEngine class not found")
            result.success("class_not_found")
        } catch (e: Exception) {
            Log.e(TAG, "queryCallState: exception", e)
            result.success("error:${e.message}")
        }
    }

    /**
     * Native-side workaround to stop incoming call vibration and ringtone.
     * Called when another device already accepted the call (FFI bug workaround).
     * This directly calls TUICallEngine.hangup() which properly closes the
     * incoming call UI, stops vibration, and stops ringtone.
     */
    private fun stopIncomingCallAndFinish(result: MethodChannel.Result) {
        Log.d(TAG, "stopIncomingCallAndFinish: called")
        try {
            // 1. Stop system vibrator immediately
            try {
                val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? android.os.Vibrator
                vibrator?.cancel()
                Log.d(TAG, "stopIncomingCallAndFinish: system vibrator cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "stopIncomingCallAndFinish: cancel vibrator failed", e)
            }

            // 2. Cancel notification
            try {
                val notificationManager =
                    getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                notificationManager?.cancel(9909)
                Log.d(TAG, "stopIncomingCallAndFinish: notification cancelled")
            } catch (e: Exception) {
                Log.e(TAG, "stopIncomingCallAndFinish: cancel notification failed", e)
            }

            // 3. Call TUICallEngine.hangup() natively via reflection.
            //    TUICallEngine is from the rtc_room_engine AAR.
            //    hangup() will:
            //    - Close the incoming call activity/overlay
            //    - Stop vibration (stops the CallingVibrator HandlerThread)
            //    - Stop ringtone
            //    Since another device already accepted, this only cleans local state.
            var hangupCalled = false
            try {
                // Try various possible TUICallEngine class names
                val candidateClasses = listOf(
                    "com.tencent.cloud.tuikit.engine.call.TUICallEngine",
                    "io.trtc.uikit.tuicalling.TUICallEngine",
                    "com.tencent.qcloud.timtuicalling.TUICallEngine",
                    "com.tencent.qcloud.tuikit.tuicalling.TUICallEngine",
                    "com.tencent.trtc.tuicalling.TUICallEngine",
                )
                for (className in candidateClasses) {
                    try {
                        val engineClass = Class.forName(className)
                        val instanceMethod = engineClass.getDeclaredMethod("instance")
                        instanceMethod.isAccessible = true
                        val engine = instanceMethod.invoke(null)
                        val hangupMethod = engineClass.getDeclaredMethod("hangup")
                        hangupMethod.invoke(engine)
                        Log.d(TAG, "stopIncomingCallAndFinish: $className.hangup() called")
                        hangupCalled = true
                        break
                    } catch (e: ClassNotFoundException) {
                        // Try next class
                    }
                }
                if (!hangupCalled) {
                    Log.w(TAG, "stopIncomingCallAndFinish: TUICallEngine class not found")
                }
            } catch (e: Exception) {
                Log.e(TAG, "stopIncomingCallAndFinish: TUICallEngine.hangup failed", e)
            }

            // 4. If hangup didn't work, try reject() as fallback
            if (!hangupCalled) {
                try {
                    val candidateClasses = listOf(
                        "com.tencent.cloud.tuikit.engine.call.TUICallEngine",
                        "io.trtc.uikit.tuicalling.TUICallEngine",
                        "com.tencent.qcloud.timtuicalling.TUICallEngine",
                        "com.tencent.qcloud.tuikit.tuicalling.TUICallEngine",
                        "com.tencent.trtc.tuicalling.TUICallEngine",
                    )
                    for (className in candidateClasses) {
                        try {
                            val engineClass = Class.forName(className)
                            val instanceMethod = engineClass.getDeclaredMethod("instance")
                            instanceMethod.isAccessible = true
                            val engine = instanceMethod.invoke(null)
                            val rejectMethod = engineClass.getDeclaredMethod("reject")
                            rejectMethod.invoke(engine)
                            Log.d(TAG, "stopIncomingCallAndFinish: $className.reject() called")
                            hangupCalled = true
                            break
                        } catch (e: ClassNotFoundException) {
                            // Try next class
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "stopIncomingCallAndFinish: TUICallEngine.reject failed", e)
                }
            }

            // 5. Last resort: also call CallingVibrator.stopVibration() via reflection
            //    to kill the HandlerThread loop directly
            try {
                val cvClass = Class.forName(
                    "com.tencent.cloud.tuikit.flutter.tuicallkit.utils.CallingVibrator"
                )
                // Get the singleton instance from TencentCallsUikitPlugin
                val pluginClass = Class.forName(
                    "com.tencent.cloud.tuikit.flutter.tuicallkit.TencentCallsUikitPlugin"
                )
                val companionField = pluginClass.getDeclaredField("Companion")
                companionField.isAccessible = true
                val companion = companionField.get(null)
                val channelField = pluginClass.getDeclaredField("channel")
                channelField.isAccessible = true
                // We can't directly get the CallingVibrator instance from here,
                // so create a new one and call stopVibration to cancel system vibrator
                val cvConstructor = cvClass.getDeclaredConstructor(Context::class.java)
                cvConstructor.isAccessible = true
                val cvInstance = cvConstructor.newInstance(applicationContext)
                val stopVibMethod = cvClass.getDeclaredMethod("stopVibration")
                stopVibMethod.invoke(cvInstance)
                Log.d(TAG, "stopIncomingCallAndFinish: CallingVibrator.stopVibration() called")
            } catch (e: Exception) {
                Log.e(TAG, "stopIncomingCallAndFinish: CallingVibrator.stopVibration failed", e)
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "stopIncomingCallAndFinish: exception", e)
            result.error("STOP_INCOMING_FAILED", e.message, null)
        }
    }
}
