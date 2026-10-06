import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppMessageType { success, error, warning, info }

/// One look for every message in the app: a floating card with an icon and
/// a colour that says at a glance whether something worked.
void showAppSnackBar(
  BuildContext context,
  String message, {
  AppMessageType type = AppMessageType.info,
  SnackBarAction? action,
  Duration? duration,
}) {
  final (icon, color) = switch (type) {
    AppMessageType.success => (Icons.check_circle_rounded, AppColors.teal),
    AppMessageType.error => (Icons.error_rounded, AppColors.orange),
    AppMessageType.warning => (Icons.warning_amber_rounded, AppColors.amber),
    AppMessageType.info => (Icons.info_rounded, const Color(0xFF8FB4FF)),
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message,
              style: const TextStyle(color: Colors.white, height: 1.35)),
        ),
      ]),
      action: action,
      // A SnackBar with an action stays until dismissed unless persist is
      // false (Flutter 3.35+).
      persist: false,
      duration: duration ??
          (type == AppMessageType.error || action != null
              ? const Duration(seconds: 5)
              : const Duration(seconds: 3)),
    ));
}
