import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'routes/app_router.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase with graceful dev fallback
  try {
    if (AppConstants.defaultSupabaseUrl != 'https://demo-project.supabase.co') {
      await Supabase.initialize(
        url: AppConstants.defaultSupabaseUrl,
        // ignore: deprecated_member_use
        anonKey: AppConstants.defaultSupabaseAnonKey,
      );
    }
  } catch (e) {
    debugPrint('Supabase initial connection note: $e');
  }

  runApp(
    const ProviderScope(
      child: DocumentScannerApp(),
    ),
  );
}

class DocumentScannerApp extends StatelessWidget {
  const DocumentScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RG_OCR • Extrator de Documentos',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      routerConfig: appRouter,
    );
  }
}
