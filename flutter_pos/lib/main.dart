import 'dart:math' as math;

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
  syncService.start();
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
            final controller = snapshot.data!;
            return controller.currentUser == null
                ? LoginScreen(controller: controller)
                : PosScreen(controller: controller);
          }
          return const SynorraLaunchScreen();
        },
      ),
    );
  }
}

class SynorraLaunchScreen extends StatefulWidget {
  const SynorraLaunchScreen({super.key});

  @override
  State<SynorraLaunchScreen> createState() => _SynorraLaunchScreenState();
}

class _SynorraLaunchScreenState extends State<SynorraLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _entranceController,
      builder: (context, _) {
        final progress = _entranceController.value;
        final spring = Curves.easeOutBack.transform(progress);
        final brandPulse = math
            .sin((progress / 0.55).clamp(0.0, 1.0) * math.pi)
            .clamp(0.0, 1.0)
            .toDouble();
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0, -0.08),
                    radius: 0.95,
                    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: 0.7 + 0.3 * spring,
                      child: Opacity(
                        opacity: progress.clamp(0.0, 1.0).toDouble(),
                        child: Container(
                          width: 196,
                          height: 148,
                          padding: const EdgeInsets.all(25),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x4483B8FF),
                                blurRadius: 44,
                                spreadRadius: 2,
                                offset: Offset(0, 15),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              Center(
                                child: Image.asset(
                                  'lib/src/images/logo_wordmark.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                              Positioned(
                                left: 78,
                                top: 34,
                                child: Opacity(
                                  opacity: brandPulse,
                                  child: Container(
                                    width: 19,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0x88E34040),
                                          blurRadius: 15,
                                          spreadRadius: 3,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Opacity(
                      opacity: Curves.easeIn.transform(
                        ((progress - 0.42) / 0.58).clamp(0.0, 1.0).toDouble(),
                      ),
                      child: const Text(
                        'Build Smarter. Grow Together.',
                        style: TextStyle(
                          color: Color(0xFF91A2BB),
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
