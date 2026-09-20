import 'dart:convert';

class ScannedDocumentData {
  final String id;
  final String documentType; // rg, cnh, passport, cin, cpf
  final String? documentNumber;
  final String? cpf;
  final bool cpfValid;
  final String? fullName;
  final String? surname;
  final String? givenNames;
  final String? birthDate;
  final String? userId;
  final String? naturalness;
  final String? nationality;
  final String? gender;
  final String? issuingOrgan;
  final String? issuingState;
  final String? issuingCountry;
  final String? issuingDate;
  final String? expiryDate;
  
  // CNH specific
  final String? cnhCategory;
  final String? cnhRenach;
  final String? cnhFirstLicenseDate;
  
  // Passport / MRZ specific
  final bool mrzValid;
  final double confidenceScore;
  final String? rawText;
  final DateTime scannedAt;

  ScannedDocumentData({
    required this.id,
    required this.documentType,
    this.documentNumber,
    this.cpf,
    this.cpfValid = false,
    this.fullName,
    this.surname,
    this.givenNames,
    this.birthDate,
    this.userId,
    this.naturalness,
    this.nationality,
    this.gender,
    this.issuingOrgan,
    this.issuingState,
    this.issuingCountry,
    this.issuingDate,
    this.expiryDate,
    this.cnhCategory,
    this.cnhRenach,
    this.cnhFirstLicenseDate,
    this.mrzValid = false,
    this.confidenceScore = 0.0,
    this.rawText,
    DateTime? scannedAt,
  }) : scannedAt = scannedAt ?? DateTime.now();

  factory ScannedDocumentData.fromOcrJson(Map<String, dynamic> json, {String? rawText}) {
    return ScannedDocumentData(
      id: (json['id'] as String?) ?? DateTime.now().millisecondsSinceEpoch.toString(),
      documentType: json['document_type'] as String? ?? 'rg',
      documentNumber: json['document_number'] as String?,
      cpf: json['cpf'] as String?,
      cpfValid: json['cpf_valid'] as bool? ?? false,
      fullName: json['full_name'] as String?,
      surname: json['surname'] as String?,
      givenNames: json['given_names'] as String?,
      birthDate: json['birth_date'] as String?,
      userId: json['user_id'] as String?,
      naturalness: json['naturalness'] as String?,
      nationality: json['nationality'] as String?,
      gender: json['gender'] as String?,
      issuingOrgan: json['issuing_organ'] as String?,
      issuingState: json['issuing_state'] as String?,
      issuingCountry: json['issuing_country'] as String?,
      issuingDate: json['issuing_date'] as String?,
      expiryDate: json['expiry_date'] as String?,
      cnhCategory: json['cnh_category'] as String?,
      cnhRenach: json['cnh_renach'] as String?,
      cnhFirstLicenseDate: json['cnh_first_license_date'] as String?,
      mrzValid: (json['mrz_valid'] as bool?) ?? (json['passport_mrz_valid'] as bool?) ?? false,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.0,
      rawText: rawText ?? (json['raw_ocr_text'] as String?),
      scannedAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString())
          : (json['scanned_at'] != null ? DateTime.tryParse(json['scanned_at'].toString()) : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'document_type': documentType,
      'document_number': documentNumber,
      'cpf': cpf,
      'cpf_valid': cpfValid,
      'full_name': fullName,
      'surname': surname,
      'given_names': givenNames,
      'birth_date': birthDate,
      'user_id': userId,
      'naturalness': naturalness,
      'nationality': nationality,
      'gender': gender,
      'issuing_organ': issuingOrgan,
      'issuing_state': issuingState,
      'issuing_country': issuingCountry,
      'issuing_date': issuingDate,
      'expiry_date': expiryDate,
      'cnh_category': cnhCategory,
      'cnh_renach': cnhRenach,
      'cnh_first_license_date': cnhFirstLicenseDate,
      'mrz_valid': mrzValid,
      'confidence_score': confidenceScore,
      'scanned_at': scannedAt.toIso8601String(),
    };
  }

  String toFormattedJson() {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(toJson());
  }

  String toCsvRow() {
    final fields = [
      documentType,
      documentNumber ?? '',
      cpf ?? '',
      fullName ?? '',
      birthDate ?? '',
      nationality ?? '',
      issuingOrgan ?? '',
      expiryDate ?? '',
      cnhCategory ?? '',
      cnhRenach ?? ''
    ];
    return fields.map((f) => '"${f.replaceAll('"', '""')}"').join(',');
  }

  static String csvHeader() {
    return '"Tipo","Numero","CPF","Nome","Nascimento","Nacionalidade","Orgao","Validade","Categoria_CNH","RENACH"';
  }

  ScannedDocumentData copyWith({
    String? id,
    String? documentType,
    String? documentNumber,
    String? cpf,
    bool? cpfValid,
    String? fullName,
    String? surname,
    String? givenNames,
    String? birthDate,
    String? userId,
    String? naturalness,
    String? nationality,
    String? gender,
    String? issuingOrgan,
    String? issuingState,
    String? issuingCountry,
    String? issuingDate,
    String? expiryDate,
    String? cnhCategory,
    String? cnhRenach,
    String? cnhFirstLicenseDate,
    bool? mrzValid,
    double? confidenceScore,
    String? rawText,
    DateTime? scannedAt,
  }) {
    return ScannedDocumentData(
      id: id ?? this.id,
      documentType: documentType ?? this.documentType,
      documentNumber: documentNumber ?? this.documentNumber,
      cpf: cpf ?? this.cpf,
      cpfValid: cpfValid ?? this.cpfValid,
      fullName: fullName ?? this.fullName,
      surname: surname ?? this.surname,
      givenNames: givenNames ?? this.givenNames,
      birthDate: birthDate ?? this.birthDate,
      userId: userId ?? this.userId,
      naturalness: naturalness ?? this.naturalness,
      nationality: nationality ?? this.nationality,
      gender: gender ?? this.gender,
      issuingOrgan: issuingOrgan ?? this.issuingOrgan,
      issuingState: issuingState ?? this.issuingState,
      issuingCountry: issuingCountry ?? this.issuingCountry,
      issuingDate: issuingDate ?? this.issuingDate,
      expiryDate: expiryDate ?? this.expiryDate,
      cnhCategory: cnhCategory ?? this.cnhCategory,
      cnhRenach: cnhRenach ?? this.cnhRenach,
      cnhFirstLicenseDate: cnhFirstLicenseDate ?? this.cnhFirstLicenseDate,
      mrzValid: mrzValid ?? this.mrzValid,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      rawText: rawText ?? this.rawText,
      scannedAt: scannedAt ?? this.scannedAt,
    );
  }
}
