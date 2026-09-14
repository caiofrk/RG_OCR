import re
import unicodedata
from typing import Optional, Dict, Any, List
from .schemas import ExtractedDocumentData
from .mrz_parser import ICAO9303MRZParser

BRAZILIAN_STATES = {
    "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA",
    "MT", "MS", "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN",
    "RS", "RO", "RR", "SC", "SP", "SE", "TO"
}

ISSUING_ORGANS = [
    "SSP", "DETRAN", "PC", "IFP", "ITEP", "SESP", "SPTC", "DIC",
    "POLICIA CIVIL", "POLICIA FEDERAL", "SECRETARIA DE SEGURANCA",
    "MINISTERIO DA DEFESA", "EXERCITO BRASILEIRO", "MARINHA DO BRASIL"
]

CNH_CATEGORIES = ["A", "B", "AB", "C", "D", "E", "ACC"]

STOPWORDS_DOC = {
    "REPUBLICA", "FEDERATIVA", "BRASIL", "REGISTRO", "GERAL", "IDENTIDADE",
    "CARTEIRA", "NACIONAL", "HABILITACAO", "VALIDA", "TODO", "TERRITORIO",
    "SECRETARIA", "SEGURANCA", "PUBLICA", "INSTITUTO", "IDENTIFICACAO",
    "FILIACAO", "NATURALIDADE", "DATA", "NASCIMENTO", "EXPEDICAO", "VIA",
    "DOC", "ORIGEM", "LEI", "ASSINATURA", "DIRETOR", "POLEGAR", "DIREITO",
    "MINISTERIO", "JUSTICA", "DEPARTAMENTO", "TRANSITO", "CONTRAN", "DENATRAN",
    "NOME", "CPF", "VALIDADE", "EMISSOR", "PERMISSAO", "CATEGORIA"
}

class MultiDocumentParser:
    """
    Unified parser for Brazilian and International Identity Documents:
    - RG (Registro Geral tradicional)
    - Nova CIN (Carteira de Identidade Nacional)
    - CNH (Carteira Nacional de Habilitação)
    - Passaporte (Passport with ICAO 9303 MRZ Engine)
    - CPF (Cadastro de Pessoas Físicas)
    """

    @staticmethod
    def normalize_accents(text: str) -> str:
        """Strips accents and standardizes to uppercase for robust matching."""
        if not text:
            return ""
        nfd = unicodedata.normalize("NFD", text)
        return "".join(c for c in nfd if unicodedata.category(c) != "Mn").upper()

    @staticmethod
    def validate_cpf(raw_cpf: str) -> bool:
        """Validates Brazilian CPF using modulus 11 checksum algorithm."""
        if not raw_cpf:
            return False
        digits = re.sub(r"\D", "", raw_cpf)
        if len(digits) != 11:
            return False
        if digits == digits[0] * 11:
            return False

        sum_1 = sum(int(digits[i]) * (10 - i) for i in range(9))
        remainder_1 = (sum_1 * 10) % 11
        check_digit_1 = 0 if remainder_1 >= 10 else remainder_1
        if int(digits[9]) != check_digit_1:
            return False

        sum_2 = sum(int(digits[i]) * (11 - i) for i in range(10))
        remainder_2 = (sum_2 * 10) % 11
        check_digit_2 = 0 if remainder_2 >= 10 else remainder_2
        if int(digits[10]) != check_digit_2:
            return False

        return True

    @staticmethod
    def format_cpf(raw_cpf: str) -> Optional[str]:
        digits = re.sub(r"\D", "", raw_cpf)
        if len(digits) == 11:
            return f"{digits[0:3]}.{digits[3:6]}.{digits[6:9]}-{digits[9:11]}"
        return None

    @staticmethod
    def format_rg(raw_rg: str) -> str:
        clean = re.sub(r"[^\dXx]", "", raw_rg).upper()
        if len(clean) == 9:
            return f"{clean[0:2]}.{clean[2:5]}.{clean[5:8]}-{clean[8]}"
        elif len(clean) == 8:
            return f"{clean[0:1]}.{clean[1:4]}.{clean[4:7]}-{clean[7]}"
        return raw_rg.strip().upper()

    @classmethod
    def extract_cpf(cls, text: str) -> tuple[Optional[str], bool]:
        matches = re.findall(r"\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b", text)
        for candidate in matches:
            cleaned = re.sub(r"\D", "", candidate)
            if cls.validate_cpf(cleaned):
                return cls.format_cpf(cleaned), True
        if matches:
            return cls.format_cpf(matches[0]), False
        return None, False

    @classmethod
    def extract_rg(cls, text: str) -> Optional[str]:
        rg_regex = r"\b(?<!\d)(\d{1,2}\.?\d{3}\.?\d{3}[- ]?[0-9xX])\b"
        matches = re.findall(rg_regex, text)
        for m in matches:
            digits_only = re.sub(r"\D", "", m)
            if 7 <= len(digits_only) <= 9:
                return cls.format_rg(m)
        return None

    @classmethod
    def extract_dates(cls, text: str) -> List[str]:
        raw_matches = re.findall(r"\b(0[1-9]|[12][0-9]|3[01])[\/.-](0[1-9]|1[012])[\/.-]((?:19|20)\d{2})\b", text)
        dates = [f"{d[0]}/{d[1]}/{d[2]}" for d in raw_matches]
        return list(dict.fromkeys(dates))

    @classmethod
    def extract_cnh_fields(cls, text: str) -> Dict[str, Optional[str]]:
        """Extracts CNH-specific fields: RENACH, Categoria, Validade, 1ª Habilitação."""
        norm_text = cls.normalize_accents(text)
        
        # Category: e.g. "CAT. HAB. B", "CATEGORIA AB", "ACC"
        category = None
        cat_match = re.search(r"(?:CATEGORIA|CAT\.?\s*HAB\.?|CAT)\s*[:\-]?\s*([A-E]{1,2}|ACC)", norm_text)
        if cat_match:
            category = cat_match.group(1).strip()
        elif "ACC" in norm_text:
            category = "ACC"

        # RENACH: typically 2 letters + 9-11 digits (e.g. SP123456789)
        renach = None
        renach_match = re.search(r"\b([A-Z]{2}\s*\d{9,11})\b", norm_text)
        if renach_match:
            renach = renach_match.group(1).replace(" ", "")

        # CNH Registration Number (typically 11 consecutive digits)
        reg_num = None
        reg_match = re.search(r"(?:REGISTRO|N[OA]?\s*REGISTRO)[^\d]*(\d{9,11})", norm_text)
        if reg_match:
            reg_num = reg_match.group(1)
        else:
            # Look for isolated 11 digit numbers that are NOT the CPF
            all_11 = re.findall(r"\b(\d{11})\b", norm_text)
            cpf_digits = re.sub(r"\D", "", cls.extract_cpf(text)[0] or "")
            for num in all_11:
                if num != cpf_digits:
                    reg_num = num
                    break

        return {
            "category": category,
            "renach": renach,
            "registration": reg_num
        }

    @classmethod
    def extract_names_from_blocks(cls, raw_text: str) -> tuple[Optional[str], Optional[str], Optional[str]]:
        """
        Extracts Full Name, Mother Name, and Father Name taking into account OCR line wrapping.
        """
        lines = [l.strip() for l in raw_text.splitlines() if l.strip()]
        full_name = None
        mother_name = None
        father_name = None

        norm_lines = [cls.normalize_accents(l) for l in lines]

        # 1. Check for NOME section
        for i, nl in enumerate(norm_lines):
            if nl == "NOME" or nl.startswith("NOME:"):
                # Collect subsequent lines until a stop keyword
                name_parts = []
                for j in range(i + 1, min(i + 6, len(norm_lines))):
                    line_norm = norm_lines[j]
                    if any(w in line_norm for w in ["DOC", "IDENTIDADE", "CPF", "DATA", "NASCIMENTO", "FILIACAO", "RG"]):
                        break
                    # Filter noise
                    clean_words = [w for w in lines[j].split() if re.match(r"^[A-Za-zÀ-ÿ]{2,}$", w)]
                    if clean_words and not any(w.upper() in STOPWORDS_DOC for w in clean_words):
                        name_parts.extend(clean_words)
                if name_parts:
                    full_name = " ".join(name_parts).title()
                break

        # 2. Check for FILIACAO section
        for i, nl in enumerate(norm_lines):
            if "FILIACAO" in nl:
                parent_parts = []
                for j in range(i + 1, min(i + 7, len(norm_lines))):
                    line_norm = norm_lines[j]
                    if any(w in line_norm for w in ["PERMISSAO", "ACC", "VALIDADE", "HABILITACAO", "REGISTRO", "ASSINATURA", "VIA"]):
                        break
                    clean_words = [w for w in lines[j].split() if re.match(r"^[A-Za-zÀ-ÿ]{2,}$", w)]
                    if clean_words and not any(w.upper() in STOPWORDS_DOC for w in clean_words):
                        parent_parts.append(" ".join(clean_words).title())
                if parent_parts:
                    mother_name = parent_parts[0]
                    if len(parent_parts) > 1:
                        father_name = parent_parts[1]
                break

        # Fallback to general line search if section parsing was not found
        if not full_name:
            candidates = []
            for line in lines:
                words = [w for w in line.split() if re.match(r"^[A-Za-zÀ-ÿ]{2,}$", w)]
                if 2 <= len(words) <= 5:
                    upper_words = [cls.normalize_accents(w) for w in words]
                    if not set(upper_words).intersection(STOPWORDS_DOC):
                        candidates.append(" ".join(words).title())
            if candidates:
                full_name = candidates[0]
                if not mother_name and len(candidates) > 1:
                    mother_name = candidates[1]

        return full_name, mother_name, father_name

    @classmethod
    def detect_document_type(cls, raw_text: str, hint: str = "auto") -> str:
        """Determines whether the document is a Passport, CNH, CIN, RG, or CPF."""
        if hint != "auto":
            return hint

        norm = cls.normalize_accents(raw_text)

        # 1. Check for Passport MRZ lines
        if "P<" in norm or re.search(r"[A-Z0-9<]{40,46}", norm):
            return "passport"

        # 2. Check for CNH markers
        cnh_markers = [
            "HABILITACAO", "CARTEIRA NACIONAL", "DETRAN", "RENACH",
            "CATEGORIA HAB", "CONTRAN", "PERMISSAO", "REGISTRO", "ACC"
        ]
        matches = sum(1 for m in cnh_markers if m in norm)
        if matches >= 2 or "HABILITACAO" in norm or "CARTEIRA NACIONAL" in norm:
            return "cnh"

        # 3. Check for New CIN (Carteira de Identidade Nacional)
        if "IDENTIDADE NACIONAL" in norm or "CIN" in norm:
            return "cin"

        # 4. Default to standard RG
        return "rg"

    @classmethod
    def parse(cls, raw_text: str, doc_hint: str = "auto") -> ExtractedDocumentData:
        """Main entry point: classifies document and extracts structured data."""
        doc_type = cls.detect_document_type(raw_text, hint=doc_hint)

        # A. PASSPORT / MRZ PROCESSING
        mrz_data = ICAO9303MRZParser.find_and_parse_mrz(raw_text)
        if mrz_data or doc_type == "passport":
            if mrz_data:
                return ExtractedDocumentData(
                    document_type="passport",
                    document_number=mrz_data.get("document_number"),
                    full_name=mrz_data.get("full_name"),
                    surname=mrz_data.get("surname"),
                    given_names=mrz_data.get("given_names"),
                    nationality=mrz_data.get("nationality"),
                    issuing_country=mrz_data.get("issuing_country"),
                    birth_date=mrz_data.get("birth_date"),
                    gender=mrz_data.get("sex"),
                    expiry_date=mrz_data.get("expiry_date"),
                    mrz_valid=mrz_data.get("mrz_valid", False),
                    confidence_score=mrz_data.get("confidence_score", 0.85)
                )

        # Common extraction for Brazilian documents
        cpf, cpf_valid = cls.extract_cpf(raw_text)
        dates = cls.extract_dates(raw_text)
        full_name, mother_name, father_name = cls.extract_names_from_blocks(raw_text)

        # B. CNH PROCESSING
        if doc_type == "cnh":
            cnh_info = cls.extract_cnh_fields(raw_text)
            
            # Sort dates chronologically: birth date is oldest, validity is newest (often future)
            birth_date = None
            first_lic_date = None
            expiry_date = None
            if dates:
                # Sort by year
                sorted_dates = sorted(dates, key=lambda d: int(d.split("/")[2]))
                birth_date = sorted_dates[0]
                if len(sorted_dates) > 1:
                    expiry_date = sorted_dates[-1]
                if len(sorted_dates) > 2:
                    first_lic_date = sorted_dates[1]

            return ExtractedDocumentData(
                document_type="cnh",
                document_number=cnh_info.get("registration") or cls.extract_rg(raw_text),
                cpf=cpf,
                cpf_valid=cpf_valid,
                full_name=full_name,
                mother_name=mother_name,
                birth_date=birth_date,
                issuing_organ="DETRAN",
                issuing_date=first_lic_date,
                expiry_date=expiry_date,
                cnh_category=cnh_info.get("category"),
                cnh_renach=cnh_info.get("renach"),
                cnh_first_license_date=first_lic_date,
                confidence_score=0.95 if cpf_valid else 0.80
            )

        # C. RG & CIN PROCESSING
        rg_num = cls.extract_rg(raw_text)
        
        # Extract organ and state
        organ = None
        state = None
        norm_upper = cls.normalize_accents(raw_text)
        for org in ISSUING_ORGANS:
            if re.search(rf"\b{org}\b", norm_upper):
                organ = org
                break
        for st in BRAZILIAN_STATES:
            if re.search(rf"[\s\/\-_]{st}\b", norm_upper):
                state = st
                break

        birth_date = dates[0] if dates else None
        issue_date = dates[1] if len(dates) > 1 else None

        score = 0.0
        if rg_num or (doc_type == "cin" and cpf):
            score += 0.35
        if cpf:
            score += 0.3
            if cpf_valid:
                score += 0.1
        if full_name:
            score += 0.2
        confidence_score = min(round(score, 2), 1.0)

        return ExtractedDocumentData(
            document_type=doc_type,
            document_number=rg_num,
            cpf=cpf,
            cpf_valid=cpf_valid,
            full_name=full_name,
            mother_name=mother_name,
            father_name=father_name,
            birth_date=birth_date,
            issuing_organ=organ,
            issuing_state=state,
            issuing_date=issue_date,
            confidence_score=confidence_score
        )
