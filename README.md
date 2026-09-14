# RG_OCR: Intelligent Multi-Document Scanner & OCR Extraction Suite

A dedicated, high-accuracy document scanning and optical character recognition (OCR) extraction suite for Brazilian and international identification documents: **RG Tradicional, Nova CIN (Carteira de Identidade Nacional), CNH (Carteira Nacional de Habilitação), Passaportes (ICAO Doc 9303 MRZ Engine), and CPF**.

---

## Supported Document Types & Features

| Document Type | Key Data Fields Extracted | Verification Algorithm |
| :--- | :--- | :--- |
| **Passaporte (Passport)** | Nome Completo, Sobrenome, Nome Próprio, Número do Passaporte, Nacionalidade, País Emissor, Data de Nascimento, Sexo, Validade | **ICAO Doc 9303 MRZ Engine** (TD3 & TD1) with 7-3-1 weighting check-digit verification |
| **CNH (Habilitação)** | Nome, CPF, Nº Registro, RENACH, Categoria (A, B, AB, C, D, E), Validade, 1ª Habilitação, Local/Data de Emissão | CPF checksum + RENACH pattern validation |
| **RG Tradicional** | Nome Completo, Registro Geral (RG), CPF, Filiação (Mãe/Pai), Naturalidade, Órgão Emissor / UF, Data de Expedição | CPF modulus 11 + RG state pattern detection |
| **Nova CIN (Identidade)** | Nome Completo, CPF unificado, Filiação, Naturalidade, Órgão Emissor, Validade, Código MRZ | CPF modulus 11 checksum + ICAO TD1 validation |
| **CPF** | Número do CPF | Algoritmo oficial de verificação dos dígitos 1 e 2 (módulo 11) |

---

## Architecture

```
+---------------------------------------------------------------------------------------+
|                               DOCUMENT SCANNER UI                                     |
|  Flutter Multi-Platform Client (Web, Desktop, Mobile)                                |
|  - File & Camera Ingestion (JPG, PNG, WEBP, PDF)                                      |
|  - Document Selector: Auto-Detect | RG | CIN | CNH | Passaporte (MRZ) | CPF           |
|  - Side-by-Side Inspector: Document Preview & Interactive Editable Fields Form         |
|  - Validation Badges: CPF Validado, MRZ ICAO Validado, Confiança da Extração         |
|  - Export Suite: One-click export to JSON, CSV, or Clipboard                          |
|  - Batch Processing: Multi-file queue processing                                      |
+------------------------------------------+--------------------------------------------+
                                           | Multipart REST API
                                           v
+------------------------------------------+--------------------------------------------+
|                                OCR BACKEND ENGINE                                     |
|  Python FastAPI Microservice (services/ocr_service)                                   |
|  1. Image Processing: OpenCV bilateral filtering, deskewing, Otsu binarization       |
|  2. Document Classifiers: Auto-detection of document layout and markers               |
|  3. ICAO Doc 9303 MRZ Parser: Mathematical 7-3-1 checksum validation                  |
|  4. Brazilian Document Parser: Modulus 11 CPF check, CNH RENACH & category extraction |
+---------------------------------------------------------------------------------------+
```

---

## Project Structure

```
RG_OCR/
├── apps/
│   └── crm_app/                         # Flutter Document Scanner UI (Desktop/Web/Mobile)
│       ├── lib/
│       │   ├── core/                    # AppTheme, OCRClientService, SupabaseService
│       │   ├── features/
│       │   │   └── scanner/             # Dashboard, Batch Processing, Models, Providers
│       │   ├── routes/                  # GoRouter configuration
│       │   └── main.dart
│       └── test/                        # Flutter widget tests
├── services/
│   └── ocr_service/                     # Python FastAPI OCR & MRZ Microservice
│       ├── app/
│       │   ├── main.py                  # API endpoints (/process-document, /parse-mrz)
│       │   ├── mrz_parser.py            # ICAO 9303 MRZ Engine (Passports TD3 & TD1)
│       │   ├── parser.py                # MultiDocumentParser (RG, CNH, CIN, CPF)
│       │   ├── preprocessing.py         # OpenCV image normalization & deskewing
│       │   └── ocr_engine.py            # PyMuPDF & OCR pipeline
│       ├── tests/                       # Unit tests (unittest)
│       └── requirements.txt
├── supabase/
│   ├── schema.sql                       # Database schema for scanned document logs
│   └── seed.sql                         # Sample scanned documents and storage bucket
├── .env.example
└── .gitignore
```

---

## Quick Start

### 1. Run the Local OCR Script on Any Image (Instant Local Extraction)
To process an image directly without running web servers or emulators:
```powershell
# Run on any image
python scan_document.py <caminho_da_imagem>

# Example: test with our sample document
python scan_document.py test_document.jpg

# Or export structured JSON directly
python scan_document.py test_document.jpg --json
```

### 2. Run the Python OCR Microservice (API)
```powershell
# From the repository root
py -m uvicorn services.ocr_service.app.main:app --host 0.0.0.0 --port 8000 --reload
```
Interactive Swagger API documentation will be available at: `http://127.0.0.1:8000/docs`.

### 2. Run the Document Scanner Application
```powershell
cd apps/crm_app

# Run on Chrome (Web)
flutter run -d chrome

# Or run natively on Windows Desktop
flutter run -d windows
```

### 3. Run Automated Tests
```powershell
# Run Python unit tests (Passports, CNH, RG, MRZ & Checksum tests)
py -m unittest services/ocr_service/tests/test_parser.py

# Run Flutter analysis and widget tests
cd apps/crm_app
flutter analyze
flutter test
```

---

## 🤖 Running & Debugging on Android Studio

The workspace is pre-configured for running, testing, and debugging on **Android Studio** out-of-the-box:

### 1. Open the Project
- Launch **Android Studio**.
- Click **File > Open** and choose either:
  - **The workspace root** (`RG_OCR`): Recommended. All modules (`RG_OCR`, `crm_app`, and `crm_app_android`) are pre-indexed with ready-to-run configurations.
  - Or directly the Flutter subfolder (`apps/crm_app`).

### 2. Select Run Configuration
- In the top toolbar run configuration dropdown, select:
  - **`Run Document Scanner`**: Standard run/debug configuration.
  - **`Run Document Scanner (Android Emulator 10.0.2.2)`**: Automatically sets `--dart-define=OCR_BASE_URL=http://10.0.2.2:8000` to seamlessly reach your host Python OCR microservice from the Android emulator.

### 3. Connect Emulator or Device
- Start any Android Virtual Device (AVD) from Android Studio's **Device Manager** (API 21+ supported, API 34/36 tested).
- Click the green **Run** (▶) or **Debug** (🪲) button.
- Breakpoints in Dart (`apps/crm_app/lib/...`) will hit in Android Studio immediately.

### 4. Permissions & Networking
- **Camera & Storage**: Configured in `AndroidManifest.xml` with `android.permission.CAMERA`, `READ_EXTERNAL_STORAGE`, and `READ_MEDIA_IMAGES`.
- **Local Microservice Communication**: Cleartext traffic to `10.0.2.2` (the Android emulator host loopback) is permitted in `res/xml/network_security_config.xml`.
- **Automatic IP Detection**: `AppConstants.ocrBaseUrl` automatically defaults to `http://10.0.2.2:8000` when running on Android emulators and `http://127.0.0.1:8000` on Desktop/Web.

