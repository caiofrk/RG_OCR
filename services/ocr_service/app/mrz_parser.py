import re
from typing import Optional, Dict, Any, List

class ICAO9303MRZParser:
    """
    Parser for ICAO Doc 9303 Machine Readable Zones (MRZ).
    Supports:
    - TD3 (2 lines x 44 characters) - Standard Passports
    - TD1 (3 lines x 30 characters) - ID Cards & New Brazilian CIN
    - TD2 (2 lines x 36 characters) - Visas / IDs
    """

    WEIGHTS = [7, 3, 1]

    @classmethod
    def calculate_check_digit(cls, text: str) -> int:
        """
        Calculates ICAO 9303 check digit using the 7-3-1 weighting algorithm.
        Characters: 0-9 = 0-9, A-Z = 10-35, '<' = 0.
        """
        total = 0
        for i, char in enumerate(text):
            weight = cls.WEIGHTS[i % 3]
            if char.isdigit():
                val = int(char)
            elif 'A' <= char <= 'Z':
                val = ord(char) - ord('A') + 10
            elif char == '<':
                val = 0
            else:
                val = 0
            total += val * weight
        return total % 10

    @classmethod
    def verify_check_digit(cls, text: str, check_digit_char: str) -> bool:
        """Verifies if the calculated check digit matches the expected check digit."""
        if not check_digit_char or not check_digit_char.isdigit():
            return False
        expected = int(check_digit_char)
        return cls.calculate_check_digit(text) == expected

    @staticmethod
    def format_date(yymmdd: str) -> Optional[str]:
        """Converts YYMMDD into YYYY-MM-DD or DD/MM/YYYY with century inference."""
        if len(yymmdd) != 6 or not yymmdd.isdigit():
            return None
        yy = int(yymmdd[0:2])
        mm = yymmdd[2:4]
        dd = yymmdd[4:6]
        # Year <= 40 implies 2000s, > 40 implies 1900s
        century = 2000 if yy <= 40 else 1900
        yyyy = century + yy
        return f"{dd}/{mm}/{yyyy}"

    @classmethod
    def parse_td3(cls, line1: str, line2: str) -> Dict[str, Any]:
        """
        Parses TD3 (Passport - 2 lines of 44 characters).
        """
        line1 = line1.strip().upper().replace(" ", "")
        line2 = line2.strip().upper().replace(" ", "")

        # Clean line lengths
        if len(line1) < 44:
            line1 = line1.ljust(44, '<')
        if len(line2) < 44:
            line2 = line2.ljust(44, '<')

        # Line 1: P<ISSNAME<<SURNAME<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
        doc_type = line1[0:2].replace('<', '')
        issuing_country = line1[2:5].replace('<', '')
        name_part = line1[5:44]
        name_tokens = [t for t in name_part.split('<<') if t]
        surname = name_tokens[0].replace('<', ' ').strip() if len(name_tokens) > 0 else ""
        given_names = name_tokens[1].replace('<', ' ').strip() if len(name_tokens) > 1 else ""
        full_name = f"{given_names} {surname}".strip() if given_names else surname

        # Line 2: DOCNUM9CK_NAT_DOB6CK_SEX_DOE6CK_OPTIONAL14CK_COMPOSITE
        doc_number = line2[0:9].replace('<', '')
        doc_number_check = line2[9]
        doc_number_valid = cls.verify_check_digit(line2[0:9], doc_number_check)

        nationality = line2[10:13].replace('<', '')
        
        dob_raw = line2[13:19]
        dob_check = line2[19]
        dob_valid = cls.verify_check_digit(dob_raw, dob_check)
        birth_date = cls.format_date(dob_raw)

        sex_char = line2[20]
        sex = "M" if sex_char == 'M' else ("F" if sex_char == 'F' else "Unspecified")

        doe_raw = line2[21:27]
        doe_check = line2[27]
        doe_valid = cls.verify_check_digit(doe_raw, doe_check)
        expiry_date = cls.format_date(doe_raw)

        optional_data = line2[28:42].replace('<', '')
        optional_check = line2[42]

        composite_check = line2[43]
        # Composite checksum covers doc number + check + dob + check + doe + check + optional + check
        composite_data = line2[0:10] + line2[13:20] + line2[21:43]
        composite_valid = cls.verify_check_digit(composite_data, composite_check)

        return {
            "format": "TD3",
            "document_type": "passport",
            "document_code": doc_type,
            "issuing_country": issuing_country,
            "document_number": doc_number,
            "document_number_valid": doc_number_valid,
            "surname": surname,
            "given_names": given_names,
            "full_name": full_name,
            "nationality": nationality,
            "birth_date": birth_date,
            "birth_date_valid": dob_valid,
            "sex": sex,
            "expiry_date": expiry_date,
            "expiry_date_valid": doe_valid,
            "optional_data": optional_data,
            "mrz_valid": doc_number_valid and dob_valid and doe_valid,
            "composite_valid": composite_valid,
            "confidence_score": 0.98 if (doc_number_valid and dob_valid) else 0.75
        }

    @classmethod
    def parse_td1(cls, line1: str, line2: str, line3: str) -> Dict[str, Any]:
        """
        Parses TD1 (ID Card / CIN - 3 lines of 30 characters).
        """
        line1 = line1.strip().upper().ljust(30, '<')
        line2 = line2.strip().upper().ljust(30, '<')
        line3 = line3.strip().upper().ljust(30, '<')

        # Line 1: I<BRA1234567897<<<<<<<<<<<<<<<
        doc_code = line1[0:2].replace('<', '')
        issuing_country = line1[2:5].replace('<', '')
        doc_number = line1[5:14].replace('<', '')
        doc_number_check = line1[14]
        doc_number_valid = cls.verify_check_digit(line1[5:14], doc_number_check)

        # Line 2: 9005155M2508208BRA<<<<<<<<<<<0
        dob_raw = line2[0:6]
        dob_check = line2[6]
        dob_valid = cls.verify_check_digit(dob_raw, dob_check)
        birth_date = cls.format_date(dob_raw)

        sex_char = line2[7]
        sex = "M" if sex_char == 'M' else ("F" if sex_char == 'F' else "Unspecified")

        doe_raw = line2[8:14]
        doe_check = line2[14]
        doe_valid = cls.verify_check_digit(doe_raw, doe_check)
        expiry_date = cls.format_date(doe_raw)

        nationality = line2[15:18].replace('<', '')

        # Line 3: SURNAME<<GIVEN<NAMES<<<<<<<<<<
        name_tokens = [t for t in line3.split('<<') if t]
        surname = name_tokens[0].replace('<', ' ').strip() if len(name_tokens) > 0 else ""
        given_names = name_tokens[1].replace('<', ' ').strip() if len(name_tokens) > 1 else ""
        full_name = f"{given_names} {surname}".strip() if given_names else surname

        return {
            "format": "TD1",
            "document_type": "cin" if issuing_country == "BRA" else "id_card",
            "document_code": doc_code,
            "issuing_country": issuing_country,
            "document_number": doc_number,
            "document_number_valid": doc_number_valid,
            "surname": surname,
            "given_names": given_names,
            "full_name": full_name,
            "nationality": nationality,
            "birth_date": birth_date,
            "birth_date_valid": dob_valid,
            "sex": sex,
            "expiry_date": expiry_date,
            "expiry_date_valid": doe_valid,
            "mrz_valid": doc_number_valid and dob_valid,
            "confidence_score": 0.95 if (doc_number_valid and dob_valid) else 0.70
        }

    @classmethod
    def find_and_parse_mrz(cls, raw_text: str) -> Optional[Dict[str, Any]]:
        """
        Scans any OCR text output to locate candidate MRZ lines and parses them.
        """
        lines = [line.strip().replace(" ", "") for line in raw_text.split('\n')]
        # Filter lines with typical MRZ characters (letters, numbers, '<')
        mrz_candidates = [
            l for l in lines 
            if len(l) >= 28 and sum(1 for c in l if c == '<') >= 3
        ]

        # Check for TD3 (2 lines x 44)
        td3_lines = [l for l in mrz_candidates if 40 <= len(l) <= 46]
        if len(td3_lines) >= 2:
            return cls.parse_td3(td3_lines[-2], td3_lines[-1])

        # Check for TD1 (3 lines x 30)
        td1_lines = [l for l in mrz_candidates if 28 <= len(l) <= 34]
        if len(td1_lines) >= 3:
            return cls.parse_td1(td1_lines[-3], td1_lines[-2], td1_lines[-1])

        return None
