import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';

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
  Uint8List? _pdfData;
  static HttpServer? _server;
  final Box _serviceBox = Hive.box('serviceBox');
  final Connectivity _connectivity = Connectivity();
  static const platform = MethodChannel('ipp_parser');
  @override
  void initState() {
    super.initState();
    bool wasRunning = _serviceBox.get('isServiceRunning', defaultValue: false);
    if (wasRunning) startBonjourService();
    startHttpServer();

    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      if (result == ConnectivityResult.wifi) {
        print("📡 Wi-Fi Reconnected! Restarting Print Service...");
        if (!_isServiceRunning) {
          startBonjourService();
        }
      }
    });
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
      print("✅ Bonjour service started");
    } catch (error) {
      print("❌ Failed to start Bonjour service: $error");
    }
  }

  Future<void> stopBonjourService() async {
    await _bonsoirBroadcast?.stop();
    _bonsoirBroadcast = null;
    setState(() => _isServiceRunning = false);
    _serviceBox.put('isServiceRunning', false);
    print("🛑 Bonjour service stopped");
  }

  Future<void> startHttpServer() async {
    await _server?.close();
    _server = null;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
      print("🖨️ HTTP Server Running on Port 8080");

      await for (HttpRequest request in _server!) {
        if (request.method == 'POST') {
          Uint8List ippData = await receivePdfData(request);
          try {
            Uint8List? pdfData =
                await platform.invokeMethod('parseIpp', {'ippData': ippData});

            if (pdfData != null) {
              print("📄 PDF Data Length: ${pdfData.length} bytes");
              setState(() => _pdfData = pdfData);
              handlePrint();
            } else {
              print("❌ PDF data not found in IPP request");
              request.response
                ..statusCode = HttpStatus.badRequest
                ..write('❌ PDF data not found in IPP request')
                ..close();
            }
          } catch (error) {
            print(ippData);
            print("❌ Error parsing IPP request: $error");
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write('❌ Invalid IPP Request!')
              ..close();
          }
        } else {
          // ... (Your existing code) ...
        }
      }
    } catch (e) {
      print("❌ Error starting HTTP server: $e");
    }
  }

  Future<Uint8List> receivePdfData(HttpRequest request) async {
    List<int> receivedData = [];
    await for (var data in request) {
      receivedData.addAll(data);
    }
    return Uint8List.fromList(receivedData);
  }

  void handlePrint() {
    if (_pdfData != null && _pdfData!.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PdfViewerScreen(pdfBytes: _pdfData!),
        ),
      );
    } else {
      print("⚠️ No PDF Available to Print!");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ PDF not found!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Flutter Print Service')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isServiceRunning
                  ? "📡 Print Service Running"
                  : "❌ Print Service Stopped",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed:
                  _isServiceRunning ? stopBonjourService : startBonjourService,
              child: Text(_isServiceRunning ? "Stop Service" : "Start Service"),
            ),
          ],
        ),
      ),
    );
  }
}

class PdfViewerScreen extends StatelessWidget {
  final Uint8List pdfBytes;

  const PdfViewerScreen({super.key, required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    if (pdfBytes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text('PDF Viewer')),
        body: Center(child: Text("❌ PDF data is empty!")),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('PDF Viewer')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "PDF Loaded Successfully!",
              style: TextStyle(fontSize: 16, color: Colors.blue),
            ),
            SizedBox(height: 20),
            Expanded(
              child: PDFView(
                pdfData: pdfBytes,
                enableSwipe: true,
                swipeHorizontal: true,
                autoSpacing: true,
                pageFling: true,
                pageSnap: true,
                onPageChanged: (int? current, int? total) {
                  print("Current page: $current / Total pages: $total");
                },
                onViewCreated: (PDFViewController pdfViewController) {
                  print("PDFView created");
                },
                onError: (error) {
                  print("❌ PDFView Error: $error");
                },
                onPageError: (page, error) {
                  print("❌ Error on page $page: $error");
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
