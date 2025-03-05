
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:path_provider/path_provider.dart';


const int IPP_TAG_END_OF_ATTRIBUTES = 0x03;
const int IPP_OPERATION_PRINT_JOB = 0x0002;
const int IPP_OPERATION_GET_PRINTER_ATTRIBUTES = 0x000B;

// IPP Response Tags
class IppTag {
  static const OPERATION_ATTRIBUTES_TAG = 0x01;
  static const PRINTER_ATTRIBUTES_TAG = 0x04;
  static const END_OF_ATTRIBUTES = 0x03;
}

Uint8List uint16Bytes(int value) =>
    Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.big);
Uint8List uint32Bytes(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('serviceBox');
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Print Service',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: Focus(
        autofocus: true,
        child: RawKeyboardListener(
          focusNode: _focusNode,
          onKey: (RawKeyEvent event) {
            if (event is RawKeyDownEvent) {
              print("🔑 Key Pressed: ${event.logicalKey}");

              bool isMac = Platform.isMacOS;
              bool isWindows = Platform.isWindows || Platform.isLinux;
              bool isMetaPressed = isMac && event.isMetaPressed;
              bool isCtrlPressed = isWindows && event.isControlPressed;
              bool isPKey = event.logicalKey == LogicalKeyboardKey.keyP;

              if ((isMac && isMetaPressed && isPKey) ||
                  (isWindows && isCtrlPressed && isPKey)) {
                print("🖨️ Print Triggered!");
                _triggerPrint(context);
              }
            }
          },
          child: PrintServiceScreen(),
        ),
      ),
    );
  }

  void _triggerPrint(BuildContext context) {
    print("📢 Print function called!");
    PrintServiceScreen.handlePrint(context);
  }
}

class PrintServiceScreen extends StatefulWidget {
  @override
  _PrintServiceScreenState createState() => _PrintServiceScreenState();

  static void handlePrint(BuildContext context) {
    final state = context.findAncestorStateOfType<_PrintServiceScreenState>();
    if (state != null) {
      state.handlePrint();
    } else {
      print("⚠️ Could not find PrintServiceScreen state!");
    }
  }
}

class _PrintServiceScreenState extends State<PrintServiceScreen> {
  static BonsoirBroadcast? _bonsoirBroadcast;
  bool _isServiceRunning = false;
  bool _hasDisplayedJob = false;

  String? _pdfPath;
  bool _isPdfLoaded = false;
  static HttpServer? _server;
  final Box _serviceBox = Hive.box('serviceBox');
  final Connectivity _connectivity = Connectivity();

  @override
  void initState() {
    super.initState();
    bool wasRunning = _serviceBox.get('isServiceRunning', defaultValue: false);
    if (wasRunning) startBonjourService();
    _startHttpServer();

    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      if (result == ConnectivityResult.wifi && !_isServiceRunning) {
        startBonjourService();
      }
    });
  }

  @override
  void dispose() {
    _server?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Print Service")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isServiceRunning ? "Service is Running" : "Service is Stopped",
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                if (_isServiceRunning) {
                  stopBonjourService();
                } else {
                  startBonjourService();
                }
              },
              child: Text(_isServiceRunning ? "Stop Service" : "Start Service"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> startBonjourService() async {
    if (_isServiceRunning) return;
    await stopBonjourService();

    _bonsoirBroadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: 'FlutterPrintService',
        type: '_ipp._tcp',
        port: 8080,
      ),
    );

    try {
      await _bonsoirBroadcast!.ready;
      await _bonsoirBroadcast!.start();
      setState(() => _isServiceRunning = true);
      _serviceBox.put('isServiceRunning', true);
      print("🔔 Bonjour service started and printer attributes ready.");
    } catch (error) {
      print("❌ Failed to start Bonjour service: $error");
    }
  }

  Future<void> stopBonjourService() async {
    await _bonsoirBroadcast?.stop();
    _bonsoirBroadcast = null;
    setState(() => _isServiceRunning = false);
    _serviceBox.put('isServiceRunning', false);
    print("🔕 Bonjour service stopped.");
  }

  // HTTP server: listens for incoming IPP requests
  Future<void> _startHttpServer() async {
    await _server?.close();
    _server = null;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      print("Server running on port 8080");
      // The server enters an infinite loop to process incoming IPP requests.
      await for (HttpRequest request in _server!) {
        try {
          final data = await _readFullRequest(request);
          // Process the IPP request and obtain response bytes.
          final responseBytes =
              await _processIppRequest(data, request.response);
          print(responseBytes.toString());

          if (responseBytes != null) {
            request.response
              ..headers.contentType = ContentType("application", "ipp")
              ..statusCode = HttpStatus.ok
              ..add(responseBytes);

            print('✅ Response sent.');
          }
        } catch (e) {
          print("Request error: $e");
          request.response.statusCode = HttpStatus.internalServerError;
        } finally {
          await request.response.close(); // Ensure response is closed.
          print("Waiting for next IPP request...");
        }
      }
    } catch (e) {
      print("💥 Server error: $e");
    }
  }

  Future<Uint8List> _readFullRequest(HttpRequest request) async {
    return await request
        .fold<BytesBuilder>(
          BytesBuilder(),
          (bb, data) => bb..add(data),
        )
        .then((bb) => bb.takeBytes());
  }

  Future<Uint8List?> _processIppRequest(
      Uint8List data, HttpResponse response) async {
    try {
      final parser = IppParser(data);
      print(
          "Processing IPP request. Operation ID: 0x${parser.operationId.toRadixString(16)}");
      response.headers.contentType = ContentType("application", "ipp");

      switch (parser.operationId) {
        // When a Get-Printer-Attributes request is received…
        case IPP_OPERATION_GET_PRINTER_ATTRIBUTES:
          // Build and send the printer attributes response.
          final resBytes = _handlePrinterAttributes(response);

          return resBytes;
        // When a Print-Job request is received…
        case IPP_OPERATION_PRINT_JOB:
          return await _handlePrintJob(parser, response);
        default:
          _sendIppError(response, 0x0501, "Unsupported operation");
          return null;
      }
    } catch (e) {
      _sendIppError(response, 0x0400, "Invalid request");
      return null;
    }
  }

  Uint8List _handlePrinterAttributes(HttpResponse response) {
    print('Entering _handlePrinterAttributes');
    try {
      final builder = IppResponseBuilder()
        ..setVersion(1, 1)
        ..setStatusCode(0x0000)
        ..setRequestId(1)
        ..addAttributeGroup(IppTag.OPERATION_ATTRIBUTES_TAG)
        ..addString('attributes-charset', 'utf-8')
        ..addString('attributes-natural-language', 'en-us')
        ..addAttributeGroup(IppTag.PRINTER_ATTRIBUTES_TAG)
        ..addString('printer-name', 'Flutter Printer')
        ..addStringList('document-format-supported', ['application/pdf'])
        ..addBoolean('printer-is-accepting-jobs', true);

      response.statusCode = HttpStatus.ok;
      final responseBytes = builder.build();
      print(
          "Printer attributes built. Response bytes length: ${responseBytes.length}");
      print(responseBytes.toString());
      return responseBytes;
    } catch (e) {
      print("Error in _handlePrinterAttributes: $e");
      return Uint8List(0);
    }
  }

  void _sendIppError(HttpResponse response, int code, String message) {
    final builder = IppResponseBuilder()
      ..setVersion(1, 1)
      ..setStatusCode(code)
      ..setRequestId(1)
      ..addAttributeGroup(IppTag.OPERATION_ATTRIBUTES_TAG)
      ..addString('status-message', message);

    response.statusCode = HttpStatus.ok;
    response.add(builder.build());
  }

  Future<Uint8List?> _handlePrintJob(
      IppParser parser, HttpResponse response) async {
    try {
      final pdfData = parser.getDocumentData();
      if (pdfData == null || !_validatePdf(pdfData)) {
        _sendIppError(response, 0x0400, "Invalid PDF data");
        return null;
      }

      await _savePdf(pdfData);
      _displayPdf(pdfData);

      final builder = IppResponseBuilder()
        ..setVersion(1, 1)
        ..setStatusCode(0x0000)
        ..setRequestId(1)
        ..addAttributeGroup(IppTag.OPERATION_ATTRIBUTES_TAG)
        ..addString('job-id', '1234')
        ..addString('job-uri', 'ipp://localhost:8080/jobs/1234');

      return builder.build();
    } catch (e) {
      _sendIppError(response, 0x0500, "Print job failed");
      return null;
    }
  }

  void _displayPdf(Uint8List pdfData) {
    // Navigate to PdfViewerScreen to show the PDF content.
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => PdfViewerScreen(pdfBytes: pdfData)));
  }

  bool _validatePdf(Uint8List data) =>
      data.length > 4 &&
      data[0] == 0x25 &&
      data[1] == 0x50 &&
      data[2] == 0x44 &&
      data[3] == 0x46;

  Future<void> _savePdf(Uint8List data) async {
    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/print_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(data);
    print("PDF saved to ${file.path}");
  }

  void handlePrint() {
    // Stub for any additional print-triggered actions.
    print("handlePrint called.");
  }
}

class PdfViewerScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  const PdfViewerScreen({super.key, required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('PDF Viewer')),
      body: PDFView(pdfData: pdfBytes),
    );
  }
}

class IppResponseBuilder {
  final BytesBuilder _buffer = BytesBuilder();
  int _currentGroup = 0x00;

  IppResponseBuilder setVersion(int major, int minor) {
    _buffer.addByte(major);
    _buffer.addByte(minor);
    return this;
  }

  IppResponseBuilder setStatusCode(int code) {
    _buffer.add(uint16Bytes(code));
    return this;
  }

  IppResponseBuilder setRequestId(int id) {
    _buffer.add(uint32Bytes(id));
    return this;
  }

  IppResponseBuilder addAttributeGroup(int tag) {
    _buffer.addByte(tag);
    _currentGroup = tag;
    return this;
  }

  IppResponseBuilder addString(String name, String value) {
    _addAttributeHeader(name, 0x47);
    _buffer.add(uint16Bytes(value.length));
    _buffer.add(value.codeUnits);
    return this;
  }

  IppResponseBuilder addStringList(String name, List<String> values) {
    for (final value in values) {
      _addAttributeHeader(name, 0x47);
      _buffer.add(uint16Bytes(value.length));
      _buffer.add(value.codeUnits);
    }
    return this;
  }

  IppResponseBuilder addBoolean(String name, bool value) {
    _addAttributeHeader(name, 0x22);
    _buffer.addByte(value ? 0x01 : 0x00);
    return this;
  }

  void _addAttributeHeader(String name, int tag) {
    _buffer.addByte(0x42); // Keyword tag for attribute name.
    _buffer.add(uint16Bytes(name.length));
    _buffer.add(name.codeUnits);
    _buffer.addByte(tag);
  }

  Uint8List build() {
    _buffer.addByte(IppTag.END_OF_ATTRIBUTES);
    return _buffer.toBytes();
  }
}

class IppParser {
  final ByteData _data;
  int _offset = 8;

  IppParser(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  int get operationId => _data.getUint16(2, Endian.big);

  Uint8List? getDocumentData() {
    while (_offset < _data.lengthInBytes) {
      final tag = _data.getUint8(_offset++);
      if (tag == IPP_TAG_END_OF_ATTRIBUTES) {
        // PDF data starts immediately after the end tag
        final pdfStart = _offset;
        final pdfLength = _data.lengthInBytes - pdfStart;
        if (pdfLength <= 0) return null;
        return _data.buffer.asUint8List(pdfStart, pdfLength);
      }

      // Skip attribute groups (printer, job, etc.)
      if (tag >= 0x01 && tag <= 0x04) continue;

      // Skip other attributes (name, value)
      final nameLength = _data.getUint16(_offset, Endian.big);
      _offset += 2 + nameLength; // Skip name length and name
      _offset += 1; // Skip value tag
      final valueLength = _data.getUint16(_offset, Endian.big);
      _offset += 2 + valueLength; // Skip value length and value
    }
    return null;
  }
}
