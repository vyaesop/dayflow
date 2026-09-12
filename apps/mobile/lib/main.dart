import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/realtime/realtime_client.dart';
import 'core/theme/theme.dart';

void main() {
  // A release build without an API origin would silently point at a dev
  // loopback address and appear dead on launch. Fail loudly and legibly.
  const apiBaseUrl = String.fromEnvironment('API_BASE_URL');
  if (kReleaseMode && apiBaseUrl.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }

  runApp(const ProviderScope(child: DayflowApp()));
}

class DayflowApp extends ConsumerStatefulWidget {
  const DayflowApp({super.key});

  @override
  ConsumerState<DayflowApp> createState() => _DayflowAppState();
}

class _DayflowAppState extends ConsumerState<DayflowApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Backoff timers pause with the app; returning to the foreground should
    // re-establish live updates immediately, not after the backoff runs out.
    _lifecycle = AppLifecycleListener(onResume: RealtimeClient.instance.reconnectNow);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Dayflow',
      debugShowCheckedModeBanner: false,
      theme: dayflowLightTheme(),
      darkTheme: dayflowDarkTheme(),
      routerConfig: router,
    );
  }
}

/// Shown instead of the app when a release build was produced without
/// `--dart-define=API_BASE_URL=...` — a build mistake that must be visible.
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dayflow',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.build_circle_outlined, size: 48),
              const SizedBox(height: 16),
              Text('This build is misconfigured', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'It was compiled without an API address. Rebuild with\n'
                '--dart-define=API_BASE_URL=https://…',
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
