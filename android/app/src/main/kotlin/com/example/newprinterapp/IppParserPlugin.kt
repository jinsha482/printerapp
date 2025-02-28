package com.example.newprinterapp

import android.util.Log // Import the Log class
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class IppParserPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private val ippParser = IppParser() // Create an instance of IppParser

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ipp_parser")
    channel.setMethodCallHandler(this)
    Log.d("IppParserPlugin", "onAttachedToEngine called")
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    Log.d("IppParserPlugin", "onMethodCall called: ${call.method}")
    if (call.method == "parseIpp") {
      val ippData = call.argument<ByteArray>("ippData")
      Log.d("IppParserPlugin", "parseIpp method called")
      if (ippData != null) {
        val pdfData = ippParser.parseIppRequest(ippData) // Use the instance
        result.success(pdfData)

      } else {
        result.error("IPP_DATA_NULL", "ippData argument is null.", null)
      }
    } else {
      result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
