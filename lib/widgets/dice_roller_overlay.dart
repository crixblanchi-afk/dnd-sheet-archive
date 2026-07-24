import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

class DiceRollerOverlay extends StatefulWidget {
  const DiceRollerOverlay({
    super.key,
    this.random,
    this.rollLifetime = const Duration(seconds: 30),
    this.revealDuration = const Duration(milliseconds: 650),
  });

  final Random? random;
  final Duration rollLifetime;
  final Duration revealDuration;

  @override
  State<DiceRollerOverlay> createState() => _DiceRollerOverlayState();
}

class _DiceRollerOverlayState extends State<DiceRollerOverlay> {
  static const _dice = [4, 6, 8, 10, 12, 20, 100];

  final List<_DieRoll> _rolls = [];
  final Map<int, Timer> _expiryTimers = {};
  final Set<int> _revealedRollIds = {};
  late final Random _random = widget.random ?? Random();
  var _nextRollId = 0;
  var _menuOpen = false;

  void _toggleMenu() => setState(() => _menuOpen = !_menuOpen);

  void _rollDie(int sides) {
    final roll = _DieRoll(
      id: _nextRollId++,
      sides: sides,
      result: _random.nextInt(sides) + 1,
    );
    setState(() => _rolls.add(roll));
    _expiryTimers[roll.id] = Timer(widget.rollLifetime, () {
      if (!mounted) return;
      setState(() {
        _rolls.removeWhere((item) => item.id == roll.id);
        _revealedRollIds.remove(roll.id);
      });
      _expiryTimers.remove(roll.id);
    });
  }

  void _markRollRevealed(int rollId) {
    if (!_rolls.any((roll) => roll.id == rollId)) return;
    setState(() => _revealedRollIds.add(rollId));
  }

  void _clearRolls() {
    if (_rolls.isEmpty) return;
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    _expiryTimers.clear();
    setState(() {
      _rolls.clear();
      _revealedRollIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: SafeArea(
            minimum: const EdgeInsets.fromLTRB(20, 80, 20, 104),
            child: LayoutBuilder(
              builder: (context, constraints) => Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      runAlignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final roll in _rolls)
                          _AnimatedDieResult(
                            key: ValueKey('dice-roll-${roll.id}'),
                            roll: roll,
                            duration: widget.revealDuration,
                            onRevealed: () => _markRollRevealed(roll.id),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      AnimatedPositioned(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        left: 0,
        right: 0,
        bottom: _menuOpen ? 210 : 76,
        child: IgnorePointer(
          child: SafeArea(
            top: false,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _rolls.length > 1
                    ? _DiceTotalBadge(
                        key: const ValueKey('dice-total'),
                        total: _revealedRollIds.length == _rolls.length
                            ? _rolls.fold<int>(
                                0,
                                (total, roll) => total + roll.result,
                              )
                            : null,
                      )
                    : const SizedBox.shrink(key: ValueKey('dice-total-hidden')),
              ),
            ),
          ),
        ),
      ),
      SafeArea(
        child: Align(
          alignment: Alignment.bottomLeft,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  reverseDuration: const Duration(milliseconds: 130),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: animation,
                      alignment: Alignment.bottomLeft,
                      child: child,
                    ),
                  ),
                  child: _menuOpen
                      ? Material(
                          key: const ValueKey('dice-menu'),
                          elevation: 5,
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: .94),
                          borderRadius: BorderRadius.circular(22),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: SizedBox(
                              width: 200,
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final sides in _dice)
                                    _DieButton(
                                      sides: sides,
                                      onPressed: () => _rollDie(sides),
                                    ),
                                  _ClearRollsButton(
                                    onPressed: _rolls.isEmpty
                                        ? null
                                        : _clearRolls,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('dice-menu-closed'),
                        ),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  key: const ValueKey('dice-menu-fab'),
                  heroTag: 'dice-menu',
                  onPressed: _toggleMenu,
                  tooltip: _menuOpen ? 'Chiudi lanciadadi' : 'Apri lanciadadi',
                  child: AnimatedRotation(
                    turns: _menuOpen ? .25 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(
                      _menuOpen ? Icons.close : Icons.casino_outlined,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    for (final timer in _expiryTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}

class _DieButton extends StatelessWidget {
  const _DieButton({required this.sides, required this.onPressed});

  final int sides;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Lancia d$sides',
    child: Semantics(
      button: true,
      label: 'Lancia d$sides',
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          key: ValueKey('dice-button-$sides'),
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: Text(
                'd$sides',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontFamily: 'RobotoSlab',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ClearRollsButton extends StatelessWidget {
  const _ClearRollsButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Pulisci tutti i risultati',
    child: Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Pulisci tutti i risultati',
      child: Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        shape: const CircleBorder(),
        child: InkWell(
          key: const ValueKey('dice-clear-button'),
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              Icons.cleaning_services_outlined,
              size: 20,
              color: onPressed == null
                  ? Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: .3)
                  : Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
    ),
  );
}

class _DiceTotalBadge extends StatelessWidget {
  const _DiceTotalBadge({super.key, required this.total});

  final int? total;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 4,
    color: Theme.of(
      context,
    ).colorScheme.tertiaryContainer.withValues(alpha: .92),
    borderRadius: BorderRadius.circular(22),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      child: Text(
        total == null ? 'Totale: …' : 'Totale: $total',
        key: const ValueKey('dice-total-value'),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontFamily: 'RobotoSlab',
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _AnimatedDieResult extends StatefulWidget {
  const _AnimatedDieResult({
    super.key,
    required this.roll,
    required this.duration,
    required this.onRevealed,
  });

  final _DieRoll roll;
  final Duration duration;
  final VoidCallback onRevealed;

  @override
  State<_AnimatedDieResult> createState() => _AnimatedDieResultState();
}

class _AnimatedDieResultState extends State<_AnimatedDieResult>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          widget.onRevealed();
          setState(() {});
        }
      })
      ..forward();
    _scale = Tween<double>(
      begin: .55,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        final wobble = sin(progress * pi * 5) * .14 * (1 - progress);
        return Opacity(
          opacity: (.3 + progress * .62).clamp(0, 1),
          child: Transform.rotate(
            angle: progress * pi * 2 + wobble,
            child: Transform.scale(scale: _scale.value, child: child),
          ),
        );
      },
      child: SizedBox.square(
        dimension: 96,
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: PhysicalShape(
            key: ValueKey('dice-result-shape-${widget.roll.id}'),
            clipper: _DieSilhouetteClipper(widget.roll.sides),
            clipBehavior: Clip.antiAlias,
            color: Theme.of(
              context,
            ).colorScheme.primaryContainer.withValues(alpha: .84),
            elevation: 5,
            shadowColor: const Color(0x66000000),
            child: CustomPaint(
              painter: _DieFramePainter(
                sides: widget.roll.sides,
                color: Theme.of(context).colorScheme.primary,
              ),
              child: Center(
                child: Transform.translate(
                  offset: Offset(0, widget.roll.sides == 4 ? 11 : 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'd${widget.roll.sides}',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontFamily: 'RobotoSlab',
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        _controller.isCompleted ? '${widget.roll.result}' : '?',
                        key: ValueKey('dice-result-value-${widget.roll.id}'),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontFamily: 'RobotoSlab',
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

class _DieSilhouetteClipper extends CustomClipper<Path> {
  const _DieSilhouetteClipper(this.sides);

  final int sides;

  @override
  Path getClip(Size size) => _dieSilhouettePath(sides, size);

  @override
  bool shouldReclip(_DieSilhouetteClipper oldClipper) =>
      sides != oldClipper.sides;
}

class _DieFramePainter extends CustomPainter {
  const _DieFramePainter({required this.sides, required this.color});

  final int sides;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _dieSilhouettePath(sides, size, inset: 1.5),
      Paint()
        ..color = color.withValues(alpha: .74)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      _dieInternalPath(sides, size, inset: 1.5),
      Paint()
        ..color = color.withValues(alpha: .24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_DieFramePainter oldDelegate) =>
      sides != oldDelegate.sides || color != oldDelegate.color;
}

Path _dieSilhouettePath(int sides, Size size, {double inset = 0}) {
  final rect = Rect.fromLTWH(
    inset,
    inset,
    max(0, size.width - inset * 2),
    max(0, size.height - inset * 2),
  );
  Offset point(double x, double y) =>
      Offset(rect.left + rect.width * x, rect.top + rect.height * y);

  switch (sides) {
    case 4:
      return Path()
        ..moveTo(point(.5, .02).dx, point(.5, .02).dy)
        ..lineTo(point(.98, .94).dx, point(.98, .94).dy)
        ..lineTo(point(.02, .94).dx, point(.02, .94).dy)
        ..close();
    case 6:
      return Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            rect.left + rect.width * .04,
            rect.top + rect.height * .04,
            rect.width * .92,
            rect.height * .92,
          ),
          Radius.circular(rect.shortestSide * .1),
        ),
      );
    case 8:
      return Path()
        ..moveTo(point(.5, .01).dx, point(.5, .01).dy)
        ..lineTo(point(.97, .5).dx, point(.97, .5).dy)
        ..lineTo(point(.5, .99).dx, point(.5, .99).dy)
        ..lineTo(point(.03, .5).dx, point(.03, .5).dy)
        ..close();
    case 10:
      return Path()
        ..moveTo(point(.5, .01).dx, point(.5, .01).dy)
        ..lineTo(point(.8, .27).dx, point(.8, .27).dy)
        ..lineTo(point(.94, .54).dx, point(.94, .54).dy)
        ..lineTo(point(.5, .99).dx, point(.5, .99).dy)
        ..lineTo(point(.06, .54).dx, point(.06, .54).dy)
        ..lineTo(point(.2, .27).dx, point(.2, .27).dy)
        ..close();
    case 12:
      return Path()
        ..moveTo(point(.46, .06).dx, point(.46, .06).dy)
        ..lineTo(point(.54, .06).dx, point(.54, .06).dy)
        ..lineTo(point(.75, .14).dx, point(.75, .14).dy)
        ..lineTo(point(.94, .35).dx, point(.94, .35).dy)
        ..lineTo(point(.94, .63).dx, point(.94, .63).dy)
        ..lineTo(point(.73, .87).dx, point(.73, .87).dy)
        ..lineTo(point(.5, .95).dx, point(.5, .95).dy)
        ..lineTo(point(.27, .87).dx, point(.27, .87).dy)
        ..lineTo(point(.06, .63).dx, point(.06, .63).dy)
        ..lineTo(point(.06, .35).dx, point(.06, .35).dy)
        ..lineTo(point(.25, .14).dx, point(.25, .14).dy)
        ..close();
    case 20:
      return Path()
        ..moveTo(point(.5, .02).dx, point(.5, .02).dy)
        ..lineTo(point(.94, .28).dx, point(.94, .28).dy)
        ..lineTo(point(.94, .7).dx, point(.94, .7).dy)
        ..lineTo(point(.5, .98).dx, point(.5, .98).dy)
        ..lineTo(point(.06, .7).dx, point(.06, .7).dy)
        ..lineTo(point(.06, .28).dx, point(.06, .28).dy)
        ..close();
    case 100:
      return Path()..addOval(rect.deflate(rect.shortestSide * .02));
    default:
      return Path()..addOval(rect);
  }
}

Path _dieInternalPath(int sides, Size size, {double inset = 0}) {
  final rect = Rect.fromLTWH(
    inset,
    inset,
    max(0, size.width - inset * 2),
    max(0, size.height - inset * 2),
  );
  Offset point(double x, double y) =>
      Offset(rect.left + rect.width * x, rect.top + rect.height * y);
  final path = Path();
  void segment(double x1, double y1, double x2, double y2) {
    final start = point(x1, y1);
    final end = point(x2, y2);
    path
      ..moveTo(start.dx, start.dy)
      ..lineTo(end.dx, end.dy);
  }

  switch (sides) {
    case 8:
      segment(.5, .01, .5, .5);
      segment(.97, .5, .5, .5);
      segment(.5, .99, .5, .5);
      segment(.03, .5, .5, .5);
    case 10:
      final top = point(.5, .01);
      final right = point(.76, .48);
      final bottom = point(.5, .63);
      final left = point(.24, .48);
      path
        ..moveTo(top.dx, top.dy)
        ..lineTo(right.dx, right.dy)
        ..lineTo(bottom.dx, bottom.dy)
        ..lineTo(left.dx, left.dy)
        ..close();
      segment(.8, .27, .76, .48);
      segment(.94, .54, .76, .48);
      segment(.5, .99, .5, .63);
      segment(.06, .54, .24, .48);
      segment(.2, .27, .24, .48);
    case 12:
      final centerFace = [
        point(.5, .27),
        point(.7, .42),
        point(.62, .68),
        point(.38, .68),
        point(.3, .42),
      ];
      path.moveTo(centerFace.first.dx, centerFace.first.dy);
      for (final vertex in centerFace.skip(1)) {
        path.lineTo(vertex.dx, vertex.dy);
      }
      path.close();
      segment(.5, .06, .5, .27);
      segment(.94, .35, .7, .42);
      segment(.73, .87, .62, .68);
      segment(.27, .87, .38, .68);
      segment(.06, .35, .3, .42);
    case 20:
      final top = point(.5, .3);
      final right = point(.72, .68);
      final left = point(.28, .68);
      path
        ..moveTo(top.dx, top.dy)
        ..lineTo(right.dx, right.dy)
        ..lineTo(left.dx, left.dy)
        ..close();
      segment(.5, .02, .5, .3);
      segment(.06, .28, .5, .3);
      segment(.94, .28, .5, .3);
      segment(.06, .7, .28, .68);
      segment(.94, .7, .72, .68);
      segment(.5, .98, .28, .68);
      segment(.5, .98, .72, .68);
  }
  return path;
}

class _DieRoll {
  const _DieRoll({required this.id, required this.sides, required this.result});

  final int id;
  final int sides;
  final int result;
}
