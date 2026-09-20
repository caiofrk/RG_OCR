import '../../features/scanner/models/document_data.dart';

/// Pure Dart Document Parser & Checksum Verification Suite
/// Implements zero-cost, 100% on-device extraction and validation for:
/// - Brazilian CPF (Modulus 11 algorithm)
/// - CNH (Carteira Nacional de Habilitação)
/// - RG (Registro Geral Tradicional)
/// - Nova CIN (Carteira de Identidade Nacional)
/// - Passaporte ICAO Doc 9303 MRZ (TD3 & TD1 with 7-3-1 weighting)
class DocumentParserService {
  static const Set<String> brazilianStates = {
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA',
    'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN',
    'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
  };

  static const List<String> issuingOrgans = [
    'SSP', 'DETRAN', 'PC', 'IFP', 'ITEP', 'SESP', 'SPTC', 'DIC',
    'POLICIA CIVIL', 'POLICIA FEDERAL', 'SECRETARIA DE SEGURANCA',
    'MINISTERIO DA DEFESA', 'EXERCITO BRASILEIRO', 'MARINHA DO BRASIL',
  ];

  static const List<String> cnhCategories = ['A', 'B', 'AB', 'C', 'D', 'E', 'ACC'];

  static const List<int> mrzWeights = [7, 3, 1];

  // --- 1. Accent Normalization ---

  static String normalizeAccents(String text) {
    const withAccents = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÖØòóôõöøÈÉÊËèéêëÌÍÎÏìíîïÙÚÛÜùúûüÇçÑñÝýÿ';
    const withoutAccents = 'AAAAAAaaaaaaOOOOOOooooooEEEEeeeeIIIIiiiiUUUUuuuuCcNnYyy';

    var result = text;
    for (var i = 0; i < withAccents.length; i++) {
      result = result.replaceAll(withAccents[i], withoutAccents[i]);
    }
    return result.toUpperCase();
  }

  // --- 2. Brazilian CPF Validation (Modulus 11) ---

  /// Validates Brazilian CPF using the official modulus 11 checksum algorithm.
  static bool validateCpf(String? rawCpf) {
    if (rawCpf == null) return false;
    final digits = rawCpf.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

    // First check digit
    var sum1 = 0;
    for (var i = 0; i < 9; i++) {
      sum1 += int.parse(digits[i]) * (10 - i);
    }
    var remainder1 = (sum1 * 10) % 11;
    final checkDigit1 = remainder1 >= 10 ? 0 : remainder1;
    if (int.parse(digits[9]) != checkDigit1) return false;

    // Second check digit
    var sum2 = 0;
    for (var i = 0; i < 10; i++) {
      sum2 += int.parse(digits[i]) * (11 - i);
    }
    var remainder2 = (sum2 * 10) % 11;
    final checkDigit2 = remainder2 >= 10 ? 0 : remainder2;
    if (int.parse(digits[10]) != checkDigit2) return false;

    return true;
  }

  static String? formatCpf(String? rawCpf) {
    if (rawCpf == null) return null;
    final digits = rawCpf.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9, 11)}';
    }
    return rawCpf;
  }

  static ({String? cpf, bool isValid}) extractCpf(String text) {
    final matches = RegExp(r'\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b').allMatches(text);
    for (final m in matches) {
      final candidate = m.group(0)!;
      final clean = candidate.replaceAll(RegExp(r'\D'), '');
      if (validateCpf(clean)) {
        return (cpf: formatCpf(clean), isValid: true);
      }
    }
    if (matches.isNotEmpty) {
      return (cpf: formatCpf(matches.first.group(0)), isValid: false);
    }
    return (cpf: null, isValid: false);
  }

  // --- 3. ICAO Doc 9303 MRZ Checksums (7-3-1 Weighting) ---

  /// Calculates check digit using official ICAO 9303 7-3-1 weighting algorithm.
  static int calculateMrzCheckDigit(String text) {
    var total = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final weight = mrzWeights[i % 3];
      int val;
      if (RegExp(r'\d').hasMatch(char)) {
        val = int.parse(char);
      } else if (char.compareTo('A') >= 0 && char.compareTo('Z') <= 0) {
        val = char.codeUnitAt(0) - 'A'.codeUnitAt(0) + 10;
      } else {
        val = 0;
      }
      total += val * weight;
    }
    return total % 10;
  }

  static bool verifyMrzCheckDigit(String text, String checkChar) {
    if (checkChar.isEmpty || !RegExp(r'\d').hasMatch(checkChar)) return false;
    final expected = int.parse(checkChar);
    return calculateMrzCheckDigit(text) == expected;
  }

  static String? formatMrzDate(String yymmdd) {
    if (yymmdd.length != 6 || !RegExp(r'^\d{6}$').hasMatch(yymmdd)) return null;
    final yy = int.parse(yymmdd.substring(0, 2));
    final mm = yymmdd.substring(2, 4);
    final dd = yymmdd.substring(4, 6);
    final century = yy <= 40 ? 2000 : 1900;
    return '$dd/$mm/${century + yy}';
  }

  /// Parses ICAO 9303 TD3 standard (Passport - 2 lines x 44 chars).
  static Map<String, dynamic> parseTd3(String rawLine1, String rawLine2) {
    var line1 = rawLine1.trim().toUpperCase().replaceAll(' ', '');
    var line2 = rawLine2.trim().toUpperCase().replaceAll(' ', '');

    if (line1.length < 44) line1 = line1.padRight(44, '<');
    if (line2.length < 44) line2 = line2.padRight(44, '<');

    // Line 1: P<ISSNAME<<SURNAME<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
    final issuingCountry = line1.substring(2, 5).replaceAll('<', '');
    final namePart = line1.substring(5, 44);
    final nameTokens = namePart.split('<<').where((t) => t.isNotEmpty).toList();
    final surname = nameTokens.isNotEmpty ? nameTokens[0].replaceAll('<', ' ').trim() : '';
    final givenNames = nameTokens.length > 1 ? nameTokens[1].replaceAll('<', ' ').trim() : '';
    final fullName = givenNames.isNotEmpty ? '$givenNames $surname' : surname;

    // Line 2: DOCNUM9CK_NAT_DOB6CK_SEX_DOE6CK_OPTIONAL14CK_COMPOSITE
    final docNumber = line2.substring(0, 9).replaceAll('<', '');
    final docNumberCheck = line2[9];
    final docNumberValid = verifyMrzCheckDigit(line2.substring(0, 9), docNumberCheck);

    final nationality = line2.substring(10, 13).replaceAll('<', '');

    final dobRaw = line2.substring(13, 19);
    final dobCheck = line2[19];
    final dobValid = verifyMrzCheckDigit(dobRaw, dobCheck);
    final birthDate = formatMrzDate(dobRaw);

    final sexChar = line2[20];
    final sex = sexChar == 'M' ? 'M' : (sexChar == 'F' ? 'F' : 'X');

    final doeRaw = line2.substring(21, 27);
    final doeCheck = line2[27];
    final doeValid = verifyMrzCheckDigit(doeRaw, doeCheck);
    final expiryDate = formatMrzDate(doeRaw);

    final compositeValid = docNumberValid && dobValid && doeValid;

    return {
      'document_type': 'passport',
      'document_number': docNumber,
      'surname': surname,
      'given_names': givenNames,
      'full_name': fullName,
      'nationality': nationality,
      'issuing_country': issuingCountry,
      'birth_date': birthDate,
      'gender': sex,
      'expiry_date': expiryDate,
      'mrz_valid': compositeValid,
      'mrz_lines': [line1, line2],
      'confidence_score': compositeValid ? 0.98 : 0.85,
    };
  }

  /// Parses ICAO 9303 TD1 standard (ID Cards / Nova CIN - 3 lines x 30 chars).
  static Map<String, dynamic> parseTd1(String rawLine1, String rawLine2, String rawLine3) {
    var line1 = rawLine1.trim().toUpperCase().replaceAll(' ', '').padRight(30, '<');
    var line2 = rawLine2.trim().toUpperCase().replaceAll(' ', '').padRight(30, '<');
    var line3 = rawLine3.trim().toUpperCase().replaceAll(' ', '').padRight(30, '<');

    final issuingCountry = line1.substring(2, 5).replaceAll('<', '');
    final docNumber = line1.substring(5, 14).replaceAll('<', '');
    final docNumberValid = verifyMrzCheckDigit(line1.substring(5, 14), line1[14]);

    final dobRaw = line2.substring(0, 6);
    final dobValid = verifyMrzCheckDigit(dobRaw, line2[6]);
    final birthDate = formatMrzDate(dobRaw);

    final sexChar = line2[7];
    final sex = sexChar == 'M' ? 'M' : (sexChar == 'F' ? 'F' : 'X');

    final doeRaw = line2.substring(8, 14);
    final doeValid = verifyMrzCheckDigit(doeRaw, line2[14]);
    final expiryDate = formatMrzDate(doeRaw);

    final nationality = line2.substring(15, 18).replaceAll('<', '');

    final nameTokens = line3.split('<<').where((t) => t.isNotEmpty).toList();
    final surname = nameTokens.isNotEmpty ? nameTokens[0].replaceAll('<', ' ').trim() : '';
    final givenNames = nameTokens.length > 1 ? nameTokens[1].replaceAll('<', ' ').trim() : '';
    final fullName = givenNames.isNotEmpty ? '$givenNames $surname' : surname;

    final compositeValid = docNumberValid && dobValid && doeValid;

    return {
      'document_type': 'cin',
      'document_number': docNumber,
      'surname': surname,
      'given_names': givenNames,
      'full_name': fullName,
      'nationality': nationality,
      'issuing_country': issuingCountry,
      'birth_date': birthDate,
      'gender': sex,
      'expiry_date': expiryDate,
      'mrz_valid': compositeValid,
      'mrz_lines': [line1, line2, line3],
      'confidence_score': compositeValid ? 0.98 : 0.85,
    };
  }

  /// Scans raw OCR text for MRZ lines and parses them if detected.
  static Map<String, dynamic>? findAndParseMrz(String text) {
    final cleanLines = text
        .split('\n')
        .map((l) => l.trim().replaceAll(' ', ''))
        .where((l) => l.length >= 28 && l.contains('<'))
        .toList();

    // Check TD3 (2 lines ~44 chars)
    for (var i = 0; i < cleanLines.length - 1; i++) {
      final l1 = cleanLines[i];
      final l2 = cleanLines[i + 1];
      if (l1.length >= 40 && l2.length >= 40 && l1.startsWith('P<')) {
        return parseTd3(l1, l2);
      }
    }

    // Check TD1 (3 lines ~30 chars)
    for (var i = 0; i < cleanLines.length - 2; i++) {
      final l1 = cleanLines[i];
      final l2 = cleanLines[i + 1];
      final l3 = cleanLines[i + 2];
      if (l1.length >= 28 && l2.length >= 28 && l3.length >= 28 && (l1.startsWith('I<') || l1.startsWith('ID') || l1.startsWith('A<'))) {
        return parseTd1(l1, l2, l3);
      }
    }

    return null;
  }

  // --- 4. CNH (Carteira Nacional de Habilitação) Parser ---

  static bool _isValidPersonName(String text) {
    if (text.isEmpty || text.length < 4) return false;
    final norm = normalizeAccents(text).toUpperCase();
    
    final stopWords = ['CARTEIRA', 'MINISTERIO', 'REPUBLICA', 'DEPARTAMENTO', 'HABILITACAO', 'NACIONAL', 'TRANSITO', 'DETRAN', 'SECRETARIA', 'IDENTIDADE', 'CPF', 'NOME', 'FILIACAO', 'ASSINATURA', 'DATA', 'LOCAL', 'EMISSOR', 'VALIDADE', 'CATEGORIA', 'RENACH', 'DOC'];
    for (final word in stopWords) {
      if (norm == word || norm.contains('$word:')) return false;
    }
    
    if (!RegExp(r'[A-Za-z]').hasMatch(norm)) return false;
    
    // Reject if it has more than 2 digits (likely a document number, CPF, or date)
    if (RegExp(r'\d').allMatches(text).length > 2) return false;
    
    return true;
  }

  static Map<String, String?> _assignChronologicalDates(List<String> rawDates, {bool isCnh = false}) {
    if (rawDates.isEmpty) return {};

    final parsedDates = <DateTime, String>{};
    for (final d in rawDates) {
      try {
        final parts = d.split('/');
        final dt = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
        parsedDates[dt] = d;
      } catch (_) {}
    }

    final sortedKeys = parsedDates.keys.toList()..sort();
    
    if (sortedKeys.isEmpty) return {'birth': rawDates.isNotEmpty ? rawDates[0] : null};
    if (sortedKeys.length == 1) return {'birth': parsedDates[sortedKeys.first]};
    
    if (sortedKeys.length == 2) {
      if (isCnh) {
         return {'birth': parsedDates[sortedKeys.first], 'expiry': parsedDates[sortedKeys.last]};
      } else {
         return {'birth': parsedDates[sortedKeys.first], 'issue': parsedDates[sortedKeys.last]};
      }
    }
    
    return {
       'birth': parsedDates[sortedKeys.first],
       'first_license': parsedDates[sortedKeys[1]],
       'issue': parsedDates[sortedKeys[1]], // For RG it might have 3 dates? Rare, but middle is issue.
       'expiry': parsedDates[sortedKeys.last]
    };
  }

  static Map<String, dynamic> parseCnh(String rawText) {
    final norm = normalizeAccents(rawText);
    final cpfResult = extractCpf(rawText);

    // CNH Registration Number (11 consecutive digits)
    String? docNumber;
    final numMatch = RegExp(r'(?:N[º°\.]?\s*REGISTRO|REGISTRO)[\s:]*([0-9]{9,11})').firstMatch(norm);
    if (numMatch != null) {
      docNumber = numMatch.group(1);
    } else {
      final standalone11 = RegExp(r'\b(\d{11})\b').allMatches(norm);
      for (final m in standalone11) {
        final val = m.group(1)!;
        if (cpfResult.cpf == null || !cpfResult.cpf!.contains(val)) {
          docNumber = val;
          break;
        }
      }
    }

    // CNH Category
    String? category;
    final catMatch = RegExp(r'(?:CAT|CATEGORIA|PERMISSAO)[\s\.:]*(ACC|AB|A|B|C|D|E)\b').firstMatch(norm);
    if (catMatch != null) {
      category = catMatch.group(1);
    } else {
      for (final c in ['AB', 'ACC', 'A', 'B', 'C', 'D', 'E']) {
        if (RegExp('\\bCAT[\\.:\\s]*$c\\b').hasMatch(norm)) {
          category = c;
          break;
        }
      }
    }

    // RENACH
    String? renach;
    final renachMatch = RegExp(r'\b([A-Z]{2}\d{9})\b').firstMatch(norm);
    if (renachMatch != null) {
      renach = renachMatch.group(1);
    }

    // Dates
    final dates = RegExp(r'\b(\d{2}/\d{2}/\d{4})\b').allMatches(rawText).map((m) => m.group(1)!).toList();
    final sortedDates = _assignChronologicalDates(dates, isCnh: true);
    String? birthDate = sortedDates['birth'];
    String? expiryDate = sortedDates['expiry'];
    String? firstLicenseDate = sortedDates['first_license'];

    // Name Extraction
    String? fullName;
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    for (var i = 0; i < lines.length; i++) {
      final lineNorm = normalizeAccents(lines[i]);
      if (lineNorm.contains('NOME') && !lineNorm.contains('NOME DO')) { // NOME DO usually goes with NOME DO PAI/MAE etc.
        // Try the same line if it's NOME: Name or NOME Name
        if (lines[i].contains(':') && lines[i].split(':').length > 1 && lines[i].split(':')[1].trim().isNotEmpty) {
          final cand = lines[i].substring(lines[i].indexOf(':') + 1).trim();
          if (_isValidPersonName(cand)) {
            fullName = cand;
          }
        } else if (lineNorm.length > 5 && lineNorm.startsWith('NOME ')) {
          final cand = lines[i].substring(5).trim();
          if (_isValidPersonName(cand)) {
            fullName = cand;
          }
        }
        
        // Scan the next few lines for a valid name
        if (fullName == null) {
          for (var j = i + 1; j < lines.length && j < i + 5; j++) {
            if (_isValidPersonName(lines[j])) {
              fullName = lines[j].trim();
              break;
            }
          }
        }
        break;
      }
    }

    // Clean up name if it contains stop words
    if (fullName != null) {
      fullName = fullName.replaceAll(RegExp(r'[0-9<>/\\_]'), '').trim();
    }

    // User ID generation could go here if we had crypto imported

    return {
      'document_type': 'cnh',
      'document_number': docNumber,
      'cpf': cpfResult.cpf,
      'cpf_valid': cpfResult.isValid,
      'full_name': fullName,
      'birth_date': birthDate,
      'issuing_organ': 'DETRAN',
      'cnh_category': category,
      'cnh_renach': renach,
      'expiry_date': expiryDate,
      'cnh_first_license_date': firstLicenseDate,
      'confidence_score': (cpfResult.isValid && docNumber != null) ? 0.95 : 0.75,
    };
  }

  // --- 5. RG & Nova CIN Parser ---

  static Map<String, dynamic> parseRg(String rawText, {bool isCin = false}) {
    final norm = normalizeAccents(rawText);
    final cpfResult = extractCpf(rawText);

    // Document Number (RG)
    String? docNumber;
    final rgMatch = RegExp(r'\b(\d{1,2}\.?\d{3}\.?\d{3}-?[0-9Xx])\b').firstMatch(rawText);
    if (rgMatch != null) {
      docNumber = rgMatch.group(1);
    } else {
      final genericNum = RegExp(r'(?:REGISTRO GERAL|RG|NUMERO)[\s:]*([0-9\.\-Xx]{6,14})').firstMatch(norm);
      if (genericNum != null) {
        docNumber = genericNum.group(1);
      }
    }

    // Dates
    final dates = RegExp(r'\b(\d{2}/\d{2}/\d{4})\b').allMatches(rawText).map((m) => m.group(1)!).toList();
    final sortedDates = _assignChronologicalDates(dates, isCnh: false);
    String? birthDate = sortedDates['birth'];
    String? issuingDate = sortedDates['issue'];

    // State & Organ
    String? issuingState;
    for (final uf in brazilianStates) {
      if (RegExp('\\b$uf\\b').hasMatch(norm)) {
        issuingState = uf;
        break;
      }
    }

    String? issuingOrgan;
    for (final organ in issuingOrgans) {
      if (norm.contains(organ)) {
        issuingOrgan = organ;
        break;
      }
    }

    // Name Extraction
    String? fullName;
    final lines = rawText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    for (var i = 0; i < lines.length; i++) {
      final lNorm = normalizeAccents(lines[i]);
      if (lNorm.contains('NOME') && !lNorm.contains('NOME DO')) {
        if (lines[i].contains(':') && lines[i].split(':').length > 1 && lines[i].split(':')[1].trim().isNotEmpty) {
          final cand = lines[i].substring(lines[i].indexOf(':') + 1).trim();
          if (_isValidPersonName(cand)) fullName = cand;
        } else if (lNorm.length > 5 && lNorm.startsWith('NOME ')) {
          final cand = lines[i].substring(5).trim();
          if (_isValidPersonName(cand)) fullName = cand;
        }
        
        if (fullName == null) {
          for (var j = i + 1; j < lines.length && j < i + 5; j++) {
            if (_isValidPersonName(lines[j])) {
              fullName = lines[j].trim();
              break;
            }
          }
        }
        break;
      }
    }

    // User ID generation could go here if we had crypto imported

    return {
      'document_type': isCin ? 'cin' : 'rg',
      'document_number': docNumber ?? (isCin ? cpfResult.cpf : null),
      'cpf': cpfResult.cpf,
      'cpf_valid': cpfResult.isValid,
      'full_name': fullName,
      'birth_date': birthDate,
      'issuing_organ': issuingOrgan ?? 'SSP',
      'issuing_state': issuingState,
      'issuing_date': issuingDate,
      'confidence_score': (cpfResult.isValid || docNumber != null) ? 0.92 : 0.70,
    };
  }

  // --- 6. Unified Auto-Classifier & Parser ---

  /// Parses any document text with automatic classification.
  static ScannedDocumentData parse(String rawText, {String docHint = 'auto', bool isBarcode = false}) {
    if (rawText.trim().isEmpty) {
      throw Exception('Nenhum texto extraído.');
    }
    final mrzData = findAndParseMrz(rawText);
    if (mrzData != null && (docHint == 'auto' || docHint == 'passport' || docHint == 'cin')) {
      return ScannedDocumentData.fromOcrJson(mrzData, rawText: rawText);
    }

    final norm = normalizeAccents(rawText);

    // 2. Classify document type
    var detectedType = docHint;
    if (detectedType == 'auto') {
      if (norm.contains('HABILITACAO') || norm.contains('CNH') || norm.contains('DETRAN') || norm.contains('RENACH') || norm.contains('CATEGORIA')) {
        detectedType = 'cnh';
      } else if (norm.contains('CARTEIRA DE IDENTIDADE NACIONAL') || norm.contains('NOVA CIN') || norm.contains('IDENTIDADE NACIONAL')) {
        detectedType = 'cin';
      } else if (norm.contains('PASSAPORTE') || norm.contains('PASSPORT') || norm.contains('P<BRA') || norm.contains('P<')) {
        detectedType = 'passport';
      } else if (norm.contains('REGISTRO GERAL') || norm.contains('SSP') || norm.contains('SECRETARIA DE SEGURANCA') || norm.contains('IDENTIDADE')) {
        detectedType = 'rg';
      } else {
        detectedType = 'rg';
      }
    }

    // 3. Delegate to specific parser
    Map<String, dynamic> result;
    switch (detectedType) {
      case 'cnh':
        result = parseCnh(rawText);
        break;
      case 'cin':
        result = parseRg(rawText, isCin: true);
        break;
      case 'passport':
        result = mrzData ?? parseRg(rawText);
        break;
      case 'cpf':
        final cpfRes = extractCpf(rawText);
        result = {
          'document_type': 'cpf',
          'cpf': cpfRes.cpf,
          'cpf_valid': cpfRes.isValid,
          'confidence_score': cpfRes.isValid ? 0.99 : 0.5,
        };
        break;
      default:
        result = parseRg(rawText);
        detectedType = 'rg';
    }

    // 4. Severe Validation Gate (Anti-Fraud & Quality)
    final upperNorm = norm.toUpperCase();
    
    if (detectedType == 'cnh') {
      if (result['cpf_valid'] == false) {
        throw Exception('SEVERE_VALIDATION_ERROR: CPF inválido. Reprovado pelo dígito verificador Modulus 11.');
      }
      if (!isBarcode) {
        int kwMatches = ['HABILITACAO', 'DETRAN', 'RENACH', 'CATEGORIA', 'REPUBLICA', 'NACIONAL', 'TRANSITO'].where((kw) => upperNorm.contains(kw)).length;
        if (kwMatches < 2) {
          throw Exception('SEVERE_VALIDATION_ERROR: Formato não reconhecido. Palavras-chave oficiais da CNH ausentes.');
        }
      }
    } else if (detectedType == 'cin') {
      if (result['cpf_valid'] == false) {
        throw Exception('SEVERE_VALIDATION_ERROR: CPF inválido. Reprovado pelo dígito verificador Modulus 11.');
      }
    } else if (detectedType == 'rg') {
      if (!isBarcode) {
        int kwMatches = ['REGISTRO', 'GERAL', 'SSP', 'SECRETARIA', 'SEGURANCA', 'REPUBLICA', 'IDENTIDADE', 'ESTADO', 'VALIDA'].where((kw) => upperNorm.contains(kw)).length;
        if (kwMatches < 2) {
          throw Exception('SEVERE_VALIDATION_ERROR: Formato não reconhecido. Palavras-chave oficiais do RG ausentes.');
        }
      }
    } else if (detectedType == 'passport') {
      if (mrzData == null) {
        throw Exception('SEVERE_VALIDATION_ERROR: Falha na validação do MRZ. O algoritmo de checksum 7-3-1 rejeitou as zonas do passaporte.');
      }
    }

    return ScannedDocumentData.fromOcrJson(result, rawText: rawText);
  }
}
