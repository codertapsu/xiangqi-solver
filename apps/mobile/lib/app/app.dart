import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_constants.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Root application widget: wires theming and the [GoRouter].
class XiangqiSolverApp extends StatefulWidget {
  const XiangqiSolverApp({super.key});

  @override
  State<XiangqiSolverApp> createState() => _XiangqiSolverAppState();
}

class _XiangqiSolverAppState extends State<XiangqiSolverApp> {
  late final GoRouter _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}
