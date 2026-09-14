import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/ocr_client.dart';
import '../../../core/services/on_device_ocr_service.dart';
import '../../../core/services/document_parser_service.dart';
import '../models/document_data.dart';

// Provider for On-Device ML Kit OCR
final onDeviceOcrServiceProvider = Provider<OnDeviceOCRService>((ref) {
  final service = OnDeviceOCRService();
  ref.onDispose(() => service.dispose());
  return service;
});

// Provider for pure Dart Document Parser
final documentParserServiceProvider = Provider<DocumentParserService>((ref) {
  return DocumentParserService();
});

// Provider for the OCR Microservice client (optional desktop/web target)
final ocrClientServiceProvider = Provider<OCRClientService>((ref) {
  return OCRClientService();
});


// Notifier for managing the active scanned document
class ActiveDocumentNotifier extends Notifier<ScannedDocumentData?> {
  @override
  ScannedDocumentData? build() => null;

  void setDocument(ScannedDocumentData doc) {
    state = doc;
  }

  void updateField({
    String? fullName,
    String? documentNumber,
    String? cpf,
    String? birthDate,
    String? motherName,
    String? issuingOrgan,
    String? issuingState,
    String? cnhCategory,
    String? cnhRenach,
    String? nationality,
    String? expiryDate,
  }) {
    if (state == null) return;
    state = state!.copyWith(
      fullName: fullName ?? state!.fullName,
      documentNumber: documentNumber ?? state!.documentNumber,
      cpf: cpf ?? state!.cpf,
      birthDate: birthDate ?? state!.birthDate,
      motherName: motherName ?? state!.motherName,
      issuingOrgan: issuingOrgan ?? state!.issuingOrgan,
      issuingState: issuingState ?? state!.issuingState,
      cnhCategory: cnhCategory ?? state!.cnhCategory,
      cnhRenach: cnhRenach ?? state!.cnhRenach,
      nationality: nationality ?? state!.nationality,
      expiryDate: expiryDate ?? state!.expiryDate,
    );
  }

  void clear() {
    state = null;
  }
}

final activeDocumentProvider =
    NotifierProvider<ActiveDocumentNotifier, ScannedDocumentData?>(ActiveDocumentNotifier.new);

// Scan History Notifier
class ScanHistoryNotifier extends Notifier<List<ScannedDocumentData>> {
  @override
  List<ScannedDocumentData> build() => [];

  void add(ScannedDocumentData doc) {
    state = [doc, ...state];
  }

  void remove(String id) {
    state = state.where((d) => d.id != id).toList();
  }

  void clearAll() {
    state = [];
  }
}

final scanHistoryProvider =
    NotifierProvider<ScanHistoryNotifier, List<ScannedDocumentData>>(ScanHistoryNotifier.new);
