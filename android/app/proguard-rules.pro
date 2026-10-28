# Flutter ProGuard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Core / Deferred Components (referenced by Flutter engine)
-dontwarn com.google.android.play.core.**

# Firebase Rules
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable
-keep public class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Coroutines and serialization
-dontwarn kotlinx.coroutines.**
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Image & Scanner plugins
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
