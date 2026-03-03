package com.pokermanagement.service

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

class SpeechInputService(private val context: Context) {

    private val _transcribedText = MutableStateFlow("")
    val transcribedText: StateFlow<String> = _transcribedText

    private val _parsedPotSize = MutableStateFlow<Double?>(null)
    val parsedPotSize: StateFlow<Double?> = _parsedPotSize

    private val _parsedBetSize = MutableStateFlow<Double?>(null)
    val parsedBetSize: StateFlow<Double?> = _parsedBetSize

    private val _isListening = MutableStateFlow(false)
    val isListening: StateFlow<Boolean> = _isListening

    private var recognizer: SpeechRecognizer? = null

    fun startListening() {
        if (_isListening.value) return

        recognizer = SpeechRecognizer.createSpeechRecognizer(context).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    _isListening.value = true
                }
                override fun onResults(results: Bundle?) {
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull() ?: ""
                    _transcribedText.value = text
                    parseAmounts(text)
                    _isListening.value = false
                }
                override fun onError(error: Int) { _isListening.value = false }
                override fun onEndOfSpeech() {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 500L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 1500L)
            putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 1000L)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }

        recognizer?.startListening(intent)
    }

    fun stopListening() {
        recognizer?.stopListening()
        recognizer?.destroy()
        recognizer = null
        _isListening.value = false
    }

    private fun parseAmounts(text: String) {
        val lower = text.lowercase()

        // Pot size keywords
        val potKeywords = listOf("pot is", "pot's", "the pot")
        for (keyword in potKeywords) {
            if (lower.contains(keyword)) {
                val after = lower.substringAfter(keyword).trim()
                val amount = wordToNumber(after)
                if (amount != null) {
                    _parsedPotSize.value = amount
                    return
                }
            }
        }

        // Bet / facing keywords
        val betKeywords = listOf("bet is", "facing", "bet of", "raise to", "raise is")
        for (keyword in betKeywords) {
            if (lower.contains(keyword)) {
                val after = lower.substringAfter(keyword).trim()
                val amount = wordToNumber(after)
                if (amount != null) {
                    _parsedBetSize.value = amount
                    return
                }
            }
        }

        // Fallback: try to parse any numeric words in the utterance
        val amount = wordToNumber(lower)
        if (amount != null) {
            _parsedPotSize.value = amount
        }
    }

    private fun wordToNumber(text: String): Double? {
        // First try direct numeric parse
        val trimmed = text.trim().split(" ").firstOrNull() ?: return null
        trimmed.toDoubleOrNull()?.let { return it }

        val ones = mapOf(
            "zero" to 0, "one" to 1, "two" to 2, "three" to 3, "four" to 4,
            "five" to 5, "six" to 6, "seven" to 7, "eight" to 8, "nine" to 9,
            "ten" to 10, "eleven" to 11, "twelve" to 12, "thirteen" to 13,
            "fourteen" to 14, "fifteen" to 15, "sixteen" to 16, "seventeen" to 17,
            "eighteen" to 18, "nineteen" to 19
        )
        val tens = mapOf(
            "twenty" to 20, "thirty" to 30, "forty" to 40, "fifty" to 50,
            "sixty" to 60, "seventy" to 70, "eighty" to 80, "ninety" to 90
        )

        val words = text.trim().lowercase().split(Regex("\\s+|-"))
        var total = 0.0
        var current = 0.0

        for (word in words) {
            ones[word]?.let { current += it; return@let }
            tens[word]?.let { current += it; return@let }
            when (word) {
                "hundred" -> current *= 100
                "thousand" -> { total += current * 1000; current = 0.0 }
                "k" -> { total += current * 1000; current = 0.0 }
            }
        }
        total += current
        return if (total > 0) total else null
    }
}
