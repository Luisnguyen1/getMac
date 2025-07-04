import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Bluetooth MAC Scanner'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String _bluetoothStatus = "Checking Bluetooth...";
  String _deviceIdentifier = "Scanning for device...";

  @override
  void initState() {
    super.initState();
    _checkBluetoothStatus();
  }

  // Check and request Bluetooth permissions
  Future<void> _checkBluetoothStatus() async {
    try {
      // Check if Bluetooth is currently enabled.
      FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.on) {
          setState(() {
            _bluetoothStatus = "Bluetooth is ON. Tap to scan.";
          });
        } else {
          setState(() {
            _bluetoothStatus = "Bluetooth is OFF. Please turn it ON.";
          });
        }
      });
    } catch (e) {
      setState(() {
        _bluetoothStatus = "Error checking Bluetooth status: $e";
      });
    }
  }

  // Scan for a Bluetooth device and get its identifier
  Future<void> _scanAndGetIdentifier() async {
    setState(() {
      _deviceIdentifier = "Scanning...";
    });

    try {
      // Start scanning for a short duration
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));

      // Listen to scan results and get the first available device
      var subscription = FlutterBluePlus.scanResults.listen((results) {
        if (results.isNotEmpty) {
          // Get the first scanned device
          ScanResult firstResult = results.first;
          // Use device ID as identifier. Note: MAC address is not reliably available on all platforms/versions for privacy.
          String identifier = firstResult.device.remoteId.toString(); // Use remoteId instead of id
          setState(() {
            _deviceIdentifier = "Device found: ${firstResult.device.platformName.isNotEmpty ? firstResult.device.platformName : 'Unknown Device'}";
          });
          _launchURL(identifier);
          // Stop scanning after finding a device
          FlutterBluePlus.stopScan();
        }
      });

      // Auto-stop scan after timeout and cleanup
      Future.delayed(const Duration(seconds: 6), () {
        subscription.cancel();
        if (mounted && _deviceIdentifier == "Scanning...") {
          setState(() {
            _deviceIdentifier = "No devices found. Try again.";
          });
        }
      });
    } catch (e) {
      setState(() {
        _deviceIdentifier = "Error scanning: $e";
      });
    }
  }

  // Launch the URL with the device identifier
  Future<void> _launchURL(String identifier) async {
    final Uri _url = Uri.parse('https://example.com/?mac=$identifier');
    if (!await launchUrl(_url)) {
      // Handle error if URL cannot be launched
      throw Exception('Could not launch $_url');
    }
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'Bluetooth Device Scanner',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Text(
              _bluetoothStatus,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            Text(
              _deviceIdentifier,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Check if Bluetooth is on before scanning
                FlutterBluePlus.adapterState.first.then((state) {
                  if (state == BluetoothAdapterState.on) {
                    _scanAndGetIdentifier();
                  } else {
                    setState(() {
                      _bluetoothStatus = "Please turn on Bluetooth first!";
                    });
                  }
                });
              },
              child: const Text('Scan and Open URL'),
            ),
          ],
        ),
      ),
    );
  }
}
