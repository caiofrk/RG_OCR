import re
import unicodedata
import hashlib
from typing import Optional, Dict, Any, List
from thefuzz import fuzz
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
    "NATURALIDADE", "DATA", "NASCIMENTO", "EXPEDICAO", "VIA",
    "DOC", "ORIGEM", "LEI", "ASSINATURA", "DIRETOR", "POLEGAR", "DIREITO",
    "MINISTERIO", "JUSTICA", "DEPARTAMENTO", "TRANSITO", "CONTRAN", "DENATRAN",
    "NOME", "CPF", "VALIDADE", "EMISSOR", "PERMISSAO", "CATEGORIA"
}

class MultiDocumentParser:
    """
    Unified parser using Keyword-Anchored Parsing logic for robust extraction.
    """

    @staticmethod
    def normalize_accents(text: str) -> str:
        """Strips accents and standardizes to uppercase for robust matching."""
        if not text:
            return ""
        nfd = unicodedata.normalize("NFD", text)
        return "".join(c for c in nfd if unicodedata.category(c) != "Mn").upper()

    @staticmethod
    def _is_fuzzy_match(keyword: str, text: str, threshold: int = 85) -> bool:
        """Returns True if keyword is found in text using fuzzy matching."""
        if not text or not keyword:
            return False
        # If the exact keyword is already in the string, return True immediately
        if keyword in text:
            return True
            
        # Split text into words and check if any word (or combination of words) matches the keyword
        words = text.split()
        if not words:
            return False
            
        # Compare against the whole string (partial_ratio is good for "NOME" in "N0ME DO PAI")
        return fuzz.partial_ratio(keyword, text) >= threshold

    @staticmethod
    def validate_cpf(raw_cpf: str) -> bool:
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
        
    @staticmethod
    def generate_user_id(name: str, document_number: str) -> str:
        """Generates a deterministic unique user ID based on Name and Document Number/CPF."""
        base_string = f"{name or ''}_{document_number or ''}".strip().lower()
        base_string = re.sub(r"[^\w]", "", MultiDocumentParser.normalize_accents(base_string))
        return hashlib.md5(base_string.encode('utf-8')).hexdigest()

    @classmethod
    def extract_cpf(cls, text: str) -> tuple[Optional[str], bool]:
        # 1. Line-Sweeping Anchored Search for CPF
        lines = [l.strip() for l in text.splitlines() if l.strip()]
        for i, line in enumerate(lines):
            if cls._is_fuzzy_match("CPF", cls.normalize_accents(line)):
                # Search the current line and up to 3 lines ahead
                for j in range(i, min(i + 4, len(lines))):
                    match = re.search(r"(\d{3}[\.\s,\-=]*\d{3}[\.\s,\-=]*\d{3}[\.\s,\-=]*\d{2})", lines[j])
                    if match:
                        cleaned = re.sub(r"\D", "", match.group(1))
                        return cls.format_cpf(cleaned), cls.validate_cpf(cleaned)
                        
        # 2. Fallback to general valid CPF match
        matches = re.findall(r"\b\d{3}[\.\s,\-=]*\d{3}[\.\s,\-=]*\d{3}[\.\s,\-=]*\d{2}\b", text)
        for candidate in matches:
            cleaned = re.sub(r"\D", "", candidate)
            if cls.validate_cpf(cleaned):
                return cls.format_cpf(cleaned), True
                
        return None, False

    @classmethod
    def extract_rg(cls, text: str) -> Optional[str]:
        norm = cls.normalize_accents(text)
        
        # Keyword anchored search for RG
        anchors = [r"REGISTRO\s*GERAL", r"IDENTIDADE", r"DOC\.", r"DOC\s*IDENTIDADE"]
        for anchor in anchors:
            match = re.search(rf"{anchor}[^\d]*(\d{{1,2}}[\.\s,-]*\d{{3}}[\.\s,-]*\d{{3}}[\.\s,-]*[0-9xX])\b", norm)
            if match:
                return cls.format_rg(match.group(1))
                
        # Fallback
        rg_regex = r"\b(?<!\d)(\d{1,2}[\.\s,-]*\d{3}[\.\s,-]*\d{3}[\.\s,-]*[0-9xX])\b"
        matches = re.findall(rg_regex, text)
        for m in matches:
            digits_only = re.sub(r"\D", "", m)
            if 7 <= len(digits_only) <= 9:
                return cls.format_rg(m)
        return None

    @classmethod
    def extract_dates(cls, text: str) -> List[str]:
        # First, find anchored birth date
        birth_date = None
        norm = cls.normalize_accents(text)
        b_match = re.search(r"(?:NASCIMENTO|DATA\s*NASC\.?)[^\d]*(0[1-9]|[12][0-9]|3[01])[\/.\-,\s](0[1-9]|1[012])[\/.\-,\s]((?:19|20)\d{2})\b", norm)
        if b_match:
            birth_date = f"{b_match.group(1)}/{b_match.group(2)}/{b_match.group(3)}"
            
        raw_matches = re.findall(r"\b(0[1-9]|[12][0-9]|3[01])[\/.\-,\s](0[1-9]|1[012])[\/.\-,\s]((?:19|20)\d{2})\b", text)
        dates = [f"{d[0]}/{d[1]}/{d[2]}" for d in raw_matches]
        dates = list(dict.fromkeys(dates))
        
        # If we anchored a birth date, make sure it's the first in the list
        if birth_date and birth_date in dates:
            dates.remove(birth_date)
            dates.insert(0, birth_date)
            
        return dates

    @classmethod
    def extract_cnh_fields(cls, text: str) -> Dict[str, Optional[str]]:
        norm_text = cls.normalize_accents(text)
        
        # OCR Typo Correction for Categories
        def _correct_category(cat: str) -> str:
            cat = cat.upper()
            return cat.replace("2B", "AB").replace("4B", "AB").replace("0", "D").replace("8", "B")

        # Anchored Category
        category = None
        cat_match = re.search(r"(?:CATEGORIA|CAT\.?\s*HAB\.?|CAT|CI\s*HAB).*?\b([A-E]{1,2}|ACC|2B|4B)\b", norm_text, re.IGNORECASE)
        if cat_match:
            category = _correct_category(cat_match.group(1).upper())
        else:
            # Fallback: look for isolated valid category on a short line (OCR might miss "CAT. HAB.")
            lines = [l.strip() for l in text.splitlines() if l.strip()]
            valid_cats = ["A", "B", "AB", "C", "D", "E"]
            for i, l in enumerate(lines):
                l_norm = cls.normalize_accents(l)
                if l_norm in valid_cats or _correct_category(l_norm) in valid_cats:
                    category = _correct_category(l_norm)
                    break
                # Special fallback for old CNH: check if "PERMISSAO", "ACC", or "CI HAB" are nearby
                if "PERMISSAO" in l_norm or "ACC" in l_norm or "CI HAB" in l_norm:
                    # check next few lines for A, B, AB
                    for j in range(i, min(i + 4, len(lines))):
                        corrected_line = _correct_category(lines[j].strip().upper())
                        if corrected_line in valid_cats:
                            category = corrected_line
                            break
                    if category:
                        break

        # Anchored RENACH
        renach = None
        renach_match = re.search(r"(?:RENACH).*?\b([A-Z]{2}[\s0-9O]{9,11})\b", norm_text)
        if not renach_match:
            renach_match = re.search(r"\b([A-Z]{2}[\s0-9O]{9,11})\b", norm_text) # fallback
        if renach_match:
            renach = renach_match.group(1).replace(" ", "").replace("O", "0")

        # Anchored Registration Number
        reg_num = None
        reg_match = re.search(r"(?:REGISTRO|N[OA]?\s*REGISTRO)[^\d]*([0-9O]{9,11})", norm_text)
        if reg_match:
            reg_num = reg_match.group(1).replace("O", "0")
        else:
            all_11 = re.findall(r"\b(\d{11})\b", norm_text)
            cpf_digits = re.sub(r"\D", "", cls.extract_cpf(text)[0] or "")
            for num in all_11:
                if num != cpf_digits and num.startswith("00"):
                    reg_num = num
                    break
            
            if not reg_num:
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
    def extract_name_from_blocks(cls, raw_text: str) -> Optional[str]:
        lines = [l.strip() for l in raw_text.splitlines() if l.strip()]
        full_name = None
        norm_lines = [cls.normalize_accents(l) for l in lines]

        # Anchored NOME
        for i, nl in enumerate(norm_lines):
            if cls._is_fuzzy_match("NOME", nl) or cls._is_fuzzy_match("NOME:", nl) or cls._is_fuzzy_match("NOMF", nl):
                name_parts = []
                for j in range(i + 1, min(i + 6, len(norm_lines))):
                    line_norm = norm_lines[j]
                    if any(w in line_norm for w in ["DOC", "IDENTIDADE", "CPF", "DATA", "NASCIMENTO", "FILIACAO", "RG", "LOCAL"]):
                        break
                        
                    # New CNH: "SOBRENOME" and "NOME SOCIAL" are labels that appear in the middle of the name lines
                    for label in ["SOBRENOME", "NOME SOCIAL", "NOVE SOCIAL"]:
                        line_norm = line_norm.replace(label, "")
                        
                    clean_words = [w for w in line_norm.split() if re.match(r"^[A-Z]{2,}$", w)]
                    if clean_words and not any(w in STOPWORDS_DOC for w in clean_words):
                        name_parts.extend(clean_words)
                if name_parts:
                    full_name = " ".join(name_parts).title()
                break

        if not full_name:
            candidates = []
            for line in lines:
                clean_line_words = [re.sub(r"[^\wÀ-ÿ]", "", w) for w in line.split()]
                words = [w for w in clean_line_words if len(w) >= 2 and not any(c.isdigit() for c in w)]
                if 2 <= len(words) <= 5:
                    upper_words = [cls.normalize_accents(w) for w in words]
                    if not set(upper_words).intersection(STOPWORDS_DOC):
                        candidates.append(" ".join(words).title())
            if candidates:
                full_name = candidates[0]

        return full_name

    @classmethod
    def detect_document_type(cls, raw_text: str, hint: str = "auto") -> str:
        if hint != "auto":
            return hint
        norm = cls.normalize_accents(raw_text)
        if "P<" in norm or re.search(r"[A-Z0-9<]{40,46}", norm): return "passport"
        cnh_markers = ["HABILITACAO", "CARTEIRA NACIONAL", "DETRAN", "RENACH", "CATEGORIA HAB", "CONTRAN", "PERMISSAO", "REGISTRO", "ACC"]
        matches = sum(1 for m in cnh_markers if cls._is_fuzzy_match(m, norm))
        if matches >= 2 or cls._is_fuzzy_match("HABILITACAO", norm) or cls._is_fuzzy_match("CARTEIRA NACIONAL", norm): return "cnh"
        if cls._is_fuzzy_match("IDENTIDADE NACIONAL", norm) or cls._is_fuzzy_match("CIN", norm): return "cin"
        return "rg"

    @classmethod
    def parse(cls, raw_text: str, doc_hint: str = "auto") -> ExtractedDocumentData:
        doc_type = cls.detect_document_type(raw_text, hint=doc_hint)

        mrz_data = ICAO9303MRZParser.find_and_parse_mrz(raw_text)
        if mrz_data or doc_type == "passport":
            if mrz_data:
                user_id = cls.generate_user_id(mrz_data.get("full_name", ""), mrz_data.get("document_number", ""))
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
                    confidence_score=mrz_data.get("confidence_score", 0.85),
                    user_id=user_id
                )

        cpf, cpf_valid = cls.extract_cpf(raw_text)
        dates = cls.extract_dates(raw_text)
        full_name = cls.extract_name_from_blocks(raw_text)
        
        norm_upper = cls.normalize_accents(raw_text)
        state = None
        for st in BRAZILIAN_STATES:
            if re.search(rf"[\s\/\-_]{st}\b", norm_upper) or re.search(rf"\b{st}\b", norm_upper[-40:]):
                state = st
                break

        if doc_type == "cnh":
            cnh_info = cls.extract_cnh_fields(raw_text)
            birth_date = None
            first_lic_date = None
            expiry_date = None
            if dates:
                birth_date = dates[0]
                sorted_dates = sorted(dates, key=lambda d: int(d.split("/")[2]))
                if len(sorted_dates) > 1:
                    expiry_date = sorted_dates[-1]
                if len(sorted_dates) > 2:
                    first_lic_date = sorted_dates[1]
                    
            user_id = cls.generate_user_id(full_name or "", cpf or cls.extract_rg(raw_text) or "")

            return ExtractedDocumentData(
                document_type="cnh",
                document_number=cnh_info.get("registration") or cls.extract_rg(raw_text),
                cpf=cpf,
                cpf_valid=cpf_valid,
                full_name=full_name,
                birth_date=birth_date,
                issuing_organ="DETRAN",
                issuing_state=state,
                issuing_date=first_lic_date,
                expiry_date=expiry_date,
                cnh_category=cnh_info.get("category"),
                cnh_renach=cnh_info.get("renach"),
                cnh_registro=cnh_info.get("registration"),
                cnh_first_license_date=first_lic_date,
                confidence_score=0.95 if cpf_valid else 0.80,
                user_id=user_id
            )

        rg_num = cls.extract_rg(raw_text)
        organ = None
        for org in ISSUING_ORGANS:
            if re.search(rf"\b{org}\b", norm_upper):
                organ = org
                break

        birth_date = dates[0] if dates else None
        issue_date = dates[1] if len(dates) > 1 else None

        score = 0.0
        if rg_num or (doc_type == "cin" and cpf): score += 0.35
        if cpf: 
            score += 0.3
            if cpf_valid: score += 0.1
        if full_name: score += 0.2
        confidence_score = min(round(score, 2), 1.0)
        
        user_id = cls.generate_user_id(full_name or "", cpf or rg_num or "")

        return ExtractedDocumentData(
            document_type=doc_type,
            document_number=rg_num,
            cpf=cpf,
            cpf_valid=cpf_valid,
            full_name=full_name,
            birth_date=birth_date,
            issuing_organ=organ,
            issuing_state=state,
            issuing_date=issue_date,
            confidence_score=confidence_score,
            user_id=user_id
        )
