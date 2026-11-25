import 'package:flutter/material.dart';

import '../theme/sheet_palette.dart';

/// Sfondo ombreggiato con cornice leggera che raggruppa i blocchi affini
/// (caratteristiche, combattimento, personalità, incantesimi), come i pannelli
/// grigi della scheda originale D&D 5e.
class SheetTray extends StatelessWidget {
  const SheetTray({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      isComplex: true,
      painter: _SheetTrayPainter(
        fill: palette.ink.withValues(alpha: isDark ? .10 : .07),
        stroke: palette.ink.withValues(alpha: isDark ? .26 : .18),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SheetTrayPainter extends CustomPainter {
  const _SheetTrayPainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _chamferedRect(Offset.zero & size, 10);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final inner = _chamferedRect((Offset.zero & size).deflate(3), 8);
    canvas.drawPath(
      inner,
      Paint()
        ..color = stroke.withValues(alpha: stroke.a * .65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75,
    );
  }

  @override
  bool shouldRepaint(_SheetTrayPainter oldDelegate) =>
      fill != oldDelegate.fill || stroke != oldDelegate.stroke;
}

/// Riquadro principale in stile scheda D&D 5e: carta piena, doppio bordo a
/// inchiostro con angoli smussati/intagliati e didascalia maiuscola in basso.
class SheetFrameBox extends StatelessWidget {
  const SheetFrameBox({
    super.key,
    required this.child,
    this.caption,
    this.topTrailing,
    this.padding = const EdgeInsets.fromLTRB(12, 10, 12, 8),
  });

  final Widget child;
  final String? caption;
  final Widget? topTrailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return CustomPaint(
      isComplex: true,
      painter: _NotchedBoxPainter(paper: palette.paper, ink: palette.ink),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (topTrailing != null)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: topTrailing!,
                ),
              ),
            child,
            if (caption != null) ...[
              const SizedBox(height: 6),
              Text(
                caption!.toUpperCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFamily: 'RobotoSlab',
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .75,
                  color: palette.ink,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotchedBoxPainter extends CustomPainter {
  const _NotchedBoxPainter({required this.paper, required this.ink});

  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final outerRect = (Offset.zero & size).deflate(.9);
    final outer = _notchedCornerPath(outerRect, 7);
    canvas.drawPath(outer, Paint()..color = paper);
    canvas.drawPath(
      outer,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.miter,
    );
    final inner = _chamferedRect(outerRect.deflate(2.8), 4.5);
    canvas.drawPath(
      inner,
      Paint()
        ..color = ink.withValues(alpha: .42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
  }

  @override
  bool shouldRepaint(_NotchedBoxPainter oldDelegate) =>
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}

/// Nastro araldico in alto per il nome del personaggio, ispirato al cartiglio
/// della testata di pagina 1 e 2.
class SheetBannerBox extends StatelessWidget {
  const SheetBannerBox({super.key, required this.child, required this.caption});

  final Widget child;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomPaint(
          isComplex: true,
          painter: _RibbonBannerPainter(paper: palette.paper, ink: palette.ink),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
            child: child,
          ),
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            caption.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontFamily: 'RobotoSlab',
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
              color: palette.ink.withValues(alpha: .85),
            ),
          ),
        ),
      ],
    );
  }
}

class _RibbonBannerPainter extends CustomPainter {
  const _RibbonBannerPainter({required this.paper, required this.ink});

  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const ear = 10.0;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;
    final earFill = Paint()..color = ink.withValues(alpha: .08);

    // Code laterali del cartiglio.
    final leftEar = Path()
      ..moveTo(ear, 6)
      ..lineTo(1, 9)
      ..lineTo(1, h - 6)
      ..lineTo(ear, h - 9)
      ..close();
    final rightEar = Path()
      ..moveTo(w - ear, 6)
      ..lineTo(w - 1, 9)
      ..lineTo(w - 1, h - 6)
      ..lineTo(w - ear, h - 9)
      ..close();
    canvas
      ..drawPath(leftEar, Paint()..color = paper)
      ..drawPath(leftEar, earFill)
      ..drawPath(leftEar, stroke)
      ..drawPath(rightEar, Paint()..color = paper)
      ..drawPath(rightEar, earFill)
      ..drawPath(rightEar, stroke);

    // Corpo centrale del nastro.
    final bodyRect = Rect.fromLTRB(ear, 1.5, w - ear, h - 1.5);
    final body = _notchedCornerPath(bodyRect, 5.5);
    canvas
      ..drawPath(body, Paint()..color = paper)
      ..drawPath(body, stroke);
    final inner = _chamferedRect(bodyRect.deflate(2.8), 3.5);
    canvas.drawPath(
      inner,
      Paint()
        ..color = ink.withValues(alpha: .42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
  }

  @override
  bool shouldRepaint(_RibbonBannerPainter oldDelegate) =>
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}

/// Scudo araldico a doppio contorno per la Classe Armatura.
class ArmorClassShield extends StatelessWidget {
  const ArmorClassShield({
    super.key,
    required this.child,
    this.caption = 'CLASSE\nARMATURA',
  });

  final Widget child;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return CustomPaint(
      isComplex: true,
      painter: _ArmorShieldPainter(paper: palette.paper, ink: palette.ink),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            child,
            const SizedBox(height: 2),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFamily: 'RobotoSlab',
                fontSize: 8.2,
                height: 1.05,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
                color: palette.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArmorShieldPainter extends CustomPainter {
  const _ArmorShieldPainter({required this.paper, required this.ink});

  final Color paper;
  final Color ink;

  Path _shieldPath(Rect r) {
    final w = r.width;
    final h = r.height;
    final l = r.left;
    final t = r.top;
    return Path()
      ..moveTo(l + w * .5, t)
      ..quadraticBezierTo(l + w * .76, t + h * .09, l + w * .97, t + h * .08)
      ..lineTo(l + w * .97, t + h * .52)
      ..cubicTo(
        l + w * .95,
        t + h * .77,
        l + w * .72,
        t + h * .91,
        l + w * .5,
        t + h,
      )
      ..cubicTo(
        l + w * .28,
        t + h * .91,
        l + w * .05,
        t + h * .77,
        l + w * .03,
        t + h * .52,
      )
      ..lineTo(l + w * .03, t + h * .08)
      ..quadraticBezierTo(l + w * .24, t + h * .09, l + w * .5, t)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outer = _shieldPath((Offset.zero & size).deflate(1));
    canvas.drawPath(outer, Paint()..color = paper);
    canvas.drawPath(
      outer,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.7
        ..strokeJoin = StrokeJoin.round,
    );
    final inner = _shieldPath((Offset.zero & size).deflate(4));
    canvas.drawPath(
      inner,
      Paint()
        ..color = ink.withValues(alpha: .5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .85
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ArmorShieldPainter oldDelegate) =>
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}

/// Cartiglio della caratteristica (FORZA, DESTREZZA, ...) con ovale sporgente
/// in basso per il modificatore, identico alla colonna sinistra di pagina 1.
class AbilityCartouche extends StatelessWidget {
  const AbilityCartouche({
    super.key,
    required this.label,
    required this.score,
    required this.modifier,
  });

  final String label;
  final Widget score;
  final Widget modifier;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: CustomPaint(
            isComplex: true,
            painter: _AbilityFramePainter(
              paper: palette.paper,
              ink: palette.ink,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFamily: 'RobotoSlab',
                      fontSize: 8.8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .4,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  score,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          child: CustomPaint(
            painter: _AbilityOvalPainter(
              paper: palette.paper,
              ink: palette.ink,
            ),
            child: SizedBox(
              width: 56,
              height: 30,
              child: Center(child: modifier),
            ),
          ),
        ),
      ],
    );
  }
}

class _AbilityFramePainter extends CustomPainter {
  const _AbilityFramePainter({required this.paper, required this.ink});

  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final outer = _notchedCornerPath(rect, 7.5);
    canvas.drawPath(outer, Paint()..color = paper);
    canvas.drawPath(
      outer,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65,
    );
    final inner = _chamferedRect(rect.deflate(2.8), 5);
    canvas.drawPath(
      inner,
      Paint()
        ..color = ink.withValues(alpha: .42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
  }

  @override
  bool shouldRepaint(_AbilityFramePainter oldDelegate) =>
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}

class _AbilityOvalPainter extends CustomPainter {
  const _AbilityOvalPainter({required this.paper, required this.ink});

  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = (Offset.zero & size).deflate(1);
    canvas.drawOval(outer, Paint()..color = paper);
    canvas.drawOval(
      outer,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65,
    );
    canvas.drawOval(
      outer.deflate(2.5),
      Paint()
        ..color = ink.withValues(alpha: .42)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75,
    );
  }

  @override
  bool shouldRepaint(_AbilityOvalPainter oldDelegate) =>
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}

enum StatEmblemShape { square, circle }

/// Barra orizzontale con stemma a sinistra (Ispirazione, Bonus competenza,
/// Percezione passiva), come i tre cartigli orizzontali di pagina 1.
class StatBadgeBar extends StatelessWidget {
  const StatBadgeBar({
    super.key,
    required this.label,
    required this.value,
    required this.shape,
  });

  final String label;
  final Widget value;
  final StatEmblemShape shape;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return SizedBox(
      height: 44,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Positioned.fill(
            left: 24,
            top: 4,
            bottom: 4,
            child: CustomPaint(
              painter: _RibbonStripPainter(
                paper: palette.paper,
                ink: palette.ink,
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 28, right: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontFamily: 'RobotoSlab',
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .65,
                      color: palette.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
          CustomPaint(
            painter: _EmblemPainter(
              paper: palette.paper,
              ink: palette.ink,
              shape: shape,
            ),
            child: SizedBox(width: 44, height: 44, child: Center(child: value)),
          ),
        ],
      ),
    );
  }
}

class _RibbonStripPainter extends CustomPainter {
  const _RibbonStripPainter({required this.paper, required this.ink});

  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.9);
    final path = _chamferedRect(rect, 5);
    canvas.drawPath(path, Paint()..color = paper);
    canvas.drawPath(
      path,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawPath(
      _chamferedRect(rect.deflate(2.5), 3.5),
      Paint()
        ..color = ink.withValues(alpha: .38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75,
    );
  }

  @override
  bool shouldRepaint(_RibbonStripPainter oldDelegate) =>
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter({
    required this.paper,
    required this.ink,
    required this.shape,
  });

  final Color paper;
  final Color ink;
  final StatEmblemShape shape;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1.2);
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7;
    final innerStroke = Paint()
      ..color = ink.withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;
    if (shape == StatEmblemShape.circle) {
      canvas
        ..drawOval(rect, Paint()..color = paper)
        ..drawOval(rect, stroke)
        ..drawOval(rect.deflate(2.8), innerStroke);
    } else {
      final outer = _chamferedRect(rect, 4.5);
      canvas
        ..drawPath(outer, Paint()..color = paper)
        ..drawPath(outer, stroke)
        ..drawPath(_chamferedRect(rect.deflate(2.8), 3), innerStroke);
    }
  }

  @override
  bool shouldRepaint(_EmblemPainter oldDelegate) =>
      paper != oldDelegate.paper ||
      ink != oldDelegate.ink ||
      shape != oldDelegate.shape;
}

/// Placca esagonale/smussata per le monete (MR, MA, ME, MO, MP).
class CoinPlaque extends StatelessWidget {
  const CoinPlaque({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return CustomPaint(
      painter: _CoinPlaquePainter(paper: palette.paper, ink: palette.ink),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 5, 4, 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontFamily: 'RobotoSlab',
                fontSize: 8.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .5,
                color: palette.ink.withValues(alpha: .8),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _CoinPlaquePainter extends CustomPainter {
  const _CoinPlaquePainter({required this.paper, required this.ink});

  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(.9);
    final outer = _chamferedRect(rect, 7);
    canvas.drawPath(outer, Paint()..color = paper);
    canvas.drawPath(
      outer,
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    canvas.drawPath(
      _chamferedRect(rect.deflate(2.5), 5),
      Paint()
        ..color = ink.withValues(alpha: .36)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .75,
    );
  }

  @override
  bool shouldRepaint(_CoinPlaquePainter oldDelegate) =>
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}

/// Intestazione di un livello di incantesimo come su pagina 3: losanga a
/// sinistra con il numero del livello, barra smussata a destra con titolo/slot.
class SpellLevelHeaderFrame extends StatelessWidget {
  const SpellLevelHeaderFrame({
    super.key,
    required this.level,
    required this.child,
  });

  final int level;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return CustomPaint(
      isComplex: true,
      painter: _SpellHeaderPainter(paper: palette.paper, ink: palette.ink),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            height: 44,
            child: Center(
              child: Text(
                '$level',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontFamily: 'RobotoSlab',
                  fontWeight: FontWeight.w900,
                  color: palette.ink,
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpellHeaderPainter extends CustomPainter {
  const _SpellHeaderPainter({required this.paper, required this.ink});

  final Color paper;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final w = size.width;
    const badgeW = 36.0;
    final stroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.miter;
    final innerStroke = Paint()
      ..color = ink.withValues(alpha: .42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8;

    // Barra destra.
    final barRect = Rect.fromLTRB(badgeW - 8, 3, w - 1, h - 3);
    final bar = _chamferedRect(barRect, 6);
    canvas
      ..drawPath(bar, Paint()..color = paper)
      ..drawPath(bar, stroke)
      ..drawPath(_chamferedRect(barRect.deflate(2.5), 4.5), innerStroke);

    // Scudetto a punta per il numero del livello a sinistra.
    final badge = Path()
      ..moveTo(badgeW * .5, 1)
      ..lineTo(badgeW - 1, 9)
      ..lineTo(badgeW - 1, h - 9)
      ..lineTo(badgeW * .5, h - 1)
      ..lineTo(1, h - 9)
      ..lineTo(1, 9)
      ..close();
    canvas
      ..drawPath(badge, Paint()..color = paper)
      ..drawPath(badge, stroke);
    final innerBadge = Path()
      ..moveTo(badgeW * .5, 4)
      ..lineTo(badgeW - 3.8, 10.5)
      ..lineTo(badgeW - 3.8, h - 10.5)
      ..lineTo(badgeW * .5, h - 4)
      ..lineTo(3.8, h - 10.5)
      ..lineTo(3.8, 10.5)
      ..close();
    canvas.drawPath(innerBadge, innerStroke);
  }

  @override
  bool shouldRepaint(_SpellHeaderPainter oldDelegate) =>
      paper != oldDelegate.paper || ink != oldDelegate.ink;
}

/// Linea orizzontale che collega i tre cerchi dei tiri salvezza contro morte,
/// come sulla scheda stampata (`○—○—○`).
class DeathSaveTrack extends StatelessWidget {
  const DeathSaveTrack({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = SheetPalette.of(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 18,
          right: 18,
          child: Container(height: 1.5, color: palette.ink),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: children),
      ],
    );
  }
}

Path _chamferedRect(Rect r, double cut) {
  final c = cut.clamp(0.0, r.shortestSide / 2);
  return Path()
    ..moveTo(r.left + c, r.top)
    ..lineTo(r.right - c, r.top)
    ..lineTo(r.right, r.top + c)
    ..lineTo(r.right, r.bottom - c)
    ..lineTo(r.right - c, r.bottom)
    ..lineTo(r.left + c, r.bottom)
    ..lineTo(r.left, r.bottom - c)
    ..lineTo(r.left, r.top + c)
    ..close();
}

/// Rettangolo con angoli a gradino/incavo nello stile della scheda D&D 5e.
Path _notchedCornerPath(Rect r, double n) {
  final c = n.clamp(0.0, r.shortestSide / 3);
  final step = c * .45;
  return Path()
    ..moveTo(r.left + c, r.top)
    ..lineTo(r.right - c, r.top)
    ..lineTo(r.right - step, r.top + step)
    ..lineTo(r.right, r.top + c)
    ..lineTo(r.right, r.bottom - c)
    ..lineTo(r.right - step, r.bottom - step)
    ..lineTo(r.right - c, r.bottom)
    ..lineTo(r.left + c, r.bottom)
    ..lineTo(r.left + step, r.bottom - step)
    ..lineTo(r.left, r.bottom - c)
    ..lineTo(r.left, r.top + c)
    ..lineTo(r.left + step, r.top + step)
    ..close();
}
