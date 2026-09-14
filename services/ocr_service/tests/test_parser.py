import unittest
from services.ocr_service.app.parser import MultiDocumentParser
from services.ocr_service.app.mrz_parser import ICAO9303MRZParser

class TestMultiDocumentParser(unittest.TestCase):

    # 1. CPF Validation
    def test_cpf_validation(self):
        self.assertTrue(MultiDocumentParser.validate_cpf("52998224725"))
        self.assertTrue(MultiDocumentParser.validate_cpf("529.982.247-25"))
        self.assertFalse(MultiDocumentParser.validate_cpf("123456789"))
        self.assertFalse(MultiDocumentParser.validate_cpf("111.111.111-11"))
        self.assertFalse(MultiDocumentParser.validate_cpf("52998224726"))

    # 2. Traditional RG
    def test_rg_parsing(self):
        text_sample = """
        REPÚBLICA FEDERATIVA DO BRASIL
        REGISTRO GERAL 12.345.678-9
        SSP SP
        CARLOS EDUARDO DA SILVA
        FILIAÇÃO
        MARIA EDUARDA DA SILVA
        JOSE ANTONIO DA SILVA
        NATURALIDADE SAO PAULO - SP
        DATA DE NASCIMENTO 15/05/1990
        CPF 529.982.247-25
        """
        data = MultiDocumentParser.parse(text_sample, doc_hint="rg")
        self.assertEqual(data.document_type, "rg")
        self.assertEqual(data.cpf, "529.982.247-25")
        self.assertTrue(data.cpf_valid)
        self.assertIn("12.345.678", data.document_number or "")
        self.assertEqual(data.issuing_organ, "SSP")
        self.assertEqual(data.issuing_state, "SP")
        self.assertEqual(data.birth_date, "15/05/1990")

    # 3. Brazilian CNH
    def test_cnh_parsing(self):
        cnh_sample = """
        REPÚBLICA FEDERATIVA DO BRASIL
        MINISTÉRIO DOS TRANSPORTES
        DEPARTAMENTO NACIONAL DE TRÂNSITO
        CARTEIRA NACIONAL DE HABILITAÇÃO
        NOME: RODRIGO ALBUQUERQUE MARTINS
        DOC. IDENTIDADE: 25.890.123-4 SSP SP
        CPF: 529.982.247-25
        DATA NASCIMENTO: 22/04/1988
        FILIAÇÃO: HELENA MARTINS
        Nº REGISTRO: 04891238910
        VALIDADE: 14/08/2028
        1ª HABILITAÇÃO: 10/05/2006
        CAT. HAB.: AB
        RENACH: SP912839120
        """
        data = MultiDocumentParser.parse(cnh_sample, doc_hint="auto")
        self.assertEqual(data.document_type, "cnh")
        self.assertEqual(data.cpf, "529.982.247-25")
        self.assertTrue(data.cpf_valid)
        self.assertEqual(data.cnh_category, "AB")
        self.assertEqual(data.cnh_renach, "SP912839120")
        self.assertEqual(data.issuing_organ, "DETRAN")

    # 4. Passport ICAO 9303 MRZ Engine (TD3)
    def test_passport_mrz_td3(self):
        line1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
        line2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"
        
        parsed = ICAO9303MRZParser.parse_td3(line1, line2)
        
        self.assertEqual(parsed["format"], "TD3")
        self.assertEqual(parsed["document_type"], "passport")
        self.assertEqual(parsed["document_number"], "L898902C3")
        self.assertTrue(parsed["document_number_valid"])
        self.assertEqual(parsed["surname"], "ERIKSSON")
        self.assertEqual(parsed["given_names"], "ANNA MARIA")
        self.assertEqual(parsed["nationality"], "UTO")
        self.assertEqual(parsed["birth_date"], "12/08/1974")
        self.assertTrue(parsed["birth_date_valid"])
        self.assertEqual(parsed["sex"], "F")
        self.assertEqual(parsed["expiry_date"], "15/04/2012")
        self.assertTrue(parsed["expiry_date_valid"])
        self.assertTrue(parsed["mrz_valid"])

    # 5. Checksum verification logic
    def test_mrz_checksum_calculation(self):
        # Doc number check digit for L898902C3 -> 6
        # L=21, 8, 9, 8, 9, 0, 2, C=12, 3
        # Weights: 7, 3, 1, 7, 3, 1, 7, 3, 1
        expected = ICAO9303MRZParser.calculate_check_digit("L898902C3")
        self.assertEqual(expected, 6)

    # 6. Auto-classification
    def test_auto_classification(self):
        passport_text = "PASSPORT\n\nP<BRACOSTA<<FERNANDA<<<<<<<<<<<<<<<<<<<<<<<<\nCS89123456BRA9207184F3001018<<<<<<<<<<<<<<04"
        data = MultiDocumentParser.parse(passport_text, doc_hint="auto")
        self.assertEqual(data.document_type, "passport")
        self.assertEqual(data.nationality, "BRA")
        self.assertEqual(data.surname, "COSTA")

if __name__ == "__main__":
    unittest.main()
