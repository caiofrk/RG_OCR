import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';
import '../../features/scanner/models/document_data.dart';

class OCRProcessResult {
  final bool success;
  final String message;
  final ScannedDocumentData? documentData;
  final String? rawText;
  final double processingTimeMs;
  final String? savedDocumentId;

  OCRProcessResult({
    required this.success,
    required this.message,
    this.documentData,
    this.rawText,
    required this.processingTimeMs,
    this.savedDocumentId,
  });

  factory OCRProcessResult.fromJson(Map<String, dynamic> json) {
    final rawText = json['raw_text'] as String?;
    final extractedJson = json['extracted_data'] as Map<String, dynamic>? ?? {};
    final savedId = json['saved_document_id'] as String?;

    var doc = ScannedDocumentData.fromOcrJson(extractedJson, rawText: rawText);
    if (savedId != null && savedId.isNotEmpty) {
      doc = ScannedDocumentData(
        id: savedId,
        documentType: doc.documentType,
        documentNumber: doc.documentNumber,
        cpf: doc.cpf,
        cpfValid: doc.cpfValid,
        fullName: doc.fullName,
        surname: doc.surname,
        givenNames: doc.givenNames,
        birthDate: doc.birthDate,
        motherName: doc.motherName,
        fatherName: doc.fatherName,
        naturalness: doc.naturalness,
        nationality: doc.nationality,
        gender: doc.gender,
        issuingOrgan: doc.issuingOrgan,
        issuingState: doc.issuingState,
        issuingCountry: doc.issuingCountry,
        issuingDate: doc.issuingDate,
        expiryDate: doc.expiryDate,
        cnhCategory: doc.cnhCategory,
        cnhRenach: doc.cnhRenach,
        cnhFirstLicenseDate: doc.cnhFirstLicenseDate,
        mrzValid: doc.mrzValid,
        confidenceScore: doc.confidenceScore,
        rawText: doc.rawText,
        scannedAt: doc.scannedAt,
      );
    }
    
    return OCRProcessResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      documentData: doc,
      rawText: rawText,
      processingTimeMs: (json['processing_time_ms'] as num?)?.toDouble() ?? 0.0,
      savedDocumentId: savedId,
    );
  }
}

class OCRClientService {
  String baseUrl;

  OCRClientService({String? baseUrl})
      : baseUrl = (baseUrl ?? AppConstants.ocrBaseUrl).replaceAll(RegExp(r'/+$'), '');

  void updateBaseUrl(String newUrl) {
    baseUrl = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }

  Future<bool> testConnection([String? testUrl]) async {
    try {
      final target = (testUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
      final res = await http.get(Uri.parse('$target/health')).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  List<String> _getCandidates() {
    final list = <String>[baseUrl];
    for (final cand in ['http://127.0.0.1:8000', 'http://192.168.0.3:8000', 'http://10.0.2.2:8000']) {
      if (!list.contains(cand)) {
        list.add(cand);
      }
    }
    return list;
  }

  // Process RG, CNH, Passport, CIN, or CPF image bytes via Python FastAPI microservice
  Future<OCRProcessResult> processDocumentBytes({
    required Uint8List bytes,
    required String filename,
    String docType = 'auto',
  }) async {
    final candidates = _getCandidates();

    for (final targetUrl in candidates) {
      final uri = Uri.parse('$targetUrl/api/v1/ocr/process-document');
      final request = http.MultipartRequest('POST', uri);

      request.fields['doc_type'] = docType;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
        ),
      );

      try {
        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 35),
          onTimeout: () {
            throw TimeoutException('Tempo limite excedido conectando a $targetUrl');
          },
        );
        final response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          // If a fallback candidate worked, make it our active URL
          if (targetUrl != baseUrl) {
            baseUrl = targetUrl;
          }
          final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          return OCRProcessResult.fromJson(decoded);
        } else {
          return OCRProcessResult(
            success: false,
            message: 'Erro no servidor ($targetUrl - ${response.statusCode}): ${response.body}',
            processingTimeMs: 0,
          );
        }
      } catch (e) {
        // Continue to try next candidate in list if connection refused / timeout
        continue;
      }
    }

    return OCRProcessResult(
      success: false,
      message: 'Não foi possível conectar ao servidor OCR ($baseUrl).\n\n'
          '💡 Dica:\n'
          '1. Se estiver usando cabo USB, execute no PC:\n'
          '   adb reverse tcp:8000 tcp:8000\n'
          '2. Se estiver via Wi-Fi, toque no ícone de rede (topo) e teste a conexão com http://192.168.0.3:8000.',
      processingTimeMs: 0,
    );
  }

  // Save or update document in local SQLite backend
  Future<bool> saveDocument({
    required ScannedDocumentData doc,
    String? fileName,
  }) async {
    for (final targetUrl in _getCandidates()) {
      try {
        final uri = Uri.parse('$targetUrl/api/v1/documents');
        final body = jsonEncode({
          'filename': fileName ?? '${doc.documentType}_${doc.id}.jpg',
          'extracted_data': doc.toJson(),
          'raw_text': doc.rawText ?? '',
          'confidence_score': doc.confidenceScore,
        });

        final response = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (targetUrl != baseUrl) baseUrl = targetUrl;
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  // Fetch saved documents from local SQLite backend
  Future<List<ScannedDocumentData>> fetchSavedDocuments({
    String? search,
    String? docType,
    int limit = 50,
  }) async {
    for (final targetUrl in _getCandidates()) {
      try {
        final queryParams = <String, String>{'limit': limit.toString()};
        if (search != null && search.trim().isNotEmpty) {
          queryParams['search'] = search.trim();
        }
        if (docType != null && docType != 'auto') {
          queryParams['doc_type'] = docType;
        }

        final uri = Uri.parse('$targetUrl/api/v1/documents').replace(queryParameters: queryParams);
        final response = await http.get(uri).timeout(const Duration(seconds: 10));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (targetUrl != baseUrl) baseUrl = targetUrl;
          final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final list = (decoded['documents'] as List<dynamic>?) ?? [];
          return list.map((item) {
            final map = item as Map<String, dynamic>;
            return ScannedDocumentData.fromOcrJson(map);
          }).toList();
        }
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  // Delete saved document from local SQLite backend
  Future<bool> deleteSavedDocument(String docId) async {
    for (final targetUrl in _getCandidates()) {
      try {
        final uri = Uri.parse('$targetUrl/api/v1/documents/$docId');
        final response = await http.delete(uri).timeout(const Duration(seconds: 8));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (targetUrl != baseUrl) baseUrl = targetUrl;
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  OCRProcessResult generateDevFallback(String docType) {
    if (docType == 'passport') {
      return OCRProcessResult(
        success: true,
        message: 'Modo demonstração (Passaporte ICAO 9303)',
        documentData: ScannedDocumentData(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          documentType: 'passport',
          documentNumber: 'CS891234',
          fullName: 'ANNA MARIA ERIKSSON',
          surname: 'ERIKSSON',
          givenNames: 'ANNA MARIA',
          nationality: 'BRA',
          issuingCountry: 'BRA',
          birthDate: '12/08/1974',
          gender: 'F',
          expiryDate: '15/04/2030',
          mrzValid: true,
          confidenceScore: 0.98,
        ),
        rawText: 'P<BRAERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<\nCS891234<6BRA7408122F3004159<<<<<<<<<<<<<<02',
        processingTimeMs: 85.0,
      );
    } else if (docType == 'cnh') {
      return OCRProcessResult(
        success: true,
        message: 'Modo demonstração (CNH)',
        documentData: ScannedDocumentData(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          documentType: 'cnh',
          documentNumber: '04891238910',
          cpf: '529.982.247-25',
          cpfValid: true,
          fullName: 'RODRIGO ALBUQUERQUE MARTINS',
          birthDate: '22/04/1988',
          issuingOrgan: 'DETRAN',
          issuingState: 'SP',
          cnhCategory: 'AB',
          cnhRenach: 'SP912839120',
          expiryDate: '14/08/2028',
          confidenceScore: 0.95,
        ),
        rawText: 'CARTEIRA NACIONAL DE HABILITACAO\nNOME: RODRIGO ALBUQUERQUE MARTINS\nCPF: 529.982.247-25',
        processingTimeMs: 92.0,
      );
    }

    // Default RG Fallback
    return OCRProcessResult(
      success: true,
      message: 'Modo demonstração (RG Tradicional)',
      documentData: ScannedDocumentData(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        documentType: 'rg',
        documentNumber: '38.452.190-8',
        cpf: '529.982.247-25',
        cpfValid: true,
        fullName: 'MARIANA RIBEIRO COSTA',
        birthDate: '18/07/1992',
        motherName: 'TERESA RIBEIRO COSTA',
        fatherName: 'ANTONIO CARLOS COSTA',
        issuingOrgan: 'SSP',
        issuingState: 'SP',
        confidenceScore: 0.94,
      ),
      rawText: 'REGISTRO GERAL 38.452.190-8 SSP/SP\nMARIANA RIBEIRO COSTA\nCPF 529.982.247-25',
      processingTimeMs: 110.0,
    );
  }
}
