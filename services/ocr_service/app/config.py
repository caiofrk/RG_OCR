import os
from pydantic import BaseModel

class Settings(BaseModel):
    app_name: str = "RG_OCR Document Service"
    version: str = "1.0.0"
    host: str = os.getenv("OCR_SERVICE_HOST", "0.0.0.0")
    port: int = int(os.getenv("OCR_SERVICE_PORT", "8000"))
    api_key: str = os.getenv("OCR_API_KEY", "rg_ocr_secret_token_change_in_production")
    max_image_size_mb: int = int(os.getenv("OCR_MAX_IMAGE_SIZE_MB", "25"))
    allowed_extensions: list[str] = [".jpg", ".jpeg", ".png", ".webp", ".pdf"]

settings = Settings()
