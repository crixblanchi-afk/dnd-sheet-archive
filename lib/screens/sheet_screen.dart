import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';
import '../data/character_repository.dart';
import '../models/character.dart';
import '../models/sheet_field.dart';
import '../models/sheet_layout.dart';
import '../sync/google_drive_sync_service.dart';
import '../widgets/dice_roller_overlay.dart';
import '../widgets/sheet_page.dart';
import '../widgets/transformation_scrollbar.dart';

// I pulsanti di zoom si disabilitano appena prima del limite, per non restare
// attivi quando un altro passo di scala non sarebbe più applicabile.
const _scaleEpsilon = .001;

class SheetScreen extends StatefulWidget {
  const SheetScreen({
    super.key,
    required this.character,
    required this.repository,
    required this.driveSync,
  });

  final Character character;
  final CharacterRepository repository;
  final GoogleDriveSyncService driveSync;

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final SheetController _sheetController;
  late final TransformationController _transformationController;
  late final AnimationController _panAnimationController;
  late final Future<List<List<SheetFieldDef>>> _fields;
  Animation<Matrix4>? _panAnimation;
  BuildContext? _pendingFieldContext;
  bool _initializedScale = false;
  bool _allowPop = false;
  bool _exiting = false;

  static const _sheetSize = Size(sheetPageWidth, sheetContentHeight);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sheetController = SheetController(
      repository: widget.repository,
      character: widget.character,
    );
    _transformationController = TransformationController();
    _panAnimationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final animation = _panAnimation;
          if (animation != null) {
            _transformationController.value = animation.value;
          }
        });
    _fields = SheetFieldDef.loadByPage();
  }

  Future<void> _exit() async {
    // La guardia va alzata prima di qualsiasi await: il pulsante indietro e il
    // gesto di sistema possono arrivare insieme, e due uscite concorrenti
    // farebbero due pop, chiudendo anche l'elenco dei personaggi.
    if (_allowPop || _exiting) return;
    _exiting = true;
    try {
      await _sheetController.close();
    } catch (_) {
      _exiting = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Salvataggio non riuscito. Riprova tra poco.'),
          ),
        );
      }
      return;
    }
    // Le modifiche sono già al sicuro nell'archivio locale: il viaggio di rete
    // verso Drive non deve trattenere la navigazione.
    unawaited(widget.driveSync.syncPendingChanges());
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
  }

  Future<void> _toggleLock() async {
    try {
      await _sheetController.toggleLock();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Stato non ancora salvato: nuovo tentativo in corso.',
            ),
          ),
        );
      }
    }
  }

  void _ensureVisible(BuildContext fieldContext) {
    _pendingFieldContext = fieldContext;
    _scheduleFieldReveal();
  }

  @override
  void didChangeMetrics() {
    // La tastiera si apre con un'animazione, quindi `viewInsets` cresce per
    // più fotogrammi: rivalutare a ogni cambio di metriche evita di indovinare
    // una durata fissa e copre anche rotazione e ridimensionamento.
    if (_pendingFieldContext != null) _scheduleFieldReveal();
  }

  void _scheduleFieldReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealPendingField());
  }

  void _revealPendingField() {
    final fieldContext = _pendingFieldContext;
    if (fieldContext == null) return;
    if (!mounted || !fieldContext.mounted) {
      _pendingFieldContext = null;
      return;
    }
    final box = fieldContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final media = MediaQuery.of(context);
    final visibleBottom = media.size.height - media.viewInsets.bottom - 16;
    if (bottom <= visibleBottom) return;
    final overlap = bottom - visibleBottom;
    final target = _transformationController.value.clone()
      ..translateByDouble(0.0, -overlap, 0.0, 1.0);
    _panAnimation =
        Matrix4Tween(
          begin: _transformationController.value,
          end: target,
        ).animate(
          CurvedAnimation(
            parent: _panAnimationController,
            curve: Curves.easeOut,
          ),
        );
    _panAnimationController.forward(from: 0);
  }

  void _zoomBy(double factor, Size viewportSize) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = (currentScale * factor).clamp(
      sheetMinScale,
      sheetMaxScale,
    );
    if ((targetScale - currentScale).abs() < _scaleEpsilon) return;
    final focalPoint = viewportSize.center(Offset.zero);
    final scenePoint = _transformationController.toScene(focalPoint);
    final target = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, 1, 1)
      ..translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);
    // Rimpicciolendo, la scheda può diventare più stretta della finestra: il
    // punto focale da solo la lascerebbe sbilanciata su un lato.
    target.storage[12] = clampSheetTranslationX(
      target.storage[12],
      viewportSize.width,
      _sheetSize.width * targetScale,
    );
    _panAnimation =
        Matrix4Tween(
          begin: _transformationController.value,
          end: target,
        ).animate(
          CurvedAnimation(
            parent: _panAnimationController,
            curve: Curves.easeOut,
          ),
        );
    _panAnimationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _exit();
    },
    child: Scaffold(
      backgroundColor: const Color(0xffdedbd2),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FutureBuilder<List<List<SheetFieldDef>>>(
              future: _fields,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Card(
                      margin: const EdgeInsets.all(32),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Impossibile caricare il layout della scheda.\n'
                          '${snapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final viewportSize = constraints.biggest;
                    if (!_initializedScale) {
                      _initializedScale = true;
                      final scale = (constraints.maxWidth / sheetPageWidth)
                          .clamp(sheetMinScale, 1.0);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          // Su finestre più larghe della pagina la scheda
                          // resterebbe appoggiata al bordo sinistro, con
                          // tutto lo spazio vuoto a destra.
                          _transformationController.value = Matrix4.identity()
                            ..translateByDouble(
                              sheetCenterOffset(
                                constraints.maxWidth,
                                sheetPageWidth * scale,
                              ),
                              0,
                              0,
                              1,
                            )
                            ..scaleByDouble(scale, scale, 1, 1);
                        }
                      });
                    }
                    final bottomPadding = MediaQuery.paddingOf(context).bottom;
                    final topPadding = MediaQuery.paddingOf(context).top;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: TransformationWheelScroller(
                            controller: _transformationController,
                            viewportSize: viewportSize,
                            contentSize: _sheetSize,
                            child: InteractiveViewer(
                              transformationController:
                                  _transformationController,
                              constrained: false,
                              minScale: sheetMinScale,
                              maxScale: sheetMaxScale,
                              scaleFactor: double.infinity,
                              boundaryMargin: const EdgeInsets.all(160),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (
                                    var page = 0;
                                    page < sheetPageCount;
                                    page++
                                  ) ...[
                                    SheetPage(
                                      pageIndex: page,
                                      fields: snapshot.data![page],
                                      controller: _sheetController,
                                      onFieldFocused: _ensureVisible,
                                    ),
                                    if (page < sheetPageCount - 1)
                                      const SizedBox(height: sheetPageGap),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 8,
                          right: 148,
                          bottom: bottomPadding + 4,
                          height: 12,
                          child: RepaintBoundary(
                            child: TransformationScrollbar(
                              axis: Axis.horizontal,
                              controller: _transformationController,
                              viewportExtent: viewportSize.width,
                              contentExtent: _sheetSize.width,
                            ),
                          ),
                        ),
                        Positioned(
                          top: topPadding + 60,
                          right: 4,
                          bottom: bottomPadding + 54,
                          width: 12,
                          child: RepaintBoundary(
                            child: TransformationScrollbar(
                              axis: Axis.vertical,
                              controller: _transformationController,
                              viewportExtent: viewportSize.height,
                              contentExtent: _sheetSize.height,
                            ),
                          ),
                        ),
                        Positioned(
                          right: 18,
                          bottom: bottomPadding + 16,
                          child: RepaintBoundary(
                            child: _ZoomControl(
                              controller: _transformationController,
                              onZoomOut: () => _zoomBy(.8, viewportSize),
                              onZoomIn: () => _zoomBy(1.25, viewportSize),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'back',
                    onPressed: _exit,
                    tooltip: 'Indietro',
                    child: const Icon(Icons.arrow_back),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _sheetController.lockedState,
                    builder: (context, locked, _) => FloatingActionButton.small(
                      heroTag: 'lock',
                      onPressed: _toggleLock,
                      tooltip: locked ? 'Sblocca scheda' : 'Blocca scheda',
                      child: Icon(locked ? Icons.lock : Icons.lock_open),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Positioned.fill(child: DiceRollerOverlay()),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingFieldContext = null;
    _panAnimationController.dispose();
    _transformationController.dispose();
    unawaited(_closeAndDisposeController());
    super.dispose();
  }

  Future<void> _closeAndDisposeController() async {
    try {
      await _sheetController.close();
    } catch (_) {
      // The save was attempted; the route no longer has UI for reporting it.
    } finally {
      _sheetController.dispose();
    }
  }
}

class _ZoomControl extends StatelessWidget {
  const _ZoomControl({
    required this.controller,
    required this.onZoomOut,
    required this.onZoomIn,
  });

  final TransformationController controller;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 3,
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .94),
    borderRadius: BorderRadius.circular(18),
    child: ValueListenableBuilder<Matrix4>(
      valueListenable: controller,
      builder: (context, matrix, _) {
        final scale = matrix.getMaxScaleOnAxis();
        return SizedBox(
          height: 36,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ZoomButton(
                tooltip: 'Riduci zoom',
                icon: Icons.remove,
                onPressed: scale > sheetMinScale + _scaleEpsilon
                    ? onZoomOut
                    : null,
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${(scale * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              _ZoomButton(
                tooltip: 'Aumenta zoom',
                icon: Icons.add,
                onPressed: scale < sheetMaxScale - _scaleEpsilon
                    ? onZoomIn
                    : null,
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 18),
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 34, height: 34),
    visualDensity: VisualDensity.compact,
  );
}
