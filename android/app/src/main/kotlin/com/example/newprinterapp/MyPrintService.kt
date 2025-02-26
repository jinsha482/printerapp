package com.example.newprinterapp

import android.print.PrintJobInfo
import android.print.PrinterId
import android.print.PrinterInfo
import android.printservice.PrintJob
import android.printservice.PrintService
import android.printservice.PrinterDiscoverySession
import android.util.Log
class MyPrintService : PrintService() {

  override fun onCreate() {
    super.onCreate()
    Log.d("PrintService", "🚀 Print Service Created!")
  }

  override fun onDestroy() {
    super.onDestroy()
    Log.d("PrintService", "🔥 Print Service Destroyed!")
  }

  override fun onCreatePrinterDiscoverySession(): PrinterDiscoverySession {
    Log.d("PrintService", "🔎 onCreatePrinterDiscoverySession Called!")
    return object : PrinterDiscoverySession() {
      override fun onStartPrinterDiscovery(printerIds: MutableList<PrinterId>) {
        Log.d("PrintService", "📡 Starting printer discovery...")

        val printerId = generatePrinterId("FlutterPrintService")
        val printerInfo = PrinterInfo.Builder(
          printerId,
          "Flutter Virtual Printer",
          PrinterInfo.STATUS_IDLE
        ).build()

        addPrinters(listOf(printerInfo))
        Log.d("PrintService", "🖨️ Printer added: ${printerInfo.name}")
      }

      override fun onStopPrinterDiscovery() {
        Log.d("PrintService", "❌ Stopping printer discovery...")
      }

      override fun onValidatePrinters(printers: MutableList<PrinterId>) {}

      override fun onStartPrinterStateTracking(printerId: PrinterId) {}

      override fun onStopPrinterStateTracking(printerId: PrinterId) {}

      override fun onDestroy() {
        Log.d("PrintService", "🔥 Print Service Destroyed!")
      }
    }
  }

  override fun onPrintJobQueued(printJob: PrintJob) {
    Log.d("PrintService", "📄 Print job received: ${printJob.info.label}")

    val jobInfo: PrintJobInfo = printJob.info
    if (jobInfo.state == PrintJobInfo.STATE_QUEUED) {
      Log.d("PrintService", "🖨️ Processing print job: ${jobInfo.label}")

      // Simulate print processing delay
      Thread.sleep(2000)

      if (printJob.isCancelled) {
        Log.e("PrintService", "🚫 Print job was cancelled before completion.")
      } else {
        Log.d("PrintService", "✅ Print job processing complete.")
        if (!printJob.isCompleted) {
          try {
            printJob.complete()
            Log.d("PrintService", "🎉 Print job completed successfully.")
          } catch (e: Exception) {
            Log.e("PrintService", "❌ Error completing print job: ${e.message}")
          }
        }
      }
    } else {
      Log.e("PrintService", "⚠️ Invalid print job state: ${jobInfo.state}")
    }
  }

  override fun onRequestCancelPrintJob(printJob: PrintJob) {
    Log.d("PrintService", "🚫 Canceling print job: ${printJob.info.label}")
    printJob.cancel()
  }
}
