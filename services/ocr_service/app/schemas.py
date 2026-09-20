from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field

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

