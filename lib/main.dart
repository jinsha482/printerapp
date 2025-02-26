import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('serviceBox');
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Print Service',
      theme: ThemeData(primarySwatch: Colors.blue),
      debugShowCheckedModeBanner: false,
      home: PrintServiceScreen(),
    );
  }
}

class PrintServiceScreen extends StatefulWidget {
  @override
  _PrintServiceScreenState createState() => _PrintServiceScreenState();
}

class _PrintServiceScreenState extends State<PrintServiceScreen> {
  static BonsoirBroadcast? _bonsoirBroadcast; // Singleton instance
  bool _isServiceRunning = false;
  String? _pdfPath;
  static HttpServer? _server;
  final Box _serviceBox = Hive.box('serviceBox');
  final Connectivity _connectivity = Connectivity();

  @override
  void initState() {
    super.initState();
    bool wasRunning = _serviceBox.get('isServiceRunning', defaultValue: false);

    if (!_isServiceRunning && wasRunning) {
      startBonjourService();
    }
    startHttpServer();

    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      if (result == ConnectivityResult.wifi) {
        print("📡 Wi-Fi Reconnected! Restarting Print Service...");
        restartBonjourService();
      }
    });
  }

  Future<void> startBonjourService() async {
    if (_isServiceRunning || (_serviceBox.get('isServiceRunning') ?? false)) {
      print("⚠️ Print service already running. Skipping start.");
      return;
    }

    await stopBonjourService(); // Ensure no duplicate service

    _bonsoirBroadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: 'FlutterPrintService',
        type: '_ipp._tcp',
        port: 8080,
        attributes: {
          "rp": "/print",
          "pdl": "application/pdf",
          "txtvers": "1",
          "adminurl": "http://localhost:8080",
          "ty": "Flutter Print Service",
          "UUID": "12345678-1234-5678-1234-567812345678",
          "printer-state": "3", // Indicates it's ready
          "printer-type": "0x8090", // Standard IPP printer type
          "urf": "W8,SRGB24,CP1,IS1-2-3-4-5-6-7-8-9-10",
          "TLS": "1.2",
          "note": "Flutter IPP Print Service",
          "printer-make-and-model": "Flutter Virtual Printer",
          "color-supported": "T",
          "compression-supported": "none",
          "copies-supported": "1",
          "document-format-supported": "application/pdf",
        },
      ),
    );

    try {
      await _bonsoirBroadcast!.ready;
      await _bonsoirBroadcast!.start();
      setState(() {
        _isServiceRunning = true;
      });
      _serviceBox.put('isServiceRunning', true); // Store state in Hive
      print("✅ Bonjour service started");
    } catch (error) {
      print("❌ Failed to start Bonjour service: $error");
    }
  }

  Future<void> stopBonjourService() async {
    if (_bonsoirBroadcast != null) {
      await _bonsoirBroadcast!.stop();
      _bonsoirBroadcast = null;
      setState(() {
        _isServiceRunning = false;
      });
      _serviceBox.put('isServiceRunning', false);
      print("🛑 Bonjour service stopped");
    }
  }

  Future<void> restartBonjourService() async {
    await stopBonjourService();
    await startBonjourService();
  }

  Future<void> startHttpServer() async {
  if (_server != null) {
    print("⚠️ HTTP server is already running.");
    return;
  }

  try {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    print("🖨️ HTTP Server Running on Port 8080");

    await for (HttpRequest request in _server!) {
      if (request.method == 'POST') {
        print("📥 PDF file received!");

        final contentType = request.headers.contentType?.mimeType;
        if (contentType != "application/pdf") {
          request.response
            ..statusCode = HttpStatus.unsupportedMediaType
            ..write('❌ Unsupported file format. Only PDFs are allowed.')
            ..close();
          return;
        }

        final filePath = await saveReceivedFile(request);
        setState(() {
          _pdfPath = filePath;
        });

        // Open PDF Viewer Automatically
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PdfViewerScreen(pdfPath: filePath),
            ),
          );
        }

        request.response
          ..statusCode = HttpStatus.ok
          ..write('✅ PDF received!')
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..write('❌ Invalid Request!')
          ..close();
      }
    }
  } catch (e) {
    print("❌ Error starting HTTP server: $e");
  }
}


  

  Future<String> saveReceivedFile(HttpRequest request) async {
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/received_document.pdf');
    final sink = file.openWrite();
    await request.listen((List<int> data) {
      sink.add(data);
    }).asFuture();
    await sink.close();
    print("✅ PDF saved at: ${file.path}");
    return file.path;
  }

  @override
  void dispose() {
    stopBonjourService();
    _server?.close();
    super.dispose();
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
              _isServiceRunning ? "🖨️ Service Running ✅" : "❌ Service Stopped",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isServiceRunning ? null : startBonjourService,
              child: Text("Start Print Service"),
            ),
          ],
        ),
      ),
    );
  }
}

class PdfViewerScreen extends StatelessWidget {
  final String pdfPath;
  const PdfViewerScreen({Key? key, required this.pdfPath}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('PDF Viewer')),
      body: PDFView(filePath: pdfPath),
    );
  }
}
