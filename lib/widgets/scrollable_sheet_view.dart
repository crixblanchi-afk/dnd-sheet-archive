import 'package:flutter/material.dart';

import '../controllers/sheet_controller.dart';
import '../models/sheet_field.dart';
import '../models/sheet_layout.dart';
import 'sheet_page.dart';
import 'transformation_scrollbar.dart';

const _scaleEpsilon = .001;

/// Le tre pagine in una colonna continua, con pan e zoom.
class ScrollableSheetView extends StatefulWidget {
  const ScrollableSheetView({
    super.key,
    required this.controller,
    required this.fields,
    this.initialPage = 0,
  });

  final SheetController controller;
  final List<List<SheetFieldDef>> fields;
  final int initialPage;

  @override
  State<ScrollableSheetView> createState() => _ScrollableSheetViewState();
}

class _ScrollableSheetViewState extends State<ScrollableSheetView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TransformationController _transformationController;
  late final AnimationController _panAnimationController;
  final _viewportKey = GlobalKey();
  Animation<Matrix4>? _panAnimation;
  BuildContext? _pendingFieldContext;
  bool _initializedScale = false;
  double? _scaleBeforeFitWidth;
  double _lastScale = 1;
  bool _applyingZoomAnimation = false;

  static const _sheetSize = Size(sheetPageWidth, sheetContentHeight);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _transformationController = TransformationController()
      ..addListener(_handleScaleChange);
    _panAnimationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 220),
        )..addListener(() {
          final animation = _panAnimation;
          if (animation != null) {
            _applyingZoomAnimation = true;
            try {
              _transformationController.value = animation.value;
            } finally {
              _applyingZoomAnimation = false;
            }
          }
        });
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
    final viewport =
        _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final visibleBottom =
        viewport.localToGlobal(Offset(0, viewport.size.height)).dy - 16;
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
    _clearFitWidth();
    _zoomTo(currentScale * factor, viewportSize);
  }

  void _clearFitWidth() {
    if (_scaleBeforeFitWidth == null) return;
    setState(() => _scaleBeforeFitWidth = null);
  }

  void _handleScaleChange() {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    final changed = (scale - _lastScale).abs() > .000001;
    _lastScale = scale;
    // Pan e animazioni dell'app conservano lo zoom da ripristinare.
    // Pinch e Ctrl+rotellina modificano direttamente il controller.
    if (changed && !_applyingZoomAnimation) {
      _panAnimationController.stop();
      _clearFitWidth();
    }
  }

  void _toggleFitWidth(Size viewportSize) {
    final previousScale = _scaleBeforeFitWidth;
    setState(() {
      _scaleBeforeFitWidth = previousScale == null
          ? _transformationController.value.getMaxScaleOnAxis()
          : null;
    });
    _zoomTo(
      previousScale ?? viewportSize.width / sheetPageWidth,
      viewportSize,
      fitWidth: true,
    );
  }

  void _zoomTo(double scale, Size viewportSize, {bool fitWidth = false}) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final targetScale = scale.clamp(sheetMinScale, sheetMaxScale);
    if (!fitWidth && (targetScale - currentScale).abs() < _scaleEpsilon) {
      return;
    }
    final focalPoint = fitWidth
        ? Offset(viewportSize.width / 2, 0)
        : viewportSize.center(Offset.zero);
    final scenePoint = _transformationController.toScene(focalPoint);
    final target = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, 1, 1)
      ..translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);
    if (fitWidth) {
      // Conserva la posizione di lettura senza lasciare spazio oltre le pagine.
      final maxScroll = (_sheetSize.height * targetScale - viewportSize.height)
          .clamp(0.0, double.infinity);
      target.storage[13] = target.storage[13].clamp(-maxScroll, 0.0);
    }
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
  Widget build(BuildContext context) => LayoutBuilder(
    key: _viewportKey,
    builder: (context, constraints) {
      final viewportSize = constraints.biggest;
      if (!_initializedScale) {
        _initializedScale = true;
        final scale = (constraints.maxWidth / sheetPageWidth).clamp(
          sheetMinScale,
          1.0,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            // Su finestre più larghe della pagina la scheda
            // resterebbe appoggiata al bordo sinistro, con
            // tutto lo spazio vuoto a destra.
            _transformationController.value = Matrix4.identity()
              ..translateByDouble(
                sheetCenterOffset(constraints.maxWidth, sheetPageWidth * scale),
                -(widget.initialPage * (sheetPageHeight + sheetPageGap) * scale)
                    .clamp(
                      0.0,
                      (sheetContentHeight * scale - constraints.maxHeight)
                          .clamp(0.0, double.infinity),
                    ),
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
                transformationController: _transformationController,
                constrained: false,
                minScale: sheetMinScale,
                maxScale: sheetMaxScale,
                scaleFactor: double.infinity,
                boundaryMargin: const EdgeInsets.all(160),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var page = 0; page < sheetPageCount; page++) ...[
                      SheetPage(
                        pageIndex: page,
                        fields: widget.fields[page],
                        controller: widget.controller,
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
                onFitWidth: () => _toggleFitWidth(viewportSize),
                canRestoreZoom: _scaleBeforeFitWidth != null,
              ),
            ),
          ),
        ],
      );
    },
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingFieldContext = null;
    _panAnimationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }
}

class _ZoomControl extends StatelessWidget {
  const _ZoomControl({
    required this.controller,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFitWidth,
    required this.canRestoreZoom,
  });

  final TransformationController controller;
  final VoidCallback onZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onFitWidth;
  final bool canRestoreZoom;

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
              const SizedBox(width: 6),
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
              const SizedBox(height: 18, child: VerticalDivider(width: 9)),
              _ZoomButton(
                tooltip: canRestoreZoom
                    ? 'Ripristina lo zoom precedente'
                    : 'Adatta alla larghezza della finestra',
                icon: canRestoreZoom ? Icons.zoom_out_map : Icons.fit_screen,
                onPressed: onFitWidth,
              ),
              const SizedBox(width: 6),
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
