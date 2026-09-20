import os
import json
import uuid
import time
import sqlite3
from typing import Optional, Dict, Any, List
from datetime import datetime

# Define data directory inside services/ocr_service/data
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")
SCANS_DIR = os.path.join(DATA_DIR, "scans")
DB_PATH = os.path.join(DATA_DIR, "documents.db")

os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(SCANS_DIR, exist_ok=True)

def get_db_connection() -> sqlite3.Connection:
    """Returns a SQLite connection with dict-like row factory."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    """Initializes SQLite database and tables with full index support."""
    with get_db_connection() as conn:
        cursor = conn.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS scanned_documents (
                id TEXT PRIMARY KEY,
                file_name TEXT NOT NULL,
                file_path TEXT,
                file_size_bytes INTEGER,
                document_type TEXT NOT NULL DEFAULT 'rg',
                status TEXT NOT NULL DEFAULT 'auto_verified',
                
                -- Extracted Document Fields
                document_number TEXT,
                cpf TEXT,
                cpf_valid INTEGER DEFAULT 0,
                full_name TEXT,
                user_id TEXT,
                birth_date TEXT,
                naturalness TEXT,
                nationality TEXT,
                gender TEXT,
                issuing_organ TEXT,
                issuing_state TEXT,
                issuing_country TEXT,
                issuing_date TEXT,
                expiry_date TEXT,
                
                -- CNH Specific Fields
                cnh_category TEXT,
                cnh_renach TEXT,
                cnh_first_license_date TEXT,
                
                -- Passport Specific Fields
                passport_mrz_lines TEXT,
                passport_mrz_valid INTEGER DEFAULT 0,
                passport_issuing_country TEXT,
                
                -- OCR Confidence & Raw Text
                confidence_score REAL DEFAULT 0.0,
                raw_ocr_text TEXT,
                extracted_payload TEXT,
                operator_notes TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
        """)

        # Indexes for lightning-fast lookups
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_scanned_cpf ON scanned_documents(cpf);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_scanned_doc_num ON scanned_documents(document_number);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_scanned_type ON scanned_documents(document_type);")
        cursor.execute("CREATE INDEX IF NOT EXISTS idx_scanned_created ON scanned_documents(created_at DESC);")
        conn.commit()

# Ensure DB is created on module import
init_db()

class LocalDatabaseService:
    """Local embedded database service for zero-cost document persistence."""

    @staticmethod
    def save_document(
        extracted_data: Dict[str, Any],
        raw_text: str,
        filename: str,
        file_bytes: Optional[bytes] = None,
        confidence_score: float = 0.9
    ) -> str:
        """
        Saves scanned image to local scans directory and stores metadata in SQLite.
        Returns document ID (UUID).
        """
        doc_id = str(uuid.uuid4())
        now_iso = datetime.utcnow().isoformat() + "Z"
        
        rel_file_path = None
        file_size = len(file_bytes) if file_bytes else None

        if file_bytes:
            safe_name = "".join(c for c in filename if c.isalnum() or c in "._-")
            scan_filename = f"{int(time.time())}_{safe_name}"
            abs_path = os.path.join(SCANS_DIR, scan_filename)
            with open(abs_path, "wb") as f:
                f.write(file_bytes)
            rel_file_path = os.path.join("data", "scans", scan_filename)

        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO scanned_documents (
                    id, file_name, file_path, file_size_bytes, document_type, status,
                    document_number, cpf, cpf_valid, full_name, user_id, birth_date,
                    naturalness, nationality, gender,
                    issuing_organ, issuing_state, issuing_country, issuing_date,
                    expiry_date, cnh_category, cnh_renach, cnh_first_license_date,
                    passport_mrz_lines, passport_mrz_valid, confidence_score,
                    raw_ocr_text, extracted_payload, created_at, updated_at
                ) VALUES (
                    ?, ?, ?, ?, ?, ?,
                    ?, ?, ?, ?, ?, ?,
                    ?, ?, ?,
                    ?, ?, ?, ?,
                    ?, ?, ?, ?,
                    ?, ?, ?,
                    ?, ?, ?, ?
                )
            """, (
                doc_id,
                filename,
                rel_file_path,
                file_size,
                extracted_data.get("document_type", "rg"),
                "auto_verified",
                extracted_data.get("document_number"),
                extracted_data.get("cpf"),
                1 if extracted_data.get("cpf_valid") else 0,
                extracted_data.get("full_name"),
                extracted_data.get("user_id"),
                extracted_data.get("birth_date"),
                extracted_data.get("naturalness"),
                extracted_data.get("nationality"),
                extracted_data.get("gender"),
                extracted_data.get("issuing_organ"),
                extracted_data.get("issuing_state"),
                extracted_data.get("issuing_country"),
                extracted_data.get("issuing_date"),
                extracted_data.get("expiry_date"),
                extracted_data.get("cnh_category"),
                extracted_data.get("cnh_renach"),
                extracted_data.get("cnh_first_license_date"),
                json.dumps(extracted_data.get("mrz_lines")) if extracted_data.get("mrz_lines") else None,
                1 if extracted_data.get("mrz_valid") else 0,
                confidence_score,
                raw_text,
                json.dumps(extracted_data, ensure_ascii=False),
                now_iso,
                now_iso
            ))
            conn.commit()

        return doc_id

    @staticmethod
    def list_documents(
        search: Optional[str] = None,
        doc_type: Optional[str] = None,
        limit: int = 50,
        offset: int = 0
    ) -> List[Dict[str, Any]]:
        """Lists saved documents with optional text search and type filtering."""
        with get_db_connection() as conn:
            cursor = conn.cursor()
            query = "SELECT * FROM scanned_documents"
            params = []
            conditions = []

            if search:
                pattern = f"%{search.strip()}%"
                conditions.append("(full_name LIKE ? OR document_number LIKE ? OR cpf LIKE ? OR user_id LIKE ?)")
                params.extend([pattern, pattern, pattern, pattern])

            if doc_type and doc_type != "auto":
                conditions.append("document_type = ?")
                params.append(doc_type)

            if conditions:
                query += " WHERE " + " AND ".join(conditions)

            query += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
            params.extend([limit, offset])

            cursor.execute(query, params)
            rows = cursor.fetchall()

            results = []
            for r in rows:
                item = dict(r)
                item["cpf_valid"] = bool(item.get("cpf_valid"))
                item["passport_mrz_valid"] = bool(item.get("passport_mrz_valid"))
                if item.get("extracted_payload"):
                    try:
                        item["extracted_payload"] = json.loads(item["extracted_payload"])
                    except Exception:
                        pass
                results.append(item)
            return results

    @staticmethod
    def get_document(doc_id: str) -> Optional[Dict[str, Any]]:
        """Fetches a single document by ID."""
        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT * FROM scanned_documents WHERE id = ?", (doc_id,))
            row = cursor.fetchone()
            if not row:
                return None
            item = dict(row)
            item["cpf_valid"] = bool(item.get("cpf_valid"))
            item["passport_mrz_valid"] = bool(item.get("passport_mrz_valid"))
            if item.get("extracted_payload"):
                try:
                    item["extracted_payload"] = json.loads(item["extracted_payload"])
                except Exception:
                    pass
            return item

    @staticmethod
    def delete_document(doc_id: str) -> bool:
        """Deletes a document record and its stored scan image."""
        doc = LocalDatabaseService.get_document(doc_id)
        if not doc:
            return False

        with get_db_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("DELETE FROM scanned_documents WHERE id = ?", (doc_id,))
            conn.commit()

        # Delete image file if present
        rel_path = doc.get("file_path")
        if rel_path:
            abs_path = os.path.join(BASE_DIR, rel_path)
            if os.path.exists(abs_path):
                try:
                    os.remove(abs_path)
                except Exception:
                    pass

        return True

    @staticmethod
    def get_scan_file_path(doc_id: str) -> Optional[str]:
        """Returns the absolute path to the stored document scan file."""
        doc = LocalDatabaseService.get_document(doc_id)
        if not doc or not doc.get("file_path"):
            return None
        abs_path = os.path.join(BASE_DIR, doc["file_path"])
        return abs_path if os.path.exists(abs_path) else None

local_db = LocalDatabaseService()
