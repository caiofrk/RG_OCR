import 'package:go_router/go_router.dart';
import '../features/scanner/screens/scanner_dashboard_screen.dart';
import '../features/scanner/screens/batch_scanner_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const ScannerDashboardScreen(),
    ),
    GoRoute(
      path: '/batch',
      builder: (context, state) => const BatchScannerScreen(),
    ),
  ],
);
