import 'package:flutter/material.dart';

import '../theme/theme_preferences.dart';

class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = ThemePreferenceScope.maybeOf(context);
    if (preferences == null) return const SizedBox.shrink();
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Aspetto',
      initialValue: preferences.mode,
      icon: Icon(switch (preferences.mode) {
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
        ThemeMode.system => Icons.brightness_auto_outlined,
      }),
      onSelected: (mode) async {
        try {
          await preferences.setMode(mode);
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tema applicato, ma non salvato. Riprova.'),
            ),
          );
        }
      },
      itemBuilder: (_) => [
        for (final entry in const {
          ThemeMode.light: 'Chiaro',
          ThemeMode.dark: 'Scuro',
          ThemeMode.system: 'Sistema',
        }.entries)
          CheckedPopupMenuItem(
            value: entry.key,
            checked: preferences.mode == entry.key,
            child: Text(entry.value),
          ),
      ],
    );
  }
}
