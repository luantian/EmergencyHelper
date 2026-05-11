package com.tianyanzhiyun.emergency_helper

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.Log
import com.baidu.mapapi.base.BmfMapApplication
import com.tencent.chat.flutter.push.tencent_cloud_chat_push.TencentCloudChatPushPlugin
import com.tencent.chat.flutter.push.tencent_cloud_chat_push.common.Extras
import com.tencent.chat.flutter.push.tencent_cloud_chat_push.common.Utils
import com.tencent.qcloud.tim.push.TIMPushListener
import com.tencent.qcloud.tim.push.TIMPushManager
import com.tencent.qcloud.tim.push.TIMPushMessage
import com.tencent.qcloud.tuicore.TUIConstants
import com.tencent.qcloud.tuicore.TUICore
import com.tencent.cloud.tuikit.engine.call.TUICallEngine
import com.tencent.cloud.tuikit.engine.call.TUICallObserver
import com.tencent.cloud.tuikit.engine.call.TUICallDefine
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel

/**
 * Tracks TUICallEngine call state via a native observer.
 * This bypasses the FFI bug where onCallNotConnected/onCallEnd aren't
 * forwarded for otherDeviceAccepted events.
 */
object CallStateTracker : TUICallObserver() {
    @Volatile var currentCallId: String? = null
    @Volatile var callState: String = "idle" // idle | incomingRinging | inCall
    @Volatile var registered = false

    /// EventChannel sink to push call events to Flutter
    private var eventSink: EventChannel.EventSink? = null
    private var eventChannel: EventChannel? = null

    fun setEventChannel(channel: EventChannel?) {
        eventChannel = channel
    }

    fun setEventSink(sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    private fun sendEventToFlutter(eventName: String, data: Map<String, String>) {
        eventSink?.success(mapOf("event" to eventName, "data" to data))
        Log.d("CallStateTracker", "sendEventToFlutter: $eventName data=$data")
    }

    override fun onCallReceived(
        callId: String,
        userId: String,
        calleeList: List<String>,
        mediaType: TUICallDefine.MediaType,
        extraInfo: TUICallDefine.CallObserverExtraInfo
    ) {
        currentCallId = callId
        callState = "incomingRinging"
        Log.d("CallStateTracker", "onCallReceived callId=$callId")
        sendEventToFlutter("onCallReceived", mapOf(
            "callId" to callId,
            "userId" to userId,
            "mediaType" to mediaType.value.toString()
        ))
    }

    override fun onCallBegin(
        callId: String,
        mediaType: TUICallDefine.MediaType,
        extraInfo: TUICallDefine.CallObserverExtraInfo
    ) {
        callState = "inCall"
        Log.d("CallStateTracker", "onCallBegin callId=$callId")
        sendEventToFlutter("onCallBegin", mapOf(
            "callId" to callId,
            "mediaType" to mediaType.value.toString()
        ))
    }

    override fun onCallEnd(
        callId: String,
        mediaType: TUICallDefine.MediaType,
        reason: TUICallDefine.CallEndReason,
        userId: String,
        totalTime: Long,
        extraInfo: TUICallDefine.CallObserverExtraInfo
    ) {
        Log.d("CallStateTracker", "onCallEnd callId=$callId reason=$reason(${reason.value})")
        currentCallId = null
        callState = "idle"
        sendEventToFlutter("onCallEnd", mapOf(
            "callId" to callId,
            "reason" to reason.value.toString(),
            "reasonName" to reason.name,
            "userId" to userId,
            "totalTime" to totalTime.toString()
        ))
    }

    override fun onCallNotConnected(
        callId: String,
        mediaType: TUICallDefine.MediaType,
        reason: TUICallDefine.CallEndReason,
        userId: String,
        extraInfo: TUICallDefine.CallObserverExtraInfo
    ) {
        Log.d("CallStateTracker", "onCallNotConnected callId=$callId reason=$reason(${reason.value})")
        currentCallId = null
        callState = "idle"
        sendEventToFlutter("onCallNotConnected", mapOf(
            "callId" to callId,
            "reason" to reason.value.toString(),
            "reasonName" to reason.name,
            "userId" to userId
        ))
    }

    override fun onCallCancelled(callId: String) {
        Log.d("CallStateTracker", "onCallCancelled callId=$callId")
        currentCallId = null
        callState = "idle"
        sendEventToFlutter("onCallCancelled", mapOf("callId" to callId))
    }

    fun register(context: android.content.Context) {
        if (registered) return
        try {
            val engine = TUICallEngine.createInstance(context.applicationContext)
            engine.addObserver(this)
            registered = true
            Log.d("CallStateTracker", "Native TUICallObserver registered on engine=$engine")
        } catch (e: Exception) {
            Log.e("CallStateTracker", "Failed to register native observer", e)
        }
    }
}

class MainApplication : BmfMapApplication() {

    private val TAG = "MainApplication"

    // ========== TIMPush state ==========
    private var hadLaunchedMainActivity = false
    private var appInForeground = false
    private var activityReferences = 0
    private var isActivityChangingConfigurations = false

    private val timPushListener = object : TIMPushListener() {
        override fun onRecvPushMessage(msg: TIMPushMessage) {
            Log.d(TAG, "onRecvPushMessage: ${msg.toString()}")
            TencentCloudChatPushPlugin.instance?.toFlutterMethodByJson(
                "onRecvPushMessage",
                Utils.convertTIMPushMessageToMap(msg)
            )
        }

        override fun onRevokePushMessage(msgID: String) {
            Log.d(TAG, "onRevokePushMessage: $msgID")
            TencentCloudChatPushPlugin.instance?.toFlutterMethodByString(
                "onRevokePushMessage",
                msgID
            )
        }

        override fun onNotificationClicked(ext: String) {
            Log.d(TAG, "onNotificationClicked: $ext")
            notifyNotificationClicked(ext)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "onCreate — application starting")

        if (isMainProcess()) {
            initTIMPushHooksSafe()
            CallStateTracker.register(this)
        }
    }

    // ===== TIMPush initialization (mirrors TencentCloudChatPushApplication) =====

    /** Safe wrapper: catches any exception to prevent ANR on cold start. */
    private fun initTIMPushHooksSafe() {
        try {
            initTIMPushHooks()
            Log.d(TAG, "initTIMPushHooks completed successfully")
        } catch (e: Throwable) {
            Log.e(TAG, "initTIMPushHooks failed — app will continue without push hooks", e)
        }
    }

    private fun initTIMPushHooks() {
        val start = System.currentTimeMillis()
        // Keep a single registration path: disable SDK auto register and
        // register manually after IM login in Flutter.
        TUICore.callService(
            TUIConstants.TIMPush.SERVICE_NAME,
            TUIConstants.TIMPush.METHOD_DISABLE_AUTO_REGISTER_PUSH,
            null
        )

        Log.d(TAG, "[TIMPush] step 1: register notification-click event")
        // 1. Register notification-click event to TUICore (handles cold-start clicks).
        registerOnNotificationClickedEvent()
        Log.d(TAG, "[TIMPush] step 1 done in ${System.currentTimeMillis() - start}ms")

        Log.d(TAG, "[TIMPush] step 2: register app-wake-up event")
        // 2. Register app-wake-up event (FCM data channel on Android).
        registerOnAppWakeUp()
        Log.d(TAG, "[TIMPush] step 2 done in ${System.currentTimeMillis() - start}ms")

        Log.d(TAG, "[TIMPush] step 3: register activity lifecycle callbacks")
        // 3. Track foreground / background state for push logic.
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {
                if (++activityReferences == 1 && !isActivityChangingConfigurations) {
                    appInForeground = true
                    Log.d(TAG, "appInForeground = true")
                }
            }
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {
                isActivityChangingConfigurations = activity.isChangingConfigurations
                if (--activityReferences == 0 && !isActivityChangingConfigurations) {
                    appInForeground = false
                    Log.d(TAG, "appInForeground = false")
                }
            }
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })

        Log.d(TAG, "[TIMPush] step 4: add TIMPush listener")
        // 4. Add TIMPush listener for receiving push messages.
        TIMPushManager.getInstance().addPushListener(timPushListener)
        Log.d(TAG, "[TIMPush] all steps done in ${System.currentTimeMillis() - start}ms")
    }

    /**
     * Called from Flutter to register Honor push after IM login.
     * TIMPush SDK only auto-registers Huawei+FCM, so Honor needs manual trigger.
     */
    fun registerHonorPush() {
        Log.d(TAG, "registerHonorPush: triggering TIMHonorPushPlugin")
        TUICore.callService(
            "TIMHonorPushPlugin",
            "registerTIMHonorPush",
            null
        )
    }

    private fun isMainProcess(): Boolean {
        val mainProcessName = packageName
        val currentProcessName = getCurrentProcessName()
        return TextUtils.equals(mainProcessName, currentProcessName)
    }

    private fun getCurrentProcessName(): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return Application.getProcessName()
        }
        return try {
            val method = Class.forName(
                "android.app.ActivityThread",
                false,
                Application::class.java.classLoader
            ).getDeclaredMethod("currentProcessName", *arrayOfNulls(0))
            method.isAccessible = true
            method.invoke(null, *arrayOfNulls(0)) as String
        } catch (e: Throwable) {
            packageName
        }
    }

    // ===== Notification-click routing (cold-start support) =====

    private fun registerOnNotificationClickedEvent() {
        TUICore.registerEvent(
            TUIConstants.TIMPush.EVENT_NOTIFY,
            TUIConstants.TIMPush.EVENT_NOTIFY_NOTIFICATION
        ) { key, subKey, param ->
            Log.d(TAG, "onNotifyEvent: key=$key, subKey=$subKey")
            if (TencentCloudChatPushPlugin.instance != null &&
                TencentCloudChatPushPlugin.instance!!.attachedToEngine
            ) {
                // Flutter engine already running — notify directly.
                notifyNotificationClickedEvent(key, subKey, param)
            } else {
                // Cold-start: launch MainActivity then notify.
                launchMainActivity()
                Handler(Looper.getMainLooper()).postDelayed({
                    notifyNotificationClickedEvent(key, subKey, param)
                }, 500)
            }
        }
    }

    private fun notifyNotificationClickedEvent(
        key: String,
        subKey: String,
        param: Map<String, Any>?
    ) {
        if (TUIConstants.TIMPush.EVENT_NOTIFY == key &&
            TUIConstants.TIMPush.EVENT_NOTIFY_NOTIFICATION == subKey
        ) {
            val extString = param?.get(TUIConstants.TUIOfflinePush.NOTIFICATION_EXT_KEY) as? String
            Log.d(TAG, "notifyNotificationClicked: ext=$extString")
            scheduleCheckPluginAndNotify(Extras.ON_NOTIFICATION_CLICKED, extString ?: "")
        }
    }

    private fun notifyNotificationClicked(ext: String) {
        if (TencentCloudChatPushPlugin.instance != null &&
            TencentCloudChatPushPlugin.instance!!.attachedToEngine
        ) {
            TencentCloudChatPushPlugin.instance!!.toFlutterMethod(
                Extras.ON_NOTIFICATION_CLICKED,
                ext
            )
        } else {
            // Cold-start: launch app and wait for plugin to attach.
            launchMainActivity()
            scheduleCheckPluginAndNotify(Extras.ON_NOTIFICATION_CLICKED, ext)
        }
    }

    // ===== App wake-up (FCM data channel) =====

    private fun registerOnAppWakeUp() {
        TUICore.registerEvent(
            TUIConstants.TIMPush.EVENT_IM_LOGIN_AFTER_APP_WAKEUP_KEY,
            TUIConstants.TIMPush.EVENT_IM_LOGIN_AFTER_APP_WAKEUP_SUB_KEY
        ) { key, subKey, _ ->
            Log.d(TAG, "onAppWakeUp: key=$key, subKey=$subKey")
            if (TUIConstants.TIMPush.EVENT_IM_LOGIN_AFTER_APP_WAKEUP_KEY == key &&
                TUIConstants.TIMPush.EVENT_IM_LOGIN_AFTER_APP_WAKEUP_SUB_KEY == subKey
            ) {
                generateFlutterEngine()
                scheduleCheckPluginAndNotify(Extras.ON_APP_WAKE_UP, "")
            }
        }
    }

    private fun generateFlutterEngine() {
        if (FlutterEngineCache.getInstance().contains(Extras.FLUTTER_ENGINE) ||
            hadLaunchedMainActivity
        ) {
            return
        }
        Handler(Looper.getMainLooper()).post {
            val engine = FlutterEngine(this)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            FlutterEngineCache.getInstance().put(Extras.FLUTTER_ENGINE, engine)
        }
    }

    private fun launchMainActivity() {
        if (TencentCloudChatPushPlugin.instance != null &&
            TencentCloudChatPushPlugin.instance!!.attachedToEngine
        ) {
            return
        }
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        if (intent != null) {
            intent.putExtra(Extras.SHOW_IN_FOREGROUND, true)
            intent.addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
            startActivity(intent)
        } else {
            Log.e(TAG, "Failed to get launch intent for $packageName")
        }
    }

    // ===== Retry loop: wait for Flutter plugin to be ready =====

    private fun scheduleCheckPluginAndNotify(action: String, data: String) {
        Handler(Looper.getMainLooper()).post {
            var attempts = 0
            val maxAttempts = 60 // up to 30 seconds
            val handler = Handler(Looper.getMainLooper())
            object : Runnable {
                override fun run() {
                    attempts++
                    val plugin = TencentCloudChatPushPlugin.instance
                    if (plugin != null && plugin.attachedToEngine) {
                        plugin.tryNotifyDartEvent(action, data)
                    } else if (attempts < maxAttempts) {
                        handler.postDelayed(this, 500)
                    } else {
                        Log.e(TAG, "Timed out waiting for Flutter plugin for action=$action")
                    }
                }
            }.also { handler.postDelayed(it, 100) }
        }
    }
}
