import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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

  @override
  void initState() {
    super.initState();
    bool wasRunning = _serviceBox.get('isServiceRunning', defaultValue: false);
    if (wasRunning) startBonjourService();
    startHttpServer();

    _connectivity.onConnectivityChanged.listen((ConnectivityResult result) {
      if (result == ConnectivityResult.wifi) {
        if (!_isServiceRunning) {
          startBonjourService();
        }
      }
    });
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
    } catch (error) {
      print("❌ Failed to start Bonjour service: $error");
    }
  }

  Future<void> stopBonjourService() async {
    await _bonsoirBroadcast?.stop();
    _bonsoirBroadcast = null;
    setState(() => _isServiceRunning = false);
    _serviceBox.put('isServiceRunning', false);
  }

 Future<void> startHttpServer() async {
  await _server?.close();
  _server = null;

  try {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    print("🖨️ HTTP Server Running on Port 8080");

    await for (HttpRequest request in _server!) {
      print("📥 Received Request: ${request.method} at ${request.uri.path}");

      if (request.method == 'POST') {
        print("📩 Handling POST request...");
        Uint8List ippData = await receivePdfData(request);

        try {
          Directory downloadDirectory;

          if (Platform.isAndroid) {
            downloadDirectory = Directory('/storage/emulated/0/Download');

            var status = await Permission.manageExternalStorage.status;
            if (!status.isGranted) {
              var requestedStatus =
                  await Permission.manageExternalStorage.request();
              if (!requestedStatus.isGranted) {
                print("❌ Storage permission denied!");
                return;
              }
            }

            if (!downloadDirectory.existsSync()) {
              downloadDirectory.createSync(recursive: true);
            }
          } else {
            downloadDirectory = await getApplicationDocumentsDirectory();
          }

          final rawFile = File(
              '${downloadDirectory.path}/raw_ipp_data_${DateTime.now().millisecondsSinceEpoch}.bin'); // Corrected string interpolation
          await rawFile.writeAsBytes(ippData);
          print("Raw ipp data saved to ${rawFile.path}");

          if (ippData.isEmpty) {
            print("❌ No data received in IPP request!");
            request.response
              ..statusCode = HttpStatus.badRequest
              ..write('❌ No IPP data received!')
              ..close();
            continue;
          }

          saveIPPDocument(
              ippData, downloadDirectory);
          print("✅ Successfully processed IPP request.");
        } catch (error) {
          print("❌ Error saving raw ipp data: $error");
        }
      } else {
        print("🔹 Non-POST request received: ${request.method}");
      }
    }
  } catch (e) {
    print("❌ Error starting HTTP server: $e");
  }
}
  Future<void> saveIPPDocument(
      Uint8List ippData, Directory downloadDirectory) async {
    print("📥 Received IPP Data: ${ippData.length} bytes");

    int docStartIndex = findDocumentStartIndex(ippData);
    print("Document start index: $docStartIndex");

    if (docStartIndex == -1 || docStartIndex >= ippData.length - 1) {
      print("❌ No valid document data found in the IPP request!");
      return;
    }

    Uint8List documentData = ippData.sublist(docStartIndex);
    if (documentData.isEmpty) {
      print("❌ Document data is empty after IPP headers!");
      return;
    }

    print("✅ Extracted Document Data: <span class=${documentData.length} bytes");

try {
final extractedFile = File(
'</span>{downloadDirectory.path}/extracted_document_data_${DateTime.now().millisecondsSinceEpoch}.bin');
      await extractedFile.writeAsBytes(documentData);
      print("Extracted document data saved to <span class=${extractedFile.path}");
String filePath =
"</span>{downloadDirectory.path}/extracted_document_${DateTime.now().millisecondsSinceEpoch}.ps";
      File file = File(filePath);
      await file.writeAsBytes(documentData);
      print("Extracted PostScript file saved: $filePath");
    } catch (e) {
      print("❌ Error saving document: $e");
    }
  }

  Future<Uint8List> receivePdfData(HttpRequest request) async {
    List<int> receivedData = [];
    await for (var data in request) {
      receivedData.addAll(data);
    }
    return Uint8List.fromList(receivedData);
  }

 int findDocumentStartIndex(Uint8List ippData) {
  for (int i = 0; i < ippData.length - 1; i++) {
    print("Checking byte at index $i: ${ippData[i]}"); // Add this line
    if (ippData[i] == 0x03) {
      print("Found 0x03 at index $i"); // Add this line
      return i + 1;
    }
  }
  print("0x03 not found"); 
  return -1;
}

  void handlePrint() {
    print("handlePrint called, but no longer used for pdf display");
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