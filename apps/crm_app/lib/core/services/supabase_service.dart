import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import '../../features/scanner/models/document_data.dart';

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

final supabaseDocumentsStreamProvider = StreamProvider<List<ScannedDocumentData>>((ref) {
  final service = ref.watch(supabaseServiceProvider);
  if (!service.isConfigured) {
    return Stream.value([]);
  }
  return service.streamScannedDocuments();
});

class SupabaseService {
  /// Checks whether Supabase has been initialized with active credentials
  bool get isConfigured {
    try {
      // ignore: unnecessary_null_comparison
      return Supabase.instance.client != null;
    } catch (_) {
      return false;
    }
  }

  SupabaseClient? get client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Dynamically initialize or switch Supabase project URL & Anon Key at runtime
  static Future<bool> initializeWithCredentials({
    required String url,
    required String anonKey,
  }) async {
    try {
      final cleanUrl = url.trim();
      final cleanKey = anonKey.trim();
      if (cleanUrl.isEmpty || cleanKey.isEmpty) return false;

      await Supabase.initialize(
        url: cleanUrl,
        // ignore: deprecated_member_use
        anonKey: cleanKey,
      );
      return true;
    } catch (e) {
      debugPrint('[!] Supabase initialization error: $e');
      return false;
    }
  }

  /// Real-time stream of past scanned documents
  Stream<List<ScannedDocumentData>> streamScannedDocuments() {
    final c = client;
    if (c == null) return Stream.value([]);

    try {
      return c
          .from('scanned_documents')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .map((rows) => rows.map((json) => ScannedDocumentData.fromOcrJson(json)).toList());
    } catch (e) {
      debugPrint('[!] Error streaming scanned documents: $e');
      return Stream.value([]);
    }
  }

  /// One-time fetch of past scans
  Future<List<ScannedDocumentData>> fetchScannedDocuments({int limit = 50}) async {
    final c = client;
    if (c == null) return [];

    try {
      final List<dynamic> rows = await c
          .from('scanned_documents')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);

      return rows
          .map((row) => ScannedDocumentData.fromOcrJson(row as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[!] Error fetching scanned documents: $e');
      return [];
    }
  }

  /// Upload document image / PDF into the 'client-documents' storage bucket
  Future<String?> uploadDocumentFile({
    required String fileName,
    required Uint8List fileBytes,
    String mimeType = 'image/jpeg',
  }) async {
    final c = client;
    if (c == null) return null;

    try {
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final storagePath = 'scans/${DateTime.now().millisecondsSinceEpoch}_$safeName';

      await c.storage.from(AppConstants.documentsBucket).uploadBinary(
            storagePath,
            fileBytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: true),
          );

      return storagePath;
    } catch (e) {
      debugPrint('[!] Storage upload warning: $e');
      return null;
    }
  }

  /// Save extracted document metadata and raw OCR payload into Supabase 'scanned_documents'
  Future<bool> saveScannedDocument({
    required ScannedDocumentData doc,
    Uint8List? fileBytes,
    String? fileName,
  }) async {
    final c = client;
    if (c == null) return false;

    try {
      String? storagePath;
      if (fileBytes != null && fileName != null) {
        storagePath = await uploadDocumentFile(
          fileName: fileName,
          fileBytes: fileBytes,
        );
      }

      await c.from('scanned_documents').insert({
        'file_name': fileName ?? 'documento.jpg',
        'file_path': storagePath,
        'file_size_bytes': fileBytes?.length,
        'document_type': doc.documentType,
        'status': 'auto_verified',
        'document_number': doc.documentNumber,
        'cpf': doc.cpf,
        'cpf_valid': doc.cpfValid,
        'full_name': doc.fullName,
        'birth_date': doc.birthDate,
        'mother_name': doc.motherName,
        'father_name': doc.fatherName,
        'naturalness': doc.naturalness,
        'nationality': doc.nationality,
        'gender': doc.gender,
        'issuing_organ': doc.issuingOrgan,
        'issuing_state': doc.issuingState,
        'issuing_country': doc.issuingCountry,
        'issuing_date': doc.issuingDate,
        'expiry_date': doc.expiryDate,
        'cnh_category': doc.cnhCategory,
        'cnh_renach': doc.cnhRenach,
        'cnh_first_license_date': doc.cnhFirstLicenseDate,
        'passport_mrz_valid': doc.mrzValid,
        'confidence_score': doc.confidenceScore,
        'raw_ocr_text': doc.rawText,
        'extracted_payload': doc.toJson(),
      });

      return true;
    } catch (e) {
      debugPrint('[!] Supabase document insertion error: $e');
      return false;
    }
  }

  /// Delete document record and associated file
  Future<bool> deleteScannedDocument(String id, {String? storagePath}) async {
    final c = client;
    if (c == null) return false;

    try {
      await c.from('scanned_documents').delete().eq('id', id);

      if (storagePath != null && storagePath.isNotEmpty) {
        await c.storage.from(AppConstants.documentsBucket).remove([storagePath]);
      }
      return true;
    } catch (e) {
      debugPrint('[!] Supabase delete error: $e');
      return false;
    }
  }
}
