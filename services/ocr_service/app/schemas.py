from typing import Optional, List, Dict, Any
import re
from pydantic import BaseModel, Field, field_validator, model_validator

class ExtractedDocumentData(BaseModel):
    document_type: str = Field(default="rg", description="Document type: rg, cnh, passport, cin, or cpf")
    document_number: Optional[str] = Field(None, description="Extracted RG, Passport Number, or CNH Registration")
    cpf: Optional[str] = Field(None, description="Brazilian CPF number (11 digits)")
    cpf_valid: bool = Field(default=False, description="Whether CPF passed modulus 11 checksum")
    full_name: Optional[str] = Field(None, description="Full Name of the document holder")
    surname: Optional[str] = Field(None, description="Surname / Sobrenome (especially for Passports)")
    given_names: Optional[str] = Field(None, description="Given Names / Nome próprio")
    birth_date: Optional[str] = Field(None, description="Date of birth in DD/MM/YYYY")
    user_id: Optional[str] = Field(None, description="Unique identifier generated from Name and Document")
    naturalness: Optional[str] = Field(None, description="Naturalidade (City - State)")
    nationality: Optional[str] = Field(None, description="Nationality (e.g. BRA, USA, ARG)")
    gender: Optional[str] = Field(None, description="Gender / Sex (M, F, X)")
    issuing_organ: Optional[str] = Field(None, description="Órgão Emissor (e.g. SSP, DETRAN, POLICIA FEDERAL)")
    issuing_state: Optional[str] = Field(None, description="Issuing state (UF, e.g. SP, RJ, MG)")
    issuing_country: Optional[str] = Field(None, description="Issuing country code (ISO alpha-3)")
    issuing_date: Optional[str] = Field(None, description="Document issuance date (Data de Expedição)")
    expiry_date: Optional[str] = Field(None, description="Document expiration date (Data de Validade)")
    
    # CNH Specific Attributes
    cnh_category: Optional[str] = Field(None, description="Driver License Category: A, B, AB, C, D, E")
    cnh_renach: Optional[str] = Field(None, description="RENACH number")
    cnh_first_license_date: Optional[str] = Field(None, description="1ª Habilitação date")
    
    # Passport & MRZ Attributes
    mrz_lines: Optional[List[str]] = Field(None, description="Raw detected MRZ lines")
    mrz_valid: bool = Field(default=False, description="Whether ICAO 9303 check digits passed")
    
    confidence_score: float = Field(default=0.0, description="Overall confidence score from 0.0 to 1.0")

    @field_validator("birth_date", "issuing_date", "expiry_date", "cnh_first_license_date", mode="before")
    def validate_dates(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        # Silently return None if it doesn't match a strict DD/MM/YYYY format
        if not re.match(r"^(0[1-9]|[12][0-9]|3[01])/(0[1-9]|1[012])/(19|20)\d\d$", str(v).strip()):
            return None
        return str(v).strip()

    @field_validator("cpf", mode="before")
    def validate_cpf_format(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        if not re.match(r"^\d{3}\.\d{3}\.\d{3}\-\d{2}$", str(v).strip()):
            return None
        return str(v).strip()

    @field_validator("full_name", "surname", "given_names", mode="before")
    def validate_names(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        return str(v).strip().title()

    @field_validator("issuing_organ", mode="before")
    def validate_issuing_organ(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        return str(v).strip().upper()

    @field_validator("issuing_state", mode="before")
    def validate_state(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        state = str(v).strip().upper()
        valid_states = {
            "AC", "AL", "AP", "AM", "BA", "CE", "DF", "ES", "GO", "MA",
            "MT", "MS", "MG", "PA", "PB", "PR", "PE", "PI", "RJ", "RN",
            "RS", "RO", "RR", "SC", "SP", "SE", "TO"
        }
        return state if state in valid_states else None

    @field_validator("gender", mode="before")
    def validate_gender(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        g = str(v).strip().upper()
        if g in ["M", "MASCULINO", "MASC"]:
            return "M"
        if g in ["F", "FEMININO", "FEM"]:
            return "F"
        if g in ["X", "OUTRO", "OUTROS"]:
            return "X"
        return None

    @field_validator("cnh_category", mode="before")
    def validate_cnh_category(cls, v: Optional[str]) -> Optional[str]:
        if not v:
            return None
        cat = str(v).strip().upper()
        valid_cats = {"A", "B", "AB", "C", "D", "E", "ACC"}
        return cat if cat in valid_cats else None

class OCRProcessResponse(BaseModel):
    success: bool
    filename: str
    message: str
    extracted_data: ExtractedDocumentData
    raw_text: Optional[str] = None
    processing_time_ms: float
    saved_document_id: Optional[str] = Field(None, description="Local SQLite document ID if persisted")

class MRZParseRequest(BaseModel):
    lines: List[str]

class CPFValidationRequest(BaseModel):
    cpf: str

class CPFValidationResponse(BaseModel):
    cpf: str
    is_valid: bool
    formatted: Optional[str] = None

class DocumentSaveRequest(BaseModel):
    filename: str = Field(default="document.jpg")
    extracted_data: Dict[str, Any]
    raw_text: Optional[str] = ""
    confidence_score: Optional[float] = 0.9

class DocumentListResponse(BaseModel):
    total: int
    documents: List[Dict[str, Any]]

