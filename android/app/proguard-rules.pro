# Gson (required by Baidu Search SDK's GsonFactory)
-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }
-keep class com.google.gson.stream.** { *; }
-dontwarn com.google.gson.**

# Baidu Map SDK - comprehensive rules for all components
-keep class com.baidu.** { *; }
-keep interface com.baidu.** { *; }
-dontwarn com.baidu.**
-keepattributes Exceptions,InnerClasses,Signature,Deprecated,SourceFile,LineNumberTable,LocalVariable*Table,*Annotation*,Synthetic,EnclosingMethod

# Keep specific Baidu search SDK classes used by Flutter plugin
-keep class com.baidu.platform.comapi.map.** { *; }
-keep class com.baidu.mapapi.search.** { *; }
-keep class com.baidu.mapapi.search.geocode.** { *; }
-keep class com.baidu.mapapi.search.core.** { *; }
-keep class com.baidu.mapapi.search.route.** { *; }
-keep class com.baidu.mapapi.search.sug.** { *; }
-keep class com.baidu.mapapi.search.poi.** { *; }
-keep class com.baidu.mapapi.search.district.** { *; }
-keep class com.baidu.mapapi.search.share.** { *; }
-keep class com.baidu.mapapi.search.cloud.** { *; }
-keep class com.baidu.mapapi.search.busline.** { *; }

# Keep Baidu location SDK classes
-keep class com.baidu.location.** { *; }
-keep class com.baidu.locsdk.** { *; }

# Keep Flutter Baidu Map plugin classes
-keep class com.baidu.flutter.** { *; }
-dontwarn com.baidu.flutter.**

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Tencent IM / TIMPush
-keep class com.tencent.** { *; }
-dontwarn com.tencent.**
