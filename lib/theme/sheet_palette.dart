import 'package:flutter/material.dart';

/// Colori del documento, separati dai controlli Material e dalle fotografie.
class SheetPalette {
  const SheetPalette({
    required this.workspace,
    required this.paper,
    required this.ink,
    required this.text,
    required this.accent,
    required this.comment,
    required this.expertise,
  });

  final Color workspace;
  final Color paper;
  final Color ink;
  final Color text;
  final Color accent;
  final Color comment;
  final Color expertise;

  static const light = SheetPalette(
    workspace: Color(0xffdedbd2),
    paper: Colors.white,
    ink: Colors.black,
    text: Colors.black,
    accent: Color(0xff7b1f1f),
    comment: Color(0xffd32f2f),
    expertise: Color(0xffc62828),
  );

  static const dark = SheetPalette(
    workspace: Color(0xff111418),
    paper: Color(0xff202329),
    ink: Color(0xffddd8cd),
    text: Color(0xfff2eadb),
    accent: Color(0xffe5bd78),
    comment: Color(0xffffa08e),
    expertise: Color(0xffffa08e),
  );

  static SheetPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class SheetArtwork extends StatelessWidget {
  const SheetArtwork({super.key, required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    // Precomputed artwork avoids full-page GPU filter passes while panning.
    // Uploaded pictures are separate widgets and keep their original pixels.
    final suffix = Theme.of(context).brightness == Brightness.dark
        ? '-dark'
        : '';
    return ColoredBox(
      color: palette.paper,
      child: Image.asset(
        'assets/sheet/page-${pageIndex + 1}$suffix.png',
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
