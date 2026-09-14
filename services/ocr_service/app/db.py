import os
import time
from typing import Optional, Dict, Any
from dotenv import load_dotenv

load_dotenv()

_SUPABASE_CLIENT = None

def get_supabase_client():
    """Initializes and caches the Supabase Python client if credentials exist in .env."""
    global _SUPABASE_CLIENT
    if _SUPABASE_CLIENT is not None:
        return _SUPABASE_CLIENT

    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY") or os.getenv("SUPABASE_ANON_KEY")

    if not url or not key or "your-project-id" in url or "demo-project" in url:
        return None

    try:
        from supabase import create_client
        _SUPABASE_CLIENT = create_client(url, key)
        return _SUPABASE_CLIENT
    except Exception as e:
        print(f"[!] Warning: Failed to connect to Supabase: {e}")
        return None

def save_document_to_supabase(
    extracted_data: Dict[str, Any],
    raw_text: str,
    filename: str,
    file_bytes: Optional[bytes] = None,
    confidence_score: float = 0.9
) -> Optional[str]:
    """
    Uploads document to Supabase storage bucket 'client-documents'
    and persists structured metadata into 'scanned_documents' table.
    Returns the created record UUID or None.
    """
    client = get_supabase_client()
    if client is None:
        return None

    try:
        storage_path = None
        if file_bytes:
            safe_name = "".join(c for c in filename if c.isalnum() or c in "._-")
            storage_path = f"scans/{int(time.time())}_{safe_name}"
            try:
                client.storage.from_("client-documents").upload(
                    storage_path,
                    file_bytes,
                    file_options={"content-type": "image/jpeg", "upsert": "true"}
                )
            except Exception as st_err:
                print(f"[!] Supabase storage upload notice: {st_err}")
                storage_path = None

        row = {
            "file_name": filename,
            "file_path": storage_path,
            "file_size_bytes": len(file_bytes) if file_bytes else None,
            "document_type": extracted_data.get("document_type", "rg"),
            "status": "auto_verified",
            "document_number": extracted_data.get("document_number"),
            "cpf": extracted_data.get("cpf"),
            "cpf_valid": extracted_data.get("cpf_valid", False),
            "full_name": extracted_data.get("full_name"),
            "birth_date": extracted_data.get("birth_date"),
            "mother_name": extracted_data.get("mother_name"),
            "father_name": extracted_data.get("father_name"),
            "naturalness": extracted_data.get("naturalness"),
            "nationality": extracted_data.get("nationality"),
            "gender": extracted_data.get("gender"),
            "issuing_organ": extracted_data.get("issuing_organ"),
            "issuing_state": extracted_data.get("issuing_state"),
            "issuing_country": extracted_data.get("issuing_country"),
            "issuing_date": extracted_data.get("issuing_date"),
            "expiry_date": extracted_data.get("expiry_date"),
            "cnh_category": extracted_data.get("cnh_category"),
            "cnh_renach": extracted_data.get("cnh_renach"),
            "cnh_first_license_date": extracted_data.get("cnh_first_license_date"),
            "passport_mrz_valid": extracted_data.get("mrz_valid", False),
            "confidence_score": confidence_score,
            "raw_ocr_text": raw_text,
            "extracted_payload": extracted_data,
        }

        res = client.table("scanned_documents").insert(row).execute()
        if res.data and len(res.data) > 0:
            return res.data[0].get("id")
        return None
    except Exception as e:
        print(f"[!] Error persisting to Supabase: {e}")
        return None
