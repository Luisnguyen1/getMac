import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:async';
import 'dart:io';

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
  bool _isBluetoothReady = false;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  Timer? _keepAliveTimer;
  String _deviceInfo = "";

  @override
  void initState() {
    super.initState();
    _initializeBLE();
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _keepAliveTimer?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _initializeBLE() async {
    setState(() {
      _status = "Đang kiểm tra quyền BLE...";
    });
    try {
      // Lấy thông tin thiết bị trước
      await _getDeviceInfo();
      
      // Kiểm tra và yêu cầu quyền
      bool hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        setState(() {
          _status = "Cần cấp quyền Bluetooth để tiếp tục";
        });
        return;
      }

      // Kiểm tra trạng thái Bluetooth
      await _checkBluetoothState();
      
    } catch (e) {
      setState(() {
        _status = "Lỗi khởi tạo: $e";
      });
    }
  }

  // Lấy thông tin thiết bị
  Future<void> _getDeviceInfo() async {
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        _deviceInfo = "${androidInfo.brand}_${androidInfo.model}_${androidInfo.id}";
        _deviceMac = androidInfo.id; // Android ID thay cho MAC
      } else if (Platform.isIOS) {
        IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        _deviceInfo = "${iosInfo.name}_${iosInfo.model}_${iosInfo.identifierForVendor}";
        _deviceMac = iosInfo.identifierForVendor ?? "unknown";
      }
      
      setState(() {
        _deviceMac = _deviceMac.toUpperCase();
      });
    } catch (e) {
      setState(() {
        _deviceMac = "DEVICE_${DateTime.now().millisecondsSinceEpoch}";
      });
      return;
    }
    await _startAdvertising();
  }

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
    bool allGranted = true;
    for (Permission permission in permissions) {
      final status = await permission.request();
      if (status != PermissionStatus.granted && status != PermissionStatus.permanentlyDenied) {
        allGranted = false;
      }
    }
    return allGranted;
  }

  // Kiểm tra trạng thái Bluetooth
  Future<void> _checkBluetoothState() async {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        setState(() {
          _status = "Bluetooth đã bật. Đang khởi động chế độ discoverable...";
        });
        _startBluetoothMode();
      } else {
        setState(() {
          _status = "Vui lòng bật Bluetooth để tiếp tục";
        });
      }
    });
  }

  // Bắt đầu chế độ Bluetooth discoverable và scan liên tục
  Future<void> _startBluetoothMode() async {
    try {
      setState(() {
        _status = "Đang khởi động chế độ BLE discoverable...";
      });

      // Bắt đầu scan liên tục để thiết bị có thể được phát hiện
      await _startContinuousScanning();
      
      setState(() {
        _isBluetoothReady = true;
        _status = "BLE đã sẵn sàng. Chuyển hướng sau 3 giây...";
      });

      Future.delayed(const Duration(seconds: 3), () {
        _redirectToWeb(_deviceMac);
      });
    } catch (e) {
      setState(() {
        _status = "Lỗi khởi động BLE: $e";
      });
    }
  }

  // Scan liên tục để duy trì hoạt động Bluetooth
  Future<void> _startContinuousScanning() async {
    try {
      // Bắt đầu scan liên tục với interval ngắn
      _keepAliveTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
        try {
          if (_isBluetoothReady) {
            // Stop scan trước khi start lại
            await FlutterBluePlus.stopScan();
            await Future.delayed(const Duration(milliseconds: 500));
            
            // Start scan với timeout ngắn
            await FlutterBluePlus.startScan(
              timeout: const Duration(seconds: 5),
              androidUsesFineLocation: true,
            );
          }
        } catch (e) {
          print("Lỗi trong quá trình scan: $e");
        }
      });

      // Bắt đầu scan lần đầu
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
        androidUsesFineLocation: true,
      );

    } catch (e) {
      print("Lỗi khởi động scan: $e");
    }
  }

  // Dừng hoạt động Bluetooth
  Future<void> _stopBluetoothMode() async {
    try {
      await FlutterBluePlus.stopScan();
      _keepAliveTimer?.cancel();
      setState(() {
        _isBluetoothReady = false;
      });
    } catch (e) {
      print("Lỗi dừng Bluetooth: $e");
    }
  }

  Future<void> _redirectToWeb(String beaconId) async {
    await Future.delayed(const Duration(seconds: 1));
    final Uri url = Uri.parse('https://google.com/search?q=beacon_$beaconId');
    try {
      bool launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      setState(() {
        _status = launched
            ? "Đã chuyển hướng web. Beacon vẫn đang chạy ngầm."
            : "Không thể mở trình duyệt. Beacon vẫn hoạt động.";
      });
    } catch (e) {
      setState(() {
        _status = "Lỗi mở URL: $e. Beacon vẫn hoạt động.";
      });
    }
  }

  void _retry() {
    setState(() {
      _status = "Đang thử lại...";
    });
    _stopBluetoothMode();
    _initializeBLE();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Device Transmitter'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isBluetoothReady ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                size: 80,
                color: _isBluetoothReady ? Colors.green : Colors.blue,
              ),
              const SizedBox(height: 20),
              const Text(
                'BLE Device Transmitter',
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
                    color: _isBluetoothReady ? Colors.green.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isBluetoothReady ? Colors.green.shade200 : Colors.blue.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _isBluetoothReady ? 'Device ID (Đang phát):' : 'Device ID:',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _deviceMac,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                        textAlign: TextAlign.center,
                      ),
                      if (_isBluetoothReady) ...[
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
                              'BLE đang hoạt động',
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
                  if (_isBluetoothReady)
                    ElevatedButton.icon(
                      onPressed: () => _stopBluetoothMode(),
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
              if (_isBluetoothReady)
                const Text(
                  'App đang chạy ngầm với BLE discoverable.\nCác beacon của bạn có thể đo RSSI từ thiết bị này.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
