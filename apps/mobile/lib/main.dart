import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/theme/theme.dart';

void main() {
  runApp(const ProviderScope(child: DayflowApp()));
}

class DayflowApp extends ConsumerWidget {
  const DayflowApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
