import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/app_theme.dart';

class LiveQrScannerScreen extends StatefulWidget {
  const LiveQrScannerScreen({super.key});

  @override
  State<LiveQrScannerScreen> createState() => _LiveQrScannerScreenState();
}

class _LiveQrScannerScreenState extends State<LiveQrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  
  bool _hasFoundCode = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasFoundCode) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final code = barcodes.first.rawValue!;
      if (code.isNotEmpty) {
        setState(() => _hasFoundCode = true);
        _scannerController.stop();
        Navigator.of(context).pop(code);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Ler QR Code / Código de Barras'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            color: Colors.white,
            icon: ValueListenableBuilder(
              valueListenable: _scannerController,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.amber);
                  case TorchState.off:
                  default:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                }
              },
            ),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            color: Colors.white,
            icon: ValueListenableBuilder(
              valueListenable: _scannerController,
              builder: (context, state, child) {
                switch (state.cameraDirection) {
                  case CameraFacing.front:
                    return const Icon(Icons.camera_front);
                  case CameraFacing.back:
                  default:
                    return const Icon(Icons.camera_rear);
                }
              },
            ),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          // Reticle Overlay
          Positioned.fill(
            child: CustomPaint(
              painter: ScannerOverlayPainter(),
            ),
          ),
          // Instructions
          const Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Text(
              'Posicione o QR Code ou Código de Barras dentro da área demarcada',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.fill;
      
    final scanAreaWidth = size.width * 0.85;
    final scanAreaHeight = size.width * 0.55; // Rectangular to fit barcodes
    final left = (size.width - scanAreaWidth) / 2;
    final top = (size.height - scanAreaHeight) / 2;
    
    final scanArea = Rect.fromLTWH(left, top, scanAreaWidth, scanAreaHeight);
    
    // Draw semi-transparent background
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(scanArea, const Radius.circular(12))),
      ),
      paint,
    );
    
    // Draw corner brackets
    final borderPaint = Paint()
      ..color = AppTheme.primaryEmerald
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
      
    final cornerLength = 30.0;
    
    // Top-left
    canvas.drawLine(Offset(left, top + cornerLength), Offset(left, top), borderPaint);
    canvas.drawLine(Offset(left, top), Offset(left + cornerLength, top), borderPaint);
    
    // Top-right
    canvas.drawLine(Offset(left + scanAreaWidth - cornerLength, top), Offset(left + scanAreaWidth, top), borderPaint);
    canvas.drawLine(Offset(left + scanAreaWidth, top), Offset(left + scanAreaWidth, top + cornerLength), borderPaint);
    
    // Bottom-left
    canvas.drawLine(Offset(left, top + scanAreaHeight - cornerLength), Offset(left, top + scanAreaHeight), borderPaint);
    canvas.drawLine(Offset(left, top + scanAreaHeight), Offset(left + cornerLength, top + scanAreaHeight), borderPaint);
    
    // Bottom-right
    canvas.drawLine(Offset(left + scanAreaWidth - cornerLength, top + scanAreaHeight), Offset(left + scanAreaWidth, top + scanAreaHeight), borderPaint);
    canvas.drawLine(Offset(left + scanAreaWidth, top + scanAreaHeight), Offset(left + scanAreaWidth, top + scanAreaHeight - cornerLength), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
