import time
import os
from typing import Optional
from fastapi import FastAPI, File, UploadFile, HTTPException, Depends, Header, Form
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
from .config import settings
from .schemas import (
    OCRProcessResponse,
    ExtractedDocumentData,
    MRZParseRequest,
    CPFValidationRequest,
    CPFValidationResponse,
    DocumentSaveRequest,
    DocumentListResponse
)
from .parser import MultiDocumentParser
from .mrz_parser import ICAO9303MRZParser
from .ocr_engine import ocr_engine
from .database import local_db


app = FastAPI(
    title=settings.app_name,
    version=settings.version,
    description="High-precision Document Scanner & OCR Extraction Suite for RG, CNH, Passports (MRZ), and CIN."
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def verify_api_key(x_api_key: str = Header(default="")):
    if settings.api_key and settings.api_key != "rg_ocr_secret_token_change_in_production":
        if x_api_key != settings.api_key:
            raise HTTPException(status_code=401, detail="Invalid or missing API Key")
    return True

@app.get("/health")
def health_check():
    return {
        "status": "healthy",
        "service": settings.app_name,
        "version": settings.version,
        "tesseract_available": ocr_engine.has_tesseract,
        "supported_documents": ["rg", "cnh", "passport", "cin", "cpf"]
    }

@app.post("/api/v1/ocr/validate-cpf", response_model=CPFValidationResponse)
def validate_cpf(request: CPFValidationRequest):
    """Validates a Brazilian CPF using modulus 11 checksum."""
    is_valid = MultiDocumentParser.validate_cpf(request.cpf)
    formatted = MultiDocumentParser.format_cpf(request.cpf) if is_valid else None
    return CPFValidationResponse(
        cpf=request.cpf,
        is_valid=is_valid,
        formatted=formatted
    )

@app.post("/api/v1/ocr/parse-mrz")
def parse_mrz(request: MRZParseRequest):
    """
    Direct endpoint to parse Passport / ID card MRZ lines (ICAO Doc 9303).
    Supports TD3 (2x44) and TD1 (3x30).
    """
    clean_lines = [l.strip() for l in request.lines if l.strip()]
    if len(clean_lines) == 2:
        return ICAO9303MRZParser.parse_td3(clean_lines[0], clean_lines[1])
    elif len(clean_lines) == 3:
        return ICAO9303MRZParser.parse_td1(clean_lines[0], clean_lines[1], clean_lines[2])
    else:
        # Try scanning as single text block
        text_block = "\n".join(clean_lines)
        res = ICAO9303MRZParser.find_and_parse_mrz(text_block)
        if res:
            return res
        raise HTTPException(status_code=400, detail="Expected 2 lines for TD3 Passport or 3 lines for TD1 ID Card.")

@app.post("/api/v1/ocr/parse-text", response_model=ExtractedDocumentData)
def parse_raw_text(
    text: str = Form(...),
    doc_type: str = Form(default="auto")
):
    """Parses raw text directly with document type auto-detection."""
    return MultiDocumentParser.parse(text, doc_hint=doc_type)

@app.post("/api/v1/ocr/process-document", response_model=OCRProcessResponse)
async def process_document(
    file: UploadFile = File(...),
    doc_type: str = Form(default="auto"),
    save_to_db: bool = Form(default=True),
    _auth: bool = Depends(verify_api_key)
):
    """
    Uploads an identity document (RG, CNH, Passport, CIN) in JPG, PNG, WEBP, or PDF,
    applies OpenCV preprocessing, executes OCR, and returns structured data.
    Auto-saves into local SQLite database if save_to_db is True.
    """
    start_time = time.time()
    
    _, ext = os.path.splitext(file.filename or "")
    if ext.lower() not in settings.allowed_extensions:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported format '{ext}'. Allowed: {settings.allowed_extensions}"
        )

    file_bytes = await file.read()
    max_bytes = settings.max_image_size_mb * 1024 * 1024
    if len(file_bytes) > max_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"File exceeds maximum allowed size of {settings.max_image_size_mb} MB"
        )

    extracted_data, raw_text = ocr_engine.process_document(
        file_bytes=file_bytes,
        filename=file.filename or "document.jpg",
        doc_hint=doc_type
    )

    elapsed_ms = round((time.time() - start_time) * 1000, 2)

    # Automatically persist to local SQLite database
    saved_doc_id = None
    if save_to_db:
        try:
            saved_doc_id = local_db.save_document(
                extracted_data=extracted_data.model_dump(),
                raw_text=raw_text,
                filename=file.filename or "document.jpg",
                file_bytes=file_bytes,
                confidence_score=extracted_data.confidence_score or 0.9
            )
        except Exception as e:
            # Non-fatal error so scan still returns even if persistence fails
            print(f"[Warning] Failed to save document to local DB: {e}")

    return OCRProcessResponse(
        success=True,
        filename=file.filename or "unknown",
        message=f"Document ({extracted_data.document_type.upper()}) processed successfully",
        extracted_data=extracted_data,
        raw_text=raw_text,
        processing_time_ms=elapsed_ms,
        saved_document_id=saved_doc_id
    )

# --- Local SQLite Document Persistence Endpoints ---

@app.get("/api/v1/documents", response_model=DocumentListResponse)
def list_documents(
    search: Optional[str] = None,
    doc_type: Optional[str] = None,
    limit: int = 50,
    offset: int = 0,
    _auth: bool = Depends(verify_api_key)
):
    """Lists saved documents from local SQLite with optional search and type filters."""
    docs = local_db.list_documents(search=search, doc_type=doc_type, limit=limit, offset=offset)
    return DocumentListResponse(total=len(docs), documents=docs)

@app.get("/api/v1/documents/{doc_id}")
def get_document(
    doc_id: str,
    _auth: bool = Depends(verify_api_key)
):
    """Retrieves a single document by ID from local SQLite."""
    doc = local_db.get_document(doc_id)
    if not doc:
        raise HTTPException(status_code=404, detail="Document not found")
    return doc

@app.get("/api/v1/documents/{doc_id}/file")
def get_document_file(
    doc_id: str,
    _auth: bool = Depends(verify_api_key)
):
    """Serves the original document image stored in local scans folder."""
    file_path = local_db.get_scan_file_path(doc_id)
    if not file_path or not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Stored document image not found")
    return FileResponse(file_path, filename=os.path.basename(file_path))

@app.post("/api/v1/documents")
def save_document(
    request: DocumentSaveRequest,
    _auth: bool = Depends(verify_api_key)
):
    """Saves document data directly to local SQLite."""
    doc_id = local_db.save_document(
        extracted_data=request.extracted_data,
        raw_text=request.raw_text or "",
        filename=request.filename,
        file_bytes=None,
        confidence_score=request.confidence_score or 0.9
    )
    return {"success": True, "id": doc_id, "message": "Document saved successfully"}

@app.delete("/api/v1/documents/{doc_id}")
def delete_document(
    doc_id: str,
    _auth: bool = Depends(verify_api_key)
):
    """Deletes a document record and its stored scan image."""
    success = local_db.delete_document(doc_id)
    if not success:
        raise HTTPException(status_code=404, detail="Document not found")
    return {"success": True, "message": "Document deleted successfully"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host=settings.host, port=settings.port, reload=True)

