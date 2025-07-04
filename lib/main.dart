import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _isScanning = false;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  Timer? _advertisingTimer;

  @override
  void initState() {
    super.initState();
    _initializeBLE();
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _advertisingTimer?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
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

      // Kiểm tra trạng thái Bluetooth
      await _checkBluetoothState();
      
    } catch (e) {
      setState(() {
        _status = "Lỗi khởi tạo: $e";
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
      ]);
    } else if (Platform.isIOS) {
      permissions.add(Permission.bluetooth);
    }

    Map<Permission, PermissionStatus> statuses = await permissions.request();
    
    // Kiểm tra xem tất cả quyền có được cấp không
    for (var status in statuses.values) {
      if (status != PermissionStatus.granted) {
        return false;
      }
    }
    
    return true;
  }

  // Kiểm tra trạng thái Bluetooth
  Future<void> _checkBluetoothState() async {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        setState(() {
          _status = "Bluetooth đã bật. Đang quét thiết bị...";
        });
        _startScanning();
      } else {
        setState(() {
          _status = "Vui lòng bật Bluetooth";
        });
      }
    });
  }

  // Bắt đầu quét thiết bị BLE
  Future<void> _startScanning() async {
    if (_isScanning) return;
    
    setState(() {
      _isScanning = true;
      _status = "Đang quét thiết bị BLE...";
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true,
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult result in results) {
          if (result.device.remoteId.toString().isNotEmpty) {
            String mac = result.device.remoteId.toString();
            setState(() {
              _deviceMac = mac;
              _status = "Đã tìm thấy thiết bị: $mac";
            });
            
            // Dừng quét và chuyển hướng
            FlutterBluePlus.stopScan();
            _startAdvertising();
            _redirectToWeb(mac);
            break;
          }
        }
      });

      // Nếu không tìm thấy thiết bị nào sau 10 giây
      Future.delayed(const Duration(seconds: 10), () {
        if (_isScanning && _deviceMac.isEmpty) {
          setState(() {
            _status = "Không tìm thấy thiết bị. Đang thử lại...";
          });
          _startScanning(); // Thử lại
        }
      });

    } catch (e) {
      setState(() {
        _status = "Lỗi quét: $e";
        _isScanning = false;
      });
    }
  }

  // Bắt đầu phát BLE liên tục
  void _startAdvertising() {
    // Phát BLE mỗi 5 giây
    _advertisingTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _advertiseBLE();
    });
  }

  // Phát BLE (advertising)
  Future<void> _advertiseBLE() async {
    try {
      // Ghi chú: Flutter Blue Plus không hỗ trợ trực tiếp advertising
      // Bạn có thể cần sử dụng plugin khác như flutter_bluetooth_serial
      // hoặc tự implement native code cho advertising
      
      // Thay vào đó, chúng ta sẽ tiếp tục quét để duy trì hoạt động BLE
      if (!_isScanning) {
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
        Future.delayed(const Duration(seconds: 2), () {
          FlutterBluePlus.stopScan();
        });
      }
    } catch (e) {
      print("Lỗi advertising: $e");
    }
  }

  // Chuyển hướng sang web với địa chỉ MAC
  Future<void> _redirectToWeb(String mac) async {
    await Future.delayed(const Duration(seconds: 2)); // Chờ 2 giây để hiển thị thông tin
    
    final Uri url = Uri.parse('https://google.com/search?q=$mac');
    
    try {
      bool launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
      
      if (!launched) {
        setState(() {
          _status = "Không thể mở trình duyệt";
        });
      }
    } catch (e) {
      setState(() {
        _status = "Lỗi mở URL: $e";
      });
    }
  }

  // Thử lại quá trình
  void _retry() {
    setState(() {
      _deviceMac = "";
      _isScanning = false;
      _status = "Đang thử lại...";
    });
    _advertisingTimer?.cancel();
    _initializeBLE();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE MAC Scanner'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.bluetooth_searching,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 20),
              const Text(
                'BLE MAC Scanner',
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
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Địa chỉ MAC:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _deviceMac,
                        style: const TextStyle(
                          fontSize: 16,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              const SizedBox(height: 20),
              if (_isScanning)
                const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
