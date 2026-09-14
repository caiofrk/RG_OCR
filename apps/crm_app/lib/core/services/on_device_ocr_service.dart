import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// Result object for on-device OCR processing
class OnDeviceOCRResult {
  final bool success;
  final String rawText;
  final List<String> lines;
  final String? errorMessage;
  final double processingTimeMs;
  final String? qrCodeData;

  OnDeviceOCRResult({
    required this.success,
    required this.rawText,
    required this.lines,
    this.errorMessage,
    this.processingTimeMs = 0.0,
    this.qrCodeData,
  });
}

/// 100% On-Device OCR Service powered by Google ML Kit
/// Executes in-process directly on Android/iOS CPU/NPU with zero network dependencies.
class OnDeviceOCRService {
  TextRecognizer? _recognizer;
  FaceDetector? _faceDetector;
  BarcodeScanner? _barcodeScanner;

  TextRecognizer get recognizer {
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    return _recognizer!;
  }
  
  FaceDetector get faceDetector {
    _faceDetector ??= FaceDetector(options: FaceDetectorOptions(enableTracking: false, enableContours: false, enableClassification: false));
    return _faceDetector!;
  }

  BarcodeScanner get barcodeScanner {
    _barcodeScanner ??= BarcodeScanner(formats: [BarcodeFormat.qrCode, BarcodeFormat.pdf417]);
    return _barcodeScanner!;
  }

  /// Processes an image file directly on the mobile device using ML Kit.
  Future<OnDeviceOCRResult> processImage(String filePath) async {
    final stopwatch = Stopwatch()..start();
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      
      // 1. Face Detection Anti-Fraud Gate
      final faces = await faceDetector.processImage(inputImage);
      if (faces.isEmpty) {
        throw Exception('SEVERE_VALIDATION_ERROR: Nenhuma foto detectada. Certifique-se de escanear a frente de um documento oficial válido.');
      }

      // 2. Text Recognition
      final recognizedText = await recognizer.processImage(inputImage);
      stopwatch.stop();

      final lines = <String>[];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          final t = line.text.trim();
          if (t.isNotEmpty) lines.add(t);
        }
      }

      return OnDeviceOCRResult(
        success: true,
        rawText: recognizedText.text,
        lines: lines,
        processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    } catch (e) {
      stopwatch.stop();
      return OnDeviceOCRResult(
        success: false,
        rawText: '',
        lines: [],
        errorMessage: e.toString(),
        processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    }
  }

  /// Processes an image specifically for QR Codes (bypasses OCR and Face Detection)
  Future<OnDeviceOCRResult> processQRCode(String filePath) async {
    final stopwatch = Stopwatch()..start();
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final barcodes = await barcodeScanner.processImage(inputImage);
      stopwatch.stop();

      if (barcodes.isEmpty) {
        throw Exception('QR_CODE_NOT_FOUND: Nenhum QR Code detectado na imagem.');
      }

      final qrData = barcodes.first.rawValue ?? '';

      return OnDeviceOCRResult(
        success: true,
        rawText: qrData,
        lines: [qrData],
        qrCodeData: qrData,
        processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    } catch (e) {
      stopwatch.stop();
      return OnDeviceOCRResult(
        success: false,
        rawText: '',
        lines: [],
        errorMessage: e.toString(),
        processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
      );
    }
  }

  void dispose() {
    _recognizer?.close();
    _recognizer = null;
    _faceDetector?.close();
    _faceDetector = null;
    _barcodeScanner?.close();
    _barcodeScanner = null;
  }
}
