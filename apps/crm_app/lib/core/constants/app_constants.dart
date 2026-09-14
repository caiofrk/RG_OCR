class AppConstants {
  // Supabase default placeholders (configured via .env or String.fromEnvironment)
  static const String defaultSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://demo-project.supabase.co',
  );

  static const String defaultSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'demo-anon-key',
  );

  // Microservice OCR URL: Defaults to 127.0.0.1:8000 (works directly via ADB reverse on physical phones
  // and on Desktop/Web). Can be overridden via --dart-define=OCR_BASE_URL=...
  static String get ocrBaseUrl {
    const envUrl = String.fromEnvironment('OCR_BASE_URL', defaultValue: '');
    if (envUrl.isNotEmpty) return envUrl;
    
    // Default to the live Render backend for web deployments
    return 'https://rg-ocr-backend.onrender.com';
  }

  // Storage Buckets
  static const String documentsBucket = 'client-documents';
}
