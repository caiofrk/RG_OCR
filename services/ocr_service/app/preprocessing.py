import io
import cv2
import numpy as np
from PIL import Image

class ImagePreprocessor:
    """
    Image preprocessing pipeline for Brazilian Identity Documents (RG / CNH).
    Optimized for zero-cost low-resource environments (Google Cloud e2-micro / local CPU).
    """

    @staticmethod
    def load_image_from_bytes(image_bytes: bytes) -> np.ndarray:
        """Decode raw image bytes into an OpenCV BGR numpy array while preserving EXIF orientation."""
        try:
            from PIL import Image, ImageOps
            import io
            pil_img = Image.open(io.BytesIO(image_bytes))
            pil_img = ImageOps.exif_transpose(pil_img) # Apply EXIF rotation
            pil_img = pil_img.convert("RGB")
            return cv2.cvtColor(np.array(pil_img), cv2.COLOR_RGB2BGR)
        except Exception:
            # Fallback to direct OpenCV decode if PIL fails
            nparr = np.frombuffer(image_bytes, np.uint8)
            return cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    @staticmethod
    def resize_for_ocr(image: np.ndarray, max_dim: int = 2000, min_dim: int = 800) -> np.ndarray:
        """
        Normalize image dimensions for OCR.
        Prevents tiny text unreadability while keeping processing fast on low-end CPUs.
        """
        h, w = image.shape[:2]
        longest = max(h, w)
        shortest = min(h, w)

        if longest > max_dim:
            scale = max_dim / float(longest)
            image = cv2.resize(image, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_AREA)
        elif shortest < min_dim:
            scale = min_dim / float(shortest)
            image = cv2.resize(image, (int(w * scale), int(h * scale)), interpolation=cv2.INTER_CUBIC)

        return image

    @staticmethod
    def deskew(image: np.ndarray) -> np.ndarray:
        """
        Detect and correct small skew angles often present in photo captures of RG cards.
        """
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        # Invert colors so text is white
        thresh = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV | cv2.THRESH_OTSU)[1]
        
        # Find coordinates of all foreground pixels
        coords = np.column_stack(np.where(thresh > 0))
        if len(coords) < 100:
            return image

        # Calculate minimum bounding rotated rectangle
        angle = cv2.minAreaRect(coords)[-1]
        if angle < -45:
            angle = -(90 + angle)
        else:
            angle = -angle

        # If angle is negligible, do not rotate
        if abs(angle) < 0.5 or abs(angle) > 45.0:
            return image

        (h, w) = image.shape[:2]
        center = (w // 2, h // 2)
        m = cv2.getRotationMatrix2D(center, angle, 1.0)
        rotated = cv2.warpAffine(
            image, m, (w, h),
            flags=cv2.INTER_CUBIC,
            borderMode=cv2.BORDER_REPLICATE
        )
        return rotated

    @staticmethod
    def enhance_contrast_and_denoise(image: np.ndarray) -> np.ndarray:
        """
        Applies bilateral filtering and CLAHE (Contrast Limited Adaptive Histogram Equalization)
        to remove watermarks, guilloche patterns, and plastic reflection common on Brazilian RG cards.
        """
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        
        # Bilateral filter preserves sharp edges while smoothing background gradients
        denoised = cv2.bilateralFilter(gray, d=9, sigmaColor=75, sigmaSpace=75)
        
        # CLAHE for localized contrast enhancement
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(denoised)
        
        return enhanced

    @staticmethod
    def binarize(gray_image: np.ndarray) -> np.ndarray:
        """
        Produce a crisp black-and-white binary image using Otsu thresholding with slight Gaussian blur.
        """
        blur = cv2.GaussianBlur(gray_image, (5, 5), 0)
        _, thresh = cv2.threshold(blur, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        return thresh

    @classmethod
    def process_pipeline(cls, image_bytes: bytes) -> tuple[np.ndarray, np.ndarray]:
        """
        Executes full preprocessing pipeline.
        Returns:
            (enhanced_grayscale_image, binary_image)
        """
        raw_img = cls.load_image_from_bytes(image_bytes)
        resized = cls.resize_for_ocr(raw_img)
        deskewed = cls.deskew(resized)
        enhanced = cls.enhance_contrast_and_denoise(deskewed)
        binary = cls.binarize(enhanced)
        return enhanced, binary
