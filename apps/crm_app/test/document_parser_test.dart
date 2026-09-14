import 'package:flutter_test/flutter_test.dart';
import 'package:crm_app/core/services/document_parser_service.dart';

void main() {
  group('DocumentParserService Tests', () {
    test('CPF Modulus 11 Validation', () {
      // Valid CPFs
      expect(DocumentParserService.validateCpf('275.153.968-81'), isTrue);
      expect(DocumentParserService.validateCpf('529.982.247-25'), isTrue);

      // Invalid CPFs (all identical digits or incorrect checksum)
      expect(DocumentParserService.validateCpf('111.111.111-11'), isFalse);
      expect(DocumentParserService.validateCpf('000.000.000-00'), isFalse);
      expect(DocumentParserService.validateCpf('123.456.789-00'), isFalse);
      expect(DocumentParserService.validateCpf(''), isFalse);
      expect(DocumentParserService.validateCpf(null), isFalse);
    });

    test('ICAO Doc 9303 MRZ 7-3-1 Weighting Check Digit', () {
      // Document Number "L898902C3" with check digit "6"
      // L=21, 8=8, 9=9, 8=8, 9=9, 0=0, 2=2, C=12, 3=3
      expect(DocumentParserService.calculateMrzCheckDigit('L898902C3'), equals(6));
      expect(DocumentParserService.verifyMrzCheckDigit('L898902C3', '6'), isTrue);
      expect(DocumentParserService.verifyMrzCheckDigit('L898902C3', '7'), isFalse);

      // Date of Birth "740812" check digit "2"
      expect(DocumentParserService.calculateMrzCheckDigit('740812'), equals(2));
      expect(DocumentParserService.verifyMrzCheckDigit('740812', '2'), isTrue);
    });

    test('Passport TD3 MRZ Parsing', () {
      const line1 = 'P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<';
      const line2 = 'L898902C36UTO7408122F1204159ZE184226B<<<<<10';

      final res = DocumentParserService.parseTd3(line1, line2);

      expect(res['document_type'], equals('passport'));
      expect(res['surname'], equals('ERIKSSON'));
      expect(res['given_names'], equals('ANNA MARIA'));
      expect(res['full_name'], equals('ANNA MARIA ERIKSSON'));
      expect(res['document_number'], equals('L898902C3'));
      expect(res['nationality'], equals('UTO'));
      expect(res['gender'], equals('F'));
      expect(res['birth_date'], equals('12/08/1974'));
      expect(res['mrz_valid'], isTrue);
    });

    test('CNH Text Parsing and Checksum Verification', () {
      const cnhText = '''
REPÚBLICA FEDERATIVA DO BRASIL
DEPARTAMENTO NACIONAL DE TRÂNSITO
CARTEIRA NACIONAL DE HABILITAÇÃO
NOME: FABIANO LUIS DE BRITO
DOC IDENTIDADE / ORG EMISSOR UF: 29047879 SSP SP
CPF: 275.153.968-81
DATA NASCIMENTO: 19/11/1979
FILIACAO: ELMA BRITO DE MOURA
PERMISSAO: ACC
VALIDADE: 03/08/2031
1ª HABILITACAO: 20/02/1998
N REGISTRO: 00748806880
RENACH: SP912839120
''';

      final doc = DocumentParserService.parse(cnhText);

      expect(doc.documentType, equals('cnh'));
      expect(doc.cpf, equals('275.153.968-81'));
      expect(doc.cpfValid, isTrue);
      expect(doc.documentNumber, equals('00748806880'));
      expect(doc.fullName, contains('FABIANO LUIS DE BRITO'));
      expect(doc.cnhCategory, equals('ACC'));
      expect(doc.cnhRenach, equals('SP912839120'));
      expect(doc.birthDate, equals('19/11/1979'));
    });

    test('RG Traditional Text Parsing', () {
      const rgText = '''
REPÚBLICA FEDERATIVA DO BRASIL
SECRETARIA DE SEGURANÇA PÚBLICA
REGISTRO GERAL: 38.452.190-8 SSP SP
NOME: MARIANA RIBEIRO COSTA
FILIACAO:
TERESA RIBEIRO COSTA
ANTONIO CARLOS COSTA
NATURALIDADE: SAO PAULO - SP
DATA DE NASCIMENTO: 18/07/1992
CPF: 529.982.247-25
''';

      final doc = DocumentParserService.parse(rgText);

      expect(doc.documentType, equals('rg'));
      expect(doc.documentNumber, equals('38.452.190-8'));
      expect(doc.cpf, equals('529.982.247-25'));
      expect(doc.cpfValid, isTrue);
      expect(doc.fullName, equals('MARIANA RIBEIRO COSTA'));
      expect(doc.motherName, equals('TERESA RIBEIRO COSTA'));
      expect(doc.fatherName, equals('ANTONIO CARLOS COSTA'));
      expect(doc.issuingOrgan, equals('SSP'));
      expect(doc.issuingState, equals('SP'));
      expect(doc.birthDate, equals('18/07/1992'));
    });
  });
}
