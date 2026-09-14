import io
import shutil
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
        """Disabled by default to prevent OOM on 512MB RAM free-tiers."""
        return None

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
        Prioritizes EasyOCR (PyTorch local model) with fallback to Tesseract.
        """
        enhanced, binary = ImagePreprocessor.process_pipeline(image_bytes)

        # 1. Primary Engine: EasyOCR (zero-cost, embedded local model)
        reader = self._get_easyocr_reader()
        if reader is not None:
            try:
                lines = reader.readtext(enhanced, detail=0, paragraph=False)
                if lines:
                    return "\n".join(lines)
            except Exception as e:
                print(f"[!] EasyOCR execution failed, falling back: {e}")

        # 2. Secondary Engine: Tesseract (if installed)
        if self.has_tesseract:
            try:
                text = self.pytesseract.image_to_string(binary, lang="por+eng")
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
