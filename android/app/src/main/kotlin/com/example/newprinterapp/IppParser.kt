package com.example.newprinterapp
import android.util.Log
import de.gmuth.ipp.core.IppInputStream
import de.gmuth.ipp.core.IppRequest
import de.gmuth.ipp.core.IppTag
import java.io.BufferedInputStream
import java.io.ByteArrayInputStream

class IppParser {
  fun parseIppRequest(ippData: ByteArray): ByteArray? {
    Log.d("IppParser", "parseIppRequest called")

    try {
      val inputStream = ByteArrayInputStream(ippData)
      val bufferedInputStream = BufferedInputStream(inputStream)
      val ippInputStream = IppInputStream(bufferedInputStream)
      val ippRequest = IppRequest() // Creates an instance of IppRequest
      ippRequest.read(ippInputStream) // Call read on the instance

      // Search for the document-data attribute, which should be of type IppTag.DATA.
      val documentDataAttribute = ippRequest.getSingleAttributesGroup(IppTag.Document)

      if (documentDataAttribute != null) {
        val pdfData = documentDataAttribute.tag as ByteArray
        return pdfData
      } else {
        return null
      }
    } catch (e: Exception) {
      e.printStackTrace()
      return null
    }
  }
}
