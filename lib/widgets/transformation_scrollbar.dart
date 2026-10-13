import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../models/sheet_layout.dart';

class TransformationWheelScroller extends StatefulWidget {
  const TransformationWheelScroller({
    super.key,
    required this.controller,
    required this.viewportSize,
    required this.contentSize,
    required this.child,
  });

  final TransformationController controller;
  final Size viewportSize;
  final Size contentSize;
  final Widget child;

  @override
  State<TransformationWheelScroller> createState() =>
      _TransformationWheelScrollerState();
}

class _TransformationWheelScrollerState
    extends State<TransformationWheelScroller>
    with SingleTickerProviderStateMixin {
  // A short time constant keeps the wheel responsive while turning coarse
  // wheel notches into frame-aligned movement.
  static const _smoothingTimeConstant = Duration(milliseconds: 42);
  static const _wheelScaleFactor = 200.0;

  late final Ticker _ticker;
  Duration? _lastTick;
  double _targetX = 0;
  double _targetY = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_handleTick);
    widget.controller.addListener(_enforceHorizontalBounds);
    // Il listener scatta solo sui cambi successivi: la posizione di partenza
    // va comunque verificata una volta.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _enforceHorizontalBounds();
    });
  }

  @override
  void didUpdateWidget(TransformationWheelScroller oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_enforceHorizontalBounds);
      widget.controller.addListener(_enforceHorizontalBounds);
    }
    if (widget.viewportSize != oldWidget.viewportSize ||
        widget.contentSize != oldWidget.contentSize) {
      // Ridimensionando la finestra cambiano i limiti senza che la matrice si
      // muova, quindi nessun listener scatta: la posizione va rivalutata a
      // fine fotogramma, perché toccare il controller durante il build
      // notificherebbe `InteractiveViewer` mentre si sta costruendo.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enforceHorizontalBounds();
      });
    }
  }

  /// Rimette la scheda al centro dopo che `InteractiveViewer` l'ha spostata.
  ///
  /// A ogni interazione `InteractiveViewer` riporta la traslazione dentro il
  /// proprio `boundaryMargin`; quando la finestra è più larga della pagina
  /// quel limite è più stretto del viewport e incolla la scheda al bordo
  /// sinistro. La correzione va quindi riapplicata dopo di lui.
  void _enforceHorizontalBounds() {
    final matrix = widget.controller.value;
    final translationX = matrix.storage[12];
    final clamped = clampSheetTranslationX(
      translationX,
      widget.viewportSize.width,
      widget.contentSize.width * matrix.getMaxScaleOnAxis(),
    );
    if ((clamped - translationX).abs() < .01) return;
    widget.controller.value = matrix.clone()..storage[12] = clamped;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (_) => _stopSmoothing(),
    onPointerSignal: _handlePointerSignal,
    child: widget.child,
  );

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.kind != PointerDeviceKind.mouse) {
      return;
    }

    if (HardwareKeyboard.instance.isControlPressed) {
      _zoomWithWheel(event);
      return;
    }

    final matrix = widget.controller.value;
    final scale = matrix.getMaxScaleOnAxis();
    if (!_ticker.isActive) {
      _targetX = matrix.storage[12];
      _targetY = matrix.storage[13];
    }
    if (event.scrollDelta.dx != 0) {
      _targetX = clampSheetTranslationX(
        _targetX - event.scrollDelta.dx,
        widget.viewportSize.width,
        widget.contentSize.width * scale,
      );
    }
    if (event.scrollDelta.dy != 0) {
      final maxY = math.max(
        0.0,
        widget.contentSize.height * scale - widget.viewportSize.height,
      );
      _targetY = (_targetY - event.scrollDelta.dy).clamp(-maxY, 0.0);
    }
    if (!_ticker.isActive) {
      _lastTick = null;
      _ticker.start();
    }
  }

  void _zoomWithWheel(PointerScrollEvent event) {
    _stopSmoothing();

    final currentScale = widget.controller.value.getMaxScaleOnAxis();
    final scaleChange = math.exp(-event.scrollDelta.dy / _wheelScaleFactor);
    final targetScale = (currentScale * scaleChange).clamp(
      sheetMinScale,
      sheetMaxScale,
    );
    if ((targetScale - currentScale).abs() < .0001) return;

    // Rebuild the transform around the pointer so that the part of the sheet
    // under the cursor stays in place while zooming.
    final focalPoint = event.localPosition;
    final scenePoint = widget.controller.toScene(focalPoint);
    final target = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, targetScale, 1)
      ..translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);
    target.storage[12] = clampSheetTranslationX(
      target.storage[12],
      widget.viewportSize.width,
      widget.contentSize.width * targetScale,
    );
    widget.controller.value = target;
  }

  void _handleTick(Duration elapsed) {
    final previousTick = _lastTick;
    _lastTick = elapsed;
    final elapsedMicros = previousTick == null
        ? Duration.microsecondsPerSecond / 60
        : (elapsed - previousTick).inMicroseconds.toDouble();
    final smoothingMicros = _smoothingTimeConstant.inMicroseconds;
    final fraction = 1 - math.exp(-elapsedMicros / smoothingMicros);

    final matrix = widget.controller.value.clone();
    final currentX = matrix.storage[12];
    final currentY = matrix.storage[13];
    final remainingX = _targetX - currentX;
    final remainingY = _targetY - currentY;

    if (remainingX.abs() < .1 && remainingY.abs() < .1) {
      matrix.storage[12] = _targetX;
      matrix.storage[13] = _targetY;
      widget.controller.value = matrix;
      _stopSmoothing();
      return;
    }

    matrix.storage[12] = currentX + remainingX * fraction;
    matrix.storage[13] = currentY + remainingY * fraction;
    widget.controller.value = matrix;
  }

  void _stopSmoothing() {
    if (_ticker.isActive) _ticker.stop();
    _lastTick = null;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_enforceHorizontalBounds);
    _ticker.dispose();
    super.dispose();
  }
}

class TransformationScrollbar extends StatefulWidget {
  const TransformationScrollbar({
    super.key,
    required this.axis,
    required this.controller,
    required this.viewportExtent,
    required this.contentExtent,
  });

  final Axis axis;
  final TransformationController controller;
  final double viewportExtent;
  final double contentExtent;

  @override
  State<TransformationScrollbar> createState() =>
      _TransformationScrollbarState();
}

class _TransformationScrollbarState extends State<TransformationScrollbar> {
  double? _thumbGrabOffset;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final trackExtent = widget.axis == Axis.horizontal
          ? constraints.maxWidth
          : constraints.maxHeight;
      final theme = Theme.of(context);
      return MouseRegion(
        cursor: widget.axis == Axis.horizontal
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _withMetrics(trackExtent, (metrics) {
            if (metrics.scrollable) {
              _startDrag(_positionOf(event), metrics);
            }
          }),
          onPointerMove: (event) => _withMetrics(trackExtent, (metrics) {
            if (metrics.scrollable) {
              _updateDrag(_positionOf(event), metrics);
            }
          }),
          onPointerUp: (_) => _thumbGrabOffset = null,
          onPointerCancel: (_) => _thumbGrabOffset = null,
          // Disegnata invece che ricostruita: la barra segue la matrice, che
          // cambia a ogni fotogramma di trascinamento, e ricostruire il
          // sottoalbero significava rifare build e layout sessanta volte al
          // secondo per spostare un rettangolo.
          child: CustomPaint(
            size: Size.infinite,
            painter: _ScrollbarPainter(
              repaint: widget.controller,
              controller: widget.controller,
              axis: widget.axis,
              viewportExtent: widget.viewportExtent,
              contentExtent: widget.contentExtent,
              trackColor: theme.brightness == Brightness.dark
                  ? Colors.white24
                  : Colors.black26,
              thumbColor: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    },
  );

  void _withMetrics(double trackExtent, void Function(_ScrollbarMetrics) run) =>
      run(
        _scrollbarMetrics(
          matrix: widget.controller.value,
          axis: widget.axis,
          trackExtent: trackExtent,
          viewportExtent: widget.viewportExtent,
          contentExtent: widget.contentExtent,
        ),
      );

  double _positionOf(PointerEvent event) => widget.axis == Axis.horizontal
      ? event.localPosition.dx
      : event.localPosition.dy;

  void _startDrag(double pointerPosition, _ScrollbarMetrics metrics) {
    final thumbEnd = metrics.thumbPosition + metrics.thumbExtent;
    if (pointerPosition >= metrics.thumbPosition &&
        pointerPosition <= thumbEnd) {
      _thumbGrabOffset = pointerPosition - metrics.thumbPosition;
      return;
    }

    _thumbGrabOffset = metrics.thumbExtent / 2;
    _moveThumbTo(pointerPosition - _thumbGrabOffset!, metrics);
  }

  void _updateDrag(double pointerPosition, _ScrollbarMetrics metrics) {
    final grabOffset = _thumbGrabOffset;
    if (grabOffset == null) return;
    _moveThumbTo(pointerPosition - grabOffset, metrics);
  }

  void _moveThumbTo(double position, _ScrollbarMetrics metrics) {
    if (metrics.thumbTravel <= 0) return;
    final thumbPosition = position.clamp(0.0, metrics.thumbTravel);
    _setScrollOffset(
      thumbPosition / metrics.thumbTravel * metrics.maxScrollOffset,
    );
  }

  void _setScrollOffset(double offset) {
    final matrix = widget.controller.value.clone();
    matrix.storage[widget.axis == Axis.horizontal ? 12 : 13] = -offset;
    widget.controller.value = matrix;
  }
}

/// Posizione e lunghezza del cursore della barra per una data matrice.
_ScrollbarMetrics _scrollbarMetrics({
  required Matrix4 matrix,
  required Axis axis,
  required double trackExtent,
  required double viewportExtent,
  required double contentExtent,
}) {
  final scale = matrix.getMaxScaleOnAxis();
  final scaledContentExtent = contentExtent * scale;
  final maxScrollOffset = math.max(0.0, scaledContentExtent - viewportExtent);
  final translation = matrix.storage[axis == Axis.horizontal ? 12 : 13];
  final scrollOffset = (-translation).clamp(0.0, maxScrollOffset);
  final visibleFraction = scaledContentExtent <= 0
      ? 1.0
      : (viewportExtent / scaledContentExtent).clamp(0.0, 1.0);
  final thumbExtent = math.min(
    trackExtent,
    math.max(28.0, trackExtent * visibleFraction),
  );
  final thumbTravel = math.max(0.0, trackExtent - thumbExtent);
  final thumbPosition = maxScrollOffset == 0
      ? 0.0
      : thumbTravel * scrollOffset / maxScrollOffset;
  return _ScrollbarMetrics(
    maxScrollOffset: maxScrollOffset,
    thumbExtent: thumbExtent,
    thumbPosition: thumbPosition,
    thumbTravel: thumbTravel,
  );
}

class _ScrollbarPainter extends CustomPainter {
  const _ScrollbarPainter({
    required super.repaint,
    required this.controller,
    required this.axis,
    required this.viewportExtent,
    required this.contentExtent,
    required this.trackColor,
    required this.thumbColor,
  });

  static const _trackThickness = 4.0;
  static const _thumbInset = 2.0;

  final TransformationController controller;
  final Axis axis;
  final double viewportExtent;
  final double contentExtent;
  final Color trackColor;
  final Color thumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    final horizontal = axis == Axis.horizontal;
    final thickness = horizontal ? size.height : size.width;
    final metrics = _scrollbarMetrics(
      matrix: controller.value,
      axis: axis,
      trackExtent: horizontal ? size.width : size.height,
      viewportExtent: viewportExtent,
      contentExtent: contentExtent,
    );

    final trackOffset = (thickness - _trackThickness) / 2;
    final track = horizontal
        ? Rect.fromLTWH(0, trackOffset, size.width, _trackThickness)
        : Rect.fromLTWH(trackOffset, 0, _trackThickness, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(2)),
      Paint()..color = trackColor,
    );

    final thumbThickness = thickness - _thumbInset * 2;
    final thumb = horizontal
        ? Rect.fromLTWH(
            metrics.thumbPosition,
            _thumbInset,
            metrics.thumbExtent,
            thumbThickness,
          )
        : Rect.fromLTWH(
            _thumbInset,
            metrics.thumbPosition,
            thumbThickness,
            metrics.thumbExtent,
          );
    canvas.drawRRect(
      RRect.fromRectAndRadius(thumb, const Radius.circular(5)),
      Paint()
        ..color = thumbColor.withValues(alpha: metrics.scrollable ? .78 : .28),
    );
  }

  @override
  bool shouldRepaint(_ScrollbarPainter oldDelegate) =>
      axis != oldDelegate.axis ||
      viewportExtent != oldDelegate.viewportExtent ||
      contentExtent != oldDelegate.contentExtent ||
      trackColor != oldDelegate.trackColor ||
      thumbColor != oldDelegate.thumbColor;
}

class _ScrollbarMetrics {
  const _ScrollbarMetrics({
    required this.maxScrollOffset,
    required this.thumbExtent,
    required this.thumbPosition,
    required this.thumbTravel,
  });

  final double maxScrollOffset;
  final double thumbExtent;
  final double thumbPosition;
  final double thumbTravel;

  bool get scrollable => maxScrollOffset > 0;
}
