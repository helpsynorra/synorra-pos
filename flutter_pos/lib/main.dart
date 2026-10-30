import 'dart:async';

import 'package:flutter/material.dart';
import 'services/local_storage_service.dart';
import 'services/supabase_service.dart';
import 'services/sync_service.dart';
import 'state/pos_controller.dart';
import 'ui/theme.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/pos_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(SynorraPosApp(initialization: _initializeController()));
}

Future<PosController> _initializeController() async {
  // 1. Initialize Local-First persistent storage
  final localStorage = LocalStorageService();
  await localStorage.init();

  // 2. Initialize Centralized Backend & Supabase Client
  final supabaseService = SupabaseService();
  await supabaseService.initialize(
    url: localStorage.getSupabaseUrl(),
    anonKey: localStorage.getSupabaseAnonKey(),
    adminApiUrl: localStorage.getAdminApiUrl(),
  );

  // 3. Initialize Background & Real-Time Auto-Sync Service
  final syncService = SyncService(
    localStorage: localStorage,
    supabaseService: supabaseService,
  );

  // 4. Initialize State Controller (registers sync listener & pulls fresh Admin data)
  final posController = PosController(
    localStorage: localStorage,
    supabaseService: supabaseService,
    syncService: syncService,
  );
  await posController.init();
  return posController;
}

class SynorraPosApp extends StatelessWidget {
  final Future<PosController> initialization;

  const SynorraPosApp({super.key, required this.initialization});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Synorra',
      debugShowCheckedModeBanner: false,
      theme: SynorraTheme.theme,
      home: FutureBuilder<PosController>(
        future: initialization,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return _ReadyApp(controller: snapshot.data!);
          }
          if (snapshot.hasError) {
            return _StartupErrorScreen(error: snapshot.error);
          }
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Image.asset(
                'lib/src/images/sn-logo-transparent.png',
                width: 240,
                height: 110,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final Object? error;

  const _StartupErrorScreen({this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'lib/src/images/sn-logo-transparent.png',
                width: 200,
                height: 90,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              const Text(
                'Synorra could not start',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SelectableText(
                '$error',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadyApp extends StatefulWidget {
  final PosController controller;

  const _ReadyApp({required this.controller});

  @override
  State<_ReadyApp> createState() => _ReadyAppState();
}

class _ReadyAppState extends State<_ReadyApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_startBackgroundServices());
    });
  }

  Future<void> _startBackgroundServices() async {
    try {
      await widget.controller.localStorage.migrateLegacyStaffCredentials();
    } catch (_) {
      // Keep startup available if an old credential cannot be migrated.
    }
    if (mounted) widget.controller.syncService.start();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return controller.currentUser == null
        ? LoginScreen(controller: controller)
        : PosScreen(controller: controller);
  }
}
