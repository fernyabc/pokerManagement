package com.pokermanagement.data.network

import okhttp3.OkHttpClient
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import java.util.concurrent.TimeUnit

object ApiClient {
    private var baseUrl: String = "http://10.0.2.2:8000/"
    private var apiKey: String = "dev-token"

    private var retrofit: Retrofit? = null
    private var apiService: ApiService? = null

    fun configure(url: String, key: String) {
        if (url != baseUrl || key != apiKey) {
            baseUrl = url.trimEnd('/') + "/"
            apiKey = key
            retrofit = null
            apiService = null
        }
    }

    private fun buildRetrofit(): Retrofit {
        val logging = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }

        val client = OkHttpClient.Builder()
            .addInterceptor { chain ->
                val request = chain.request().newBuilder()
                    .addHeader("Authorization", "Bearer $apiKey")
                    .addHeader("Content-Type", "application/json")
                    .build()
                chain.proceed(request)
            }
            .addInterceptor(logging)
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .build()

        return Retrofit.Builder()
            .baseUrl(baseUrl)
            .client(client)
            .addConverterFactory(GsonConverterFactory.create())
            .build()
    }

    fun getService(): ApiService {
        return apiService ?: run {
            val r = retrofit ?: buildRetrofit().also { retrofit = it }
            r.create(ApiService::class.java).also { apiService = it }
        }
    }

    fun buildWebSocketClient(): okhttp3.OkHttpClient {
        return OkHttpClient.Builder()
            .connectTimeout(30, TimeUnit.SECONDS)
            .readTimeout(0, TimeUnit.SECONDS) // no timeout for WS
            .build()
    }
}
