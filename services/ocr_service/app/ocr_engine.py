import io
import shutil
import cv2
import pymupdf as fitz  # PyMuPDF
from PIL import Image
from .preprocessing import ImagePreprocessor
from .parser import MultiDocumentParser
from .schemas import ExtractedDocumentData

class OCREngine:
    """
    Zero-cost modular OCR processing engine.
    Extracts text from PDF documents natively or image files using preprocessed CV pipeline + EasyOCR / Tesseract.
    """

    def __init__(self):
        self.easyocr_reader = None
        self.has_tesseract = shutil.which("tesseract") is not None
        if self.has_tesseract:
            try:
                import pytesseract
                self.pytesseract = pytesseract
            except ImportError:
                self.has_tesseract = False

    def _get_easyocr_reader(self):
        """Lazy load EasyOCR reader for maximum precision."""
        if self.easyocr_reader is None:
            try:
                import easyocr
                # Enable GPU support since this will run locally on the RTX 5050
                self.easyocr_reader = easyocr.Reader(['pt', 'en'], gpu=True)
            except Exception as e:
                print(f"[!] Failed to load EasyOCR: {e}")
        return self.easyocr_reader

    def extract_from_pdf(self, pdf_bytes: bytes) -> str:
        """Extracts text from PDF using PyMuPDF (fitz) - lightning fast & free."""
        text_parts = []
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
        for page in doc:
            text = page.get_text()
            if text:
                text_parts.append(text)
        doc.close()
        return "\n".join(text_parts)

    def extract_from_image(self, image_bytes: bytes) -> str:
        """
        Processes image through OpenCV preprocessing pipeline and runs OCR extraction.
        Implements Auto-Rotation by checking 4 orientations (0, 90, 180, 270) with EasyOCR.
        """
        enhanced, binary = ImagePreprocessor.process_pipeline(image_bytes)

        # 1. Primary Engine: EasyOCR (zero-cost, embedded local model)
        reader = self._get_easyocr_reader()
        if reader is not None:
            best_text = ""
            best_char_count = 0
            current_img = enhanced
            
            # Key anchors that confidently tell us the document is correctly oriented
            anchors = {"CPF", "NOME", "BRASIL", "REPUBLICA", "CARTEIRA", "IDENTIDADE", "REGISTRO", "DETRAN"}
            
            for _ in range(4):
                try:
                    lines = reader.readtext(current_img, detail=0, paragraph=False)
                    text = "\n".join(lines)
                    text_upper = text.upper()
                    
                    # Stop early if we find at least 2 strong anchors indicating correct orientation
                    if sum(anchor in text_upper for anchor in anchors) >= 2:
                        return text
                        
                    char_count = len(text.replace(" ", "").replace("\n", ""))
                    if char_count > best_char_count:
                        best_char_count = char_count
                        best_text = text
                        
                except Exception as e:
                    print(f"[!] EasyOCR execution failed during rotation check: {e}")
                    
                # Rotate 90 degrees clockwise for next attempt
                current_img = cv2.rotate(current_img, cv2.ROTATE_90_CLOCKWISE)
                
            if best_text.strip():
                return best_text

        # 2. Secondary Engine: Tesseract (Fallback if EasyOCR is completely broken/unavailable)
        if self.has_tesseract:
            try:
                # Basic tesseract run without auto-rotation to save time on fallback
                text_enhanced = self.pytesseract.image_to_string(enhanced, lang="por+eng")
                text_binary = self.pytesseract.image_to_string(binary, lang="por+eng")
                text = text_enhanced + "\n" + text_binary
                if text.strip():
                    return text
            except Exception:
                pass

        return ""

    def process_document(self, file_bytes: bytes, filename: str, doc_hint: str = "auto") -> tuple[ExtractedDocumentData, str]:
        """
        End-to-end extraction and parsing for any uploaded identity document:
        RG, CNH, Passport, or CIN.
        """
        is_pdf = filename.lower().endswith(".pdf")
        raw_text = ""

        if is_pdf:
            raw_text = self.extract_from_pdf(file_bytes)
            if not raw_text.strip():
                doc = fitz.open(stream=file_bytes, filetype="pdf")
                if len(doc) > 0:
                    page = doc[0]
                    pix = page.get_pixmap(dpi=200)
                    img_bytes = pix.tobytes("png")
                    raw_text = self.extract_from_image(img_bytes)
                doc.close()
        else:
            raw_text = self.extract_from_image(file_bytes)

        parsed_data = MultiDocumentParser.parse(raw_text, doc_hint=doc_hint)
        return parsed_data, raw_text

ocr_engine = OCREngine()
