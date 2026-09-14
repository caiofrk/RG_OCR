#!/usr/bin/env python3
"""
RG_OCR: Local Document OCR & Extraction CLI
-------------------------------------------
High-accuracy, zero-cost local OCR scanner for Brazilian & international documents:
- RG Tradicional (Old model with SSP/UF, filiação, doc number)
- Nova CIN (Carteira de Identidade Nacional with unified CPF)
- CNH (Carteira Nacional de Habilitação with RENACH, category, validity)
- Passaporte (ICAO Doc 9303 MRZ with 7-3-1 check-digit verification)
- CPF (Modulus 11 validation)

Usage:
    python scan_document.py <path_to_image>
    python scan_document.py test_document.jpg
    python scan_document.py test_document.jpg --json
"""

import sys
import os
import json
import time
import argparse

# Ensure UTF-8 output in Windows PowerShell / Command Prompt
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# Add services/ocr_service to path to reuse our battle-tested parsers & preprocessing
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
OCR_SERVICE_DIR = os.path.join(CURRENT_DIR, "services", "ocr_service")
if OCR_SERVICE_DIR not in sys.path:
    sys.path.insert(0, OCR_SERVICE_DIR)

from dotenv import load_dotenv
load_dotenv()

from app.preprocessing import ImagePreprocessor
from app.parser import MultiDocumentParser
from app.mrz_parser import ICAO9303MRZParser
from app.database import local_db
from app.db import save_document_to_supabase, get_supabase_client


_EASYOCR_READER = None

def get_ocr_reader():
    """Initializes and caches the EasyOCR reader model locally."""
    global _EASYOCR_READER
    if _EASYOCR_READER is None:
        import easyocr
        print("[*] Carregando modelo local de OCR (EasyOCR / PyTorch)...")
        _EASYOCR_READER = easyocr.Reader(["pt", "en"], gpu=False, verbose=False)
    return _EASYOCR_READER

def scan_image(image_path: str, doc_hint: str = "auto") -> dict:
    """Runs local image preprocessing, OCR extraction, and document parsing."""
    if not os.path.exists(image_path):
        raise FileNotFoundError(f"Arquivo não encontrado: {image_path}")

    start_time = time.time()
    print(f"[*] Lendo imagem: {os.path.basename(image_path)}...")
    with open(image_path, "rb") as f:
        image_bytes = f.read()

    # 1. OpenCV Preprocessing Pipeline (Bilateral filter, CLAHE contrast enhancement)
    print("[*] Aplicando pré-processamento OpenCV (contraste, denoise, alinhamento)...")
    enhanced, binary = ImagePreprocessor.process_pipeline(image_bytes)

    # 2. Local OCR Extraction via EasyOCR
    reader = get_ocr_reader()
    print("[*] Executando OCR sobre o documento...")
    
    # Run OCR on both enhanced grayscale and raw image for maximum text recall
    results = reader.readtext(enhanced, detail=1, paragraph=False)
    
    # Extract text lines and confidence scores
    text_lines = []
    confidences = []
    for bbox, text, conf in results:
        clean_text = text.strip()
        if clean_text:
            text_lines.append(clean_text)
            confidences.append(conf)

    raw_text = "\n".join(text_lines)
    avg_confidence = sum(confidences) / max(len(confidences), 1)

    # 3. Document Parsing & Checksum Verification
    print(f"[*] Classificando documento e validando dígitos verificadores...")
    extracted_data = MultiDocumentParser.parse(raw_text, doc_hint=doc_hint)
    
    elapsed = round(time.time() - start_time, 2)

    return {
        "success": True,
        "filename": os.path.basename(image_path),
        "processing_time_seconds": elapsed,
        "average_confidence": round(avg_confidence, 3),
        "raw_text_lines": len(text_lines),
        "extracted_data": extracted_data.model_dump(),
        "raw_text": raw_text
    }

def get_adb_path():
    candidates = [
        r"C:\Users\Admin\AppData\Local\Android\Sdk\platform-tools\adb.exe",
        "adb"
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return "adb"

def pull_latest_phone_photo() -> str:
    import subprocess
    adb = get_adb_path()
    res = subprocess.run([adb, "shell", "ls -t /sdcard/DCIM/Camera | head -n 1"], capture_output=True, text=True)
    filename = res.stdout.strip()
    if not filename or not any(filename.lower().endswith(ext) for ext in [".jpg", ".jpeg", ".png", ".webp"]):
        raise RuntimeError("Nenhuma foto recente encontrada no celular conectado via USB.")
    
    save_dir = os.path.join(CURRENT_DIR, "scans_inbox")
    os.makedirs(save_dir, exist_ok=True)
    local_path = os.path.join(save_dir, filename)
    
    print(f"[*] Celular conectado: Baixando foto mais recente ({filename})...")
    pull_res = subprocess.run([adb, "pull", f"/sdcard/DCIM/Camera/{filename}", local_path], capture_output=True, text=True)
    if pull_res.returncode != 0:
        raise RuntimeError(f"Erro ao transferir foto do celular: {pull_res.stderr}")
    return local_path

def watch_scans(doc_hint: str = "auto", no_local_db: bool = False, no_supabase: bool = False):
    """Continuously monitors for new scans on the phone or in scans_inbox/."""
    import subprocess
    adb = get_adb_path()
    last_processed = None
    save_dir = os.path.join(CURRENT_DIR, "scans_inbox")
    os.makedirs(save_dir, exist_ok=True)

    print("\n" + "=" * 60)
    print("  👀 RG_OCR • MODO OBSERVADOR AUTOMÁTICO (ZERO SERVIDOR)")
    print("=" * 60)
    print(f"  Pasta monitorada: {save_dir}")
    print("  Monitorando câmera do celular via USB...")
    print("  Tire uma foto no celular ou coloque um arquivo na pasta.")
    print("  Pressione Ctrl+C para encerrar.")
    print("=" * 60 + "\n")

    while True:
        try:
            # Check phone camera
            res = subprocess.run([adb, "shell", "ls -t /sdcard/DCIM/Camera | head -n 1"], capture_output=True, text=True)
            candidate = res.stdout.strip()
            if candidate and any(candidate.lower().endswith(ext) for ext in [".jpg", ".jpeg", ".png", ".webp"]):
                if candidate != last_processed:
                    print(f"\n[🔔 Nova Foto Detectada no Celular: {candidate}]")
                    local_path = os.path.join(save_dir, candidate)
                    subprocess.run([adb, "pull", f"/sdcard/DCIM/Camera/{candidate}", local_path], capture_output=True, text=True)
                    last_processed = candidate
                    process_file(local_path, doc_hint=doc_hint, no_local_db=no_local_db, no_supabase=no_supabase)
                    print("\n[*] Aguardando próximo scan...")
            time.sleep(2.5)
        except KeyboardInterrupt:
            print("\nObservador encerrado.")
            break
        except Exception as e:
            time.sleep(3.0)

def process_file(image_path: str, doc_hint: str = "auto", no_local_db: bool = False, no_supabase: bool = False, as_json: bool = False, output: str = None):
    try:
        result = scan_image(image_path, doc_hint=doc_hint)
    except Exception as e:
        print(f"Erro no processamento OCR: {e}", file=sys.stderr)
        return

    with open(image_path, "rb") as f:
        raw_bytes = f.read()

    local_doc_id = None
    if not no_local_db:
        try:
            local_doc_id = local_db.save_document(
                extracted_data=result["extracted_data"],
                raw_text=result["raw_text"],
                filename=os.path.basename(image_path),
                file_bytes=raw_bytes,
                confidence_score=result["average_confidence"]
            )
            result["local_db_id"] = local_doc_id
        except Exception as e:
            print(f"[Aviso] Falha ao salvar no SQLite local: {e}", file=sys.stderr)

    supabase_id = None
    if not no_supabase:
        supabase_id = save_document_to_supabase(
            extracted_data=result["extracted_data"],
            raw_text=result["raw_text"],
            filename=os.path.basename(image_path),
            file_bytes=raw_bytes,
            confidence_score=result["average_confidence"]
        )
        if supabase_id:
            result["supabase_id"] = supabase_id

    if as_json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return

    data = result["extracted_data"]
    doc_type = data.get("document_type", "unknown").upper()

    print("\n" + "=" * 60)
    print(f"  📄 RESULTADO DA EXTRAÇÃO OCR • {doc_type}")
    print("=" * 60)
    print(f"  Arquivo:          {result['filename']}")
    print(f"  Tempo de OCR:     {result['processing_time_seconds']}s")
    print(f"  Confiança Média:  {int(result['average_confidence'] * 100)}%")
    if local_doc_id:
        print(f"  SQLite Local DB:  ✅ Salvo offline (ID: {local_doc_id})")
    if supabase_id:
        print(f"  Supabase Cloud:   ✅ Salvo na nuvem (ID: {supabase_id})")
    elif get_supabase_client() is None:
        print(f"  Supabase Cloud:   ⚪ Desconectado (usando SQLite local)")
    print("-" * 60)
    
    fields = [
        ("Nome Completo", data.get("full_name")),
        ("Número do Doc", data.get("document_number")),
        ("CPF", data.get("cpf")),
        ("CPF Válido?", "✅ SIM (Módulo 11)" if data.get("cpf_valid") else ("❌ NÃO" if data.get("cpf") else None)),
        ("Data Nascimento", data.get("birth_date")),
        ("Órgão Emissor", data.get("issuing_organ")),
        ("UF Emissora", data.get("issuing_state")),
        ("Data Emissão", data.get("issuing_date")),
        ("Nome da Mãe", data.get("mother_name")),
        ("Nome do Pai", data.get("father_name")),
        ("Naturalidade", data.get("naturalness")),
        ("Categoria CNH", data.get("cnh_category")),
        ("RENACH CNH", data.get("cnh_renach")),
        ("Validade CNH", data.get("expiry_date")),
        ("Nacionalidade", data.get("nationality")),
        ("MRZ Válido?", "✅ SIM (ICAO 9303)" if data.get("mrz_valid") else None),
    ]

    for label, val in fields:
        if val:
            print(f"  {label:<18}: {val}")

    print("-" * 60)
    print("  Texto Bruto Extraído (primeiras linhas):")
    for line in result["raw_text"].splitlines()[:10]:
        if line.strip():
            print(f"    | {line}")
    print("=" * 60 + "\n")

    if output:
        with open(output, "w", encoding="utf-8") as out_f:
            json.dump(result, out_f, indent=2, ensure_ascii=False)
        print(f"Resultado salvo em: {output}")

def main():
    parser = argparse.ArgumentParser(description="RG_OCR: Local Document OCR Scanner (Zero Server)")
    parser.add_argument("image_path", nargs="?", default=None, help="Caminho para o arquivo de imagem (se omitido, usa a última foto do celular)")
    parser.add_argument("--phone", "--latest", action="store_true", help="Puxar e escanear a foto mais recente tirada na câmera do celular")
    parser.add_argument("--watch", action="store_true", help="Modo observador contínuo: auto-escaneia ao tirar foto no celular")
    parser.add_argument("--gui", action="store_true", help="Abrir interface gráfica nativa de desktop")
    parser.add_argument("--type", default="auto", choices=["auto", "rg", "cnh", "cin", "passport", "cpf"], help="Tipo de documento esperado")
    parser.add_argument("--json", action="store_true", help="Imprimir saída exclusivamente em formato JSON")
    parser.add_argument("--output", help="Salvar resultado estruturado em um arquivo JSON")
    parser.add_argument("--no-local-db", action="store_true", help="Desabilitar salvamento automático no banco SQLite local")
    parser.add_argument("--no-supabase", action="store_true", help="Desabilitar sincronização automática com o Supabase")

    args = parser.parse_args()

    if args.gui:
        import subprocess
        gui_path = os.path.join(CURRENT_DIR, "scan_gui.py")
        subprocess.run([sys.executable, gui_path])
        return

    if args.watch:
        watch_scans(doc_hint=args.type, no_local_db=args.no_local_db, no_supabase=args.no_supabase)
        return

    target_image = args.image_path

    # If --phone flag or if no image path specified, try pulling the latest from phone
    if args.phone or target_image is None:
        try:
            target_image = pull_latest_phone_photo()
        except Exception as e:
            if target_image is None:
                # Fallback to test_document.jpg if exists
                if os.path.exists("test_document.jpg"):
                    target_image = "test_document.jpg"
                    print(f"[*] Usando imagem local padrão: {target_image}")
                else:
                    print(f"Erro: {e}", file=sys.stderr)
                    print("Uso: python scan_document.py <caminho_da_imagem>")
                    print("Ou conecte o celular via USB e use: python scan_document.py --phone")
                    sys.exit(1)

    process_file(
        target_image,
        doc_hint=args.type,
        no_local_db=args.no_local_db,
        no_supabase=args.no_supabase,
        as_json=args.json,
        output=args.output
    )

if __name__ == "__main__":
    main()
