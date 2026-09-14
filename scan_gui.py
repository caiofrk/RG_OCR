#!/usr/bin/env python3
"""
RG_OCR: Native Desktop GUI
--------------------------
100% Serverless, zero-network Document Scanner & OCR Inspector.
Runs EasyOCR and OpenCV directly in-process with zero ports or HTTP connections.
"""

import sys
import os
import threading
import json
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

# Ensure services/ocr_service is on path
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
OCR_SERVICE_DIR = os.path.join(CURRENT_DIR, "services", "ocr_service")
if OCR_SERVICE_DIR not in sys.path:
    sys.path.insert(0, OCR_SERVICE_DIR)

from app.preprocessing import ImagePreprocessor
from app.parser import MultiDocumentParser
from app.database import local_db

try:
    from PIL import Image, ImageTk
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

_READER = None

def get_reader():
    global _READER
    if _READER is None:
        import easyocr
        _READER = easyocr.Reader(["pt", "en"], gpu=False, verbose=False)
    return _READER

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
    
    pull_res = subprocess.run([adb, "pull", f"/sdcard/DCIM/Camera/{filename}", local_path], capture_output=True, text=True)
    if pull_res.returncode != 0:
        raise RuntimeError(f"Erro ao transferir foto do celular: {pull_res.stderr}")
    return local_path

class DocumentScannerApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("RG_OCR • Extrator Local de Documentos (Zero Servidor)")
        self.geometry("1020x680")
        self.minsize(900, 600)
        self.configure(bg="#0f172a")

        self.current_image_path = None
        self.current_result = None

        self._init_styles()
        self._build_ui()

    def _init_styles(self):
        style = ttk.Style()
        style.theme_use("clam")
        style.configure("TFrame", background="#0f172a")
        style.configure("Card.TFrame", background="#1e293b", relief="flat")
        style.configure("TLabel", background="#0f172a", foreground="#f8fafc", font=("Segoe UI", 10))
        style.configure("Header.TLabel", font=("Segoe UI", 13, "bold"), foreground="#10b981")
        style.configure("FieldLabel.TLabel", background="#1e293b", font=("Segoe UI", 9, "bold"), foreground="#94a3b8")
        style.configure("FieldValue.TLabel", background="#1e293b", font=("Segoe UI", 10), foreground="#f8fafc")

    def _build_ui(self):
        # Top Action Bar
        top_bar = tk.Frame(self, bg="#1e293b", height=60, padx=16, pady=10)
        top_bar.pack(fill="x", side="top")

        title_lbl = tk.Label(
            top_bar,
            text="📄 RG_OCR • Scanner Direto (Python Local)",
            font=("Segoe UI", 14, "bold"),
            fg="#10b981",
            bg="#1e293b"
        )
        title_lbl.pack(side="left")

        # Buttons
        btn_phone = tk.Button(
            top_bar,
            text="📱 Capturar do Celular (USB)",
            font=("Segoe UI", 10, "bold"),
            bg="#0284c7",
            fg="white",
            activebackground="#0369a1",
            padx=12,
            pady=4,
            relief="flat",
            command=self._on_pull_phone
        )
        btn_phone.pack(side="right", padx=6)

        btn_file = tk.Button(
            top_bar,
            text="📂 Abrir Imagem do PC",
            font=("Segoe UI", 10, "bold"),
            bg="#10b981",
            fg="white",
            activebackground="#059669",
            padx=12,
            pady=4,
            relief="flat",
            command=self._on_choose_file
        )
        btn_file.pack(side="right", padx=6)

        # Status strip
        self.status_var = tk.StringVar(value="Pronto. Selecione uma imagem ou capture direto do celular.")
        self.status_bar = tk.Label(
            self,
            textvariable=self.status_var,
            font=("Segoe UI", 9),
            bg="#0f172a",
            fg="#94a3b8",
            anchor="w",
            padx=16,
            pady=6
        )
        self.status_bar.pack(fill="x", side="bottom")

        # Main Split Content
        main_paned = tk.PanedWindow(self, orient="horizontal", bg="#334155", sashwidth=4)
        main_paned.pack(fill="both", expand=True, padx=12, pady=10)

        # Left Panel: Image Preview
        left_frame = tk.Frame(main_paned, bg="#1e293b", padx=12, pady=12)
        main_paned.add(left_frame, width=420)

        lbl_img_title = tk.Label(left_frame, text="Documento Escaneado", font=("Segoe UI", 11, "bold"), fg="#f8fafc", bg="#1e293b")
        lbl_img_title.pack(anchor="w", pady=(0, 8))

        self.img_canvas = tk.Label(left_frame, text="Nenhuma imagem carregada\n\nClique em 'Abrir Imagem' ou 'Capturar do Celular'", bg="#0f172a", fg="#64748b", font=("Segoe UI", 10))
        self.img_canvas.pack(fill="both", expand=True)

        # Right Panel: Extracted Fields Form
        right_frame = tk.Frame(main_paned, bg="#1e293b", padx=16, pady=12)
        main_paned.add(right_frame)

        header_row = tk.Frame(right_frame, bg="#1e293b")
        header_row.pack(fill="x", pady=(0, 12))

        self.doc_type_lbl = tk.Label(header_row, text="DADOS EXTRAÍDOS", font=("Segoe UI", 12, "bold"), fg="#10b981", bg="#1e293b")
        self.doc_type_lbl.pack(side="left")

        self.btn_copy_json = tk.Button(
            header_row,
            text="Copiar JSON",
            font=("Segoe UI", 9, "bold"),
            bg="#334155",
            fg="white",
            relief="flat",
            command=self._copy_json,
            state="disabled"
        )
        self.btn_copy_json.pack(side="right")

        # Form Scrollable Canvas
        fields_canvas = tk.Canvas(right_frame, bg="#1e293b", highlightthickness=0)
        scrollbar = ttk.Scrollbar(right_frame, orient="vertical", command=fields_canvas.yview)
        self.fields_inner = tk.Frame(fields_canvas, bg="#1e293b")

        self.fields_inner.bind("<Configure>", lambda e: fields_canvas.configure(scrollregion=fields_canvas.bbox("all")))
        fields_canvas.create_window((0, 0), window=self.fields_inner, anchor="nw")
        fields_canvas.configure(yscrollcommand=scrollbar.set)

        fields_canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")

        self.field_widgets = {}
        fields_list = [
            ("Nome Completo", "full_name"),
            ("Número do Documento", "document_number"),
            ("CPF", "cpf"),
            ("CPF Válido (Módulo 11)", "cpf_valid"),
            ("Data de Nascimento", "birth_date"),
            ("Órgão Emissor / UF", "issuing_organ"),
            ("Nome da Mãe (Filiação)", "mother_name"),
            ("Categoria CNH", "cnh_category"),
            ("RENACH CNH", "cnh_renach"),
            ("Validade", "expiry_date"),
            ("Nacionalidade", "nationality"),
            ("Passaporte MRZ Válido", "mrz_valid"),
            ("Tempo de Processamento", "processing_time"),
            ("ID Banco Local (SQLite)", "local_id")
        ]

        for label_text, key in fields_list:
            row = tk.Frame(self.fields_inner, bg="#1e293b", pady=4)
            row.pack(fill="x", expand=True)

            lbl = tk.Label(row, text=label_text, font=("Segoe UI", 9, "bold"), fg="#94a3b8", bg="#1e293b", width=22, anchor="w")
            lbl.pack(side="left")

            val = tk.Entry(row, font=("Segoe UI", 10), bg="#0f172a", fg="#f8fafc", insertbackground="white", relief="flat")
            val.pack(side="right", fill="x", expand=True, ipady=3, padx=(8, 0))
            self.field_widgets[key] = val

    def _on_choose_file(self):
        path = filedialog.askopenfilename(
            title="Selecionar Documento",
            filetypes=[("Imagens", "*.jpg;*.jpeg;*.png;*.webp"), ("Todos os arquivos", "*.*")]
        )
        if path:
            self._process_image_async(path)

    def _on_pull_phone(self):
        self.status_var.set("⏳ Buscando foto mais recente no celular via USB...")
        self.update_idletasks()
        try:
            path = pull_latest_phone_photo()
            self._process_image_async(path)
        except Exception as e:
            messagebox.showerror("Erro Celular USB", str(e))
            self.status_var.set(f"Erro: {e}")

    def _process_image_async(self, image_path: str):
        self.current_image_path = image_path
        self._display_preview(image_path)
        self.status_var.set(f"⏳ Processando OCR localmente com EasyOCR + OpenCV ({os.path.basename(image_path)})...")
        self.btn_copy_json.configure(state="disabled")

        # Run OCR in background thread so UI remains responsive
        threading.Thread(target=self._run_ocr_worker, args=(image_path,), daemon=True).start()

    def _run_ocr_worker(self, image_path: str):
        import time
        t0 = time.time()

        try:
            with open(image_path, "rb") as f:
                raw_bytes = f.read()

            enhanced, _ = ImagePreprocessor.process_pipeline(raw_bytes)
            reader = get_reader()
            results = reader.readtext(enhanced, detail=1, paragraph=False)

            text_lines = [t[1].strip() for t in results if t[1].strip()]
            raw_text = "\n".join(text_lines)

            parsed = MultiDocumentParser.parse(raw_text, doc_hint="auto")
            elapsed = round(time.time() - t0, 2)

            data = parsed.model_dump()
            data["processing_time"] = f"{elapsed}s"

            # Auto-save to SQLite local DB
            try:
                doc_id = local_db.save_document(
                    extracted_data=data,
                    raw_text=raw_text,
                    filename=os.path.basename(image_path),
                    file_bytes=raw_bytes,
                    confidence_score=0.9
                )
                data["local_id"] = doc_id
            except Exception:
                data["local_id"] = "Erro ao salvar"

            self.current_result = data
            self.after(0, lambda: self._on_ocr_success(data, elapsed))

        except Exception as err:
            self.after(0, lambda: self._on_ocr_error(str(err)))

    def _on_ocr_success(self, data: dict, elapsed: float):
        doc_type = data.get("document_type", "rg").upper()
        self.doc_type_lbl.config(text=f"DADOS EXTRAÍDOS • {doc_type}")
        self.status_var.set(f"✅ OCR Concluído em {elapsed}s | Salvo no SQLite local (ID: {data.get('local_id')})")
        self.btn_copy_json.configure(state="normal")

        for key, entry in self.field_widgets.items():
            entry.delete(0, tk.END)
            val = data.get(key)
            if key == "cpf_valid":
                val = "✅ SIM (Módulo 11)" if val else ("❌ NÃO" if data.get("cpf") else "")
            elif key == "mrz_valid":
                val = "✅ SIM (ICAO 9303)" if val else ("" if not data.get("mrz_lines") else "❌ NÃO")
            elif key == "issuing_organ":
                organ = data.get("issuing_organ") or ""
                uf = data.get("issuing_state") or ""
                val = f"{organ}/{uf}".strip("/")
            
            if val is not None:
                entry.insert(0, str(val))

    def _on_ocr_error(self, err_msg: str):
        self.status_var.set(f"❌ Erro no OCR: {err_msg}")
        messagebox.showerror("Erro de Extração", f"Ocorreu um erro ao processar o documento:\n\n{err_msg}")

    def _display_preview(self, image_path: str):
        if not HAS_PIL:
            self.img_canvas.config(text=f"Carregado:\n{os.path.basename(image_path)}")
            return
        try:
            pil_img = Image.open(image_path)
            pil_img.thumbnail((380, 520), Image.Resampling.LANCZOS)
            tk_img = ImageTk.PhotoImage(pil_img)
            self.img_canvas.config(image=tk_img, text="")
            self.img_canvas.image = tk_img
        except Exception:
            self.img_canvas.config(text=f"Carregado:\n{os.path.basename(image_path)}")

    def _copy_json(self):
        if self.current_result:
            self.clipboard_clear()
            self.clipboard_append(json.dumps(self.current_result, indent=2, ensure_ascii=False))
            self.status_var.set("📋 JSON copiado para a área de transferência!")

if __name__ == "__main__":
    app = DocumentScannerApp()
    app.mainloop()
