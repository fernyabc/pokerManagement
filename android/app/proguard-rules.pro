# TensorFlow Lite
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }

# WebRTC
-keep class org.webrtc.** { *; }
-keep class io.getstream.** { *; }

# Retrofit / OkHttp / Gson
-keep class com.squareup.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep class com.pokermanagement.data.models.** { *; }
-keep class com.pokermanagement.data.network.** { *; }

# Room
-keep class * extends androidx.room.RoomDatabase
-keep @androidx.room.Entity class *

# DataStore
-keep class androidx.datastore.** { *; }
