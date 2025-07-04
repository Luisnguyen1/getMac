import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:beacon_broadcast/beacon_broadcast.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE MAC Scanner',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BLEMacScanner(),
    );
  }
}

class BLEMacScanner extends StatefulWidget {
  const BLEMacScanner({super.key});

  @override
  State<BLEMacScanner> createState() => _BLEMacScannerState();
}

class _BLEMacScannerState extends State<BLEMacScanner> {
  String _status = "Đang kiểm tra quyền...";
  String _deviceMac = "";
  bool _isAdvertising = false;
  Timer? _keepAliveTimer;
  String _beaconUuid = "";
  BeaconBroadcast beaconBroadcast = BeaconBroadcast();

  @override
  void initState() {
    super.initState();
    _generateBeaconUuid();
    _initializeBLE();
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _stopAdvertising();
    super.dispose();
  }

  // Tạo UUID duy nhất cho beacon
  void _generateBeaconUuid() {
    final random = Random();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    
    // Format UUID như chuẩn
    _beaconUuid = 
        "${bytes[0].toRadixString(16).padLeft(2, '0')}"
        "${bytes[1].toRadixString(16).padLeft(2, '0')}"
        "${bytes[2].toRadixString(16).padLeft(2, '0')}"
        "${bytes[3].toRadixString(16).padLeft(2, '0')}-"
        "${bytes[4].toRadixString(16).padLeft(2, '0')}"
        "${bytes[5].toRadixString(16).padLeft(2, '0')}-"
        "${bytes[6].toRadixString(16).padLeft(2, '0')}"
        "${bytes[7].toRadixString(16).padLeft(2, '0')}-"
        "${bytes[8].toRadixString(16).padLeft(2, '0')}"
        "${bytes[9].toRadixString(16).padLeft(2, '0')}-"
        "${bytes[10].toRadixString(16).padLeft(2, '0')}"
        "${bytes[11].toRadixString(16).padLeft(2, '0')}"
        "${bytes[12].toRadixString(16).padLeft(2, '0')}"
        "${bytes[13].toRadixString(16).padLeft(2, '0')}"
        "${bytes[14].toRadixString(16).padLeft(2, '0')}"
        "${bytes[15].toRadixString(16).padLeft(2, '0')}";
    
    setState(() {
      _deviceMac = _beaconUuid.toUpperCase();
    });
  }

  // Khởi tạo BLE và kiểm tra quyền
  Future<void> _initializeBLE() async {
    setState(() {
      _status = "Đang kiểm tra quyền BLE...";
    });

    try {
      // Kiểm tra và yêu cầu quyền
      bool hasPermissions = await _requestPermissions();
      
      if (!hasPermissions) {
        setState(() {
          _status = "Cần cấp quyền Bluetooth để tiếp tục";
        });
        return;
      }

      // Khởi tạo beacon
      await _initializeBeacon();
      
    } catch (e) {
      setState(() {
        _status = "Lỗi khởi tạo: $e";
      });
    }
  }

  // Khởi tạo beacon service
  Future<void> _initializeBeacon() async {
    try {
      setState(() {
        _status = "Đang kiểm tra khả năng phát beacon...";
      });

      // Kiểm tra xem thiết bị có hỗ trợ advertising không
      bool isSupported = await beaconBroadcast.checkTransmissionSupported();
      
      if (!isSupported) {
        setState(() {
          _status = "Thiết bị không hỗ trợ phát BLE beacon";
        });
        return;
      }

      // Bắt đầu phát beacon
      await _startAdvertising();
      
    } catch (e) {
      setState(() {
        _status = "Lỗi khởi tạo beacon: $e";
      });
    }
  }

  // Yêu cầu quyền cần thiết
  Future<bool> _requestPermissions() async {
    List<Permission> permissions = [];
    
    if (Platform.isAndroid) {
      permissions.addAll([
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.locationWhenInUse,
      ]);
    } else if (Platform.isIOS) {
      permissions.addAll([
        Permission.bluetooth,
        Permission.locationWhenInUse,
      ]);
    }

    // Yêu cầu từng quyền một cách linh hoạt
    bool allGranted = true;
    for (Permission permission in permissions) {
      final status = await permission.request();
      if (status != PermissionStatus.granted && status != PermissionStatus.permanentlyDenied) {
        allGranted = false;
      }
    }
    
    return allGranted;
  }

  // Bắt đầu phát BLE beacon
  Future<void> _startAdvertising() async {
    if (_isAdvertising) return;

    try {
      setState(() {
        _status = "Đang bắt đầu phát BLE beacon...";
      });

      // Thiết lập beacon layout (iBeacon format)
      beaconBroadcast
          .setUUID(_beaconUuid)
          .setMajorId(1)
          .setMinorId(1)
          .setIdentifier('MyBeacon')
          .setLayout(BeaconBroadcast.ALTBEACON_LAYOUT)
          .setManufacturerId(0x004c); // Apple manufacturer ID for iBeacon

      // Bắt đầu phát beacon
      await beaconBroadcast.start();
      
      setState(() {
        _isAdvertising = true;
        _status = "Đang phát BLE beacon. Chuyển hướng sau 3 giây...";
      });

      // Thiết lập timer để duy trì hoạt động
      _setupKeepAlive();

      // Chuyển hướng sau 3 giây
      Future.delayed(const Duration(seconds: 3), () {
        _redirectToWeb(_deviceMac);
      });

    } catch (e) {
      setState(() {
        _status = "Lỗi bắt đầu phát beacon: $e";
        _isAdvertising = false;
      });
    }
  }

  // Duy trì beacon hoạt động
  void _setupKeepAlive() {
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (_isAdvertising) {
        try {
          // Kiểm tra và restart beacon nếu cần
          bool isTransmitting = await beaconBroadcast.isTransmitting();
          if (!isTransmitting) {
            await beaconBroadcast.start();
          }
        } catch (e) {
          print("Lỗi duy trì beacon: $e");
        }
      }
    });
  }

  // Dừng phát beacon
  Future<void> _stopAdvertising() async {
    try {
      await beaconBroadcast.stop();
      _keepAliveTimer?.cancel();
      setState(() {
        _isAdvertising = false;
      });
    } catch (e) {
      print("Lỗi dừng beacon: $e");
    }
  }

  // Chuyển hướng sang web với thông tin beacon
  Future<void> _redirectToWeb(String beaconId) async {
    await Future.delayed(const Duration(seconds: 1)); // Chờ 1 giây
    
    final Uri url = Uri.parse('https://google.com/search?q=beacon_$beaconId');
    
    try {
      bool launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      
      if (launched) {
        setState(() {
          _status = "Đã chuyển hướng web. Beacon vẫn đang chạy ngầm.";
        });
      } else {
        setState(() {
          _status = "Không thể mở trình duyệt. Beacon vẫn đang hoạt động.";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Lỗi mở URL: $e. Beacon vẫn đang hoạt động.";
      });
    }
  }

  // Thử lại quá trình
  void _retry() {
    setState(() {
      _status = "Đang thử lại...";
    });
    _stopAdvertising();
    _generateBeaconUuid();
    _initializeBLE();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Beacon Transmitter'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isAdvertising ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                size: 80,
                color: _isAdvertising ? Colors.green : Colors.blue,
              ),
              const SizedBox(height: 20),
              const Text(
                'BLE Beacon Transmitter',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 20),
              if (_deviceMac.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _isAdvertising ? Colors.green.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isAdvertising ? Colors.green.shade200 : Colors.blue.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _isAdvertising ? 'Beacon UUID (Đang phát):' : 'Beacon UUID:',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _deviceMac,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_isAdvertising) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Đang phát beacon',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  if (_isAdvertising)
                    ElevatedButton.icon(
                      onPressed: () => _stopAdvertising(),
                      icon: const Icon(Icons.stop),
                      label: const Text('Dừng'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (_isAdvertising)
                const Text(
                  'App đang chạy ngầm phát beacon.\nCác beacon của bạn có thể đo RSSI từ thiết bị này.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
