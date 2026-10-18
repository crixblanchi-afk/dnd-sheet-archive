import 'package:flutter/material.dart';

import '../theme/theme_preferences.dart';

class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = ThemePreferenceScope.maybeOf(context);
    if (preferences == null) return const SizedBox.shrink();
    return PopupMenuButton<AppTheme>(
      tooltip: 'Aspetto',
      initialValue: preferences.theme,
      icon: Icon(switch (preferences.theme) {
        AppTheme.light => Icons.light_mode_outlined,
        AppTheme.dark => Icons.dark_mode_outlined,
        AppTheme.lightColored || AppTheme.darkColored => Icons.palette_outlined,
        AppTheme.system => Icons.brightness_auto_outlined,
      }),
      onSelected: (theme) async {
        try {
          await preferences.setTheme(theme);
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
        for (final theme in AppTheme.values)
          CheckedPopupMenuItem(
            value: theme,
            checked: preferences.theme == theme,
            child: Text(theme.label),
          ),
      ],
    );
  }
}
