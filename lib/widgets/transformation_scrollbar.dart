import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

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
  static const _minScale = .3;
  static const _maxScale = 6.0;

  late final Ticker _ticker;
  Duration? _lastTick;
  double _targetX = 0;
  double _targetY = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_handleTick);
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
      final maxX = math.max(
        0.0,
        widget.contentSize.width * scale - widget.viewportSize.width,
      );
      _targetX = (_targetX - event.scrollDelta.dx).clamp(-maxX, 0.0);
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
      _minScale,
      _maxScale,
    );
    if ((targetScale - currentScale).abs() < .0001) return;

    // Rebuild the transform around the pointer so that the part of the sheet
    // under the cursor stays in place while zooming.
    final focalPoint = event.localPosition;
    final scenePoint = widget.controller.toScene(focalPoint);
    widget.controller.value = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(targetScale, targetScale, 1, 1)
      ..translateByDouble(-scenePoint.dx, -scenePoint.dy, 0, 1);
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
      return ValueListenableBuilder<Matrix4>(
        valueListenable: widget.controller,
        builder: (context, matrix, _) {
          final metrics = _metrics(matrix, trackExtent);
          return MouseRegion(
            cursor: widget.axis == Axis.horizontal
                ? SystemMouseCursors.resizeLeftRight
                : SystemMouseCursors.resizeUpDown,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: metrics.scrollable
                  ? (event) => _startDrag(_positionOf(event), metrics)
                  : null,
              onPointerMove: metrics.scrollable
                  ? (event) => _updateDrag(_positionOf(event), metrics)
                  : null,
              onPointerUp: (_) => _thumbGrabOffset = null,
              onPointerCancel: (_) => _thumbGrabOffset = null,
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: widget.axis == Axis.vertical ? 4 : double.infinity,
                      height: widget.axis == Axis.horizontal
                          ? 4
                          : double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (widget.axis == Axis.horizontal)
                    Positioned(
                      left: metrics.thumbPosition,
                      top: 2,
                      width: metrics.thumbExtent,
                      bottom: 2,
                      child: _thumb(context, metrics.scrollable),
                    )
                  else
                    Positioned(
                      left: 2,
                      top: metrics.thumbPosition,
                      right: 2,
                      height: metrics.thumbExtent,
                      child: _thumb(context, metrics.scrollable),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  Widget _thumb(BuildContext context, bool enabled) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: enabled ? .78 : .28),
      borderRadius: BorderRadius.circular(5),
    ),
  );

  _ScrollbarMetrics _metrics(Matrix4 matrix, double trackExtent) {
    final scale = matrix.getMaxScaleOnAxis();
    final scaledContentExtent = widget.contentExtent * scale;
    final maxScrollOffset = math.max(
      0.0,
      scaledContentExtent - widget.viewportExtent,
    );
    final translation =
        matrix.storage[widget.axis == Axis.horizontal ? 12 : 13];
    final scrollOffset = (-translation).clamp(0.0, maxScrollOffset);
    final visibleFraction = scaledContentExtent <= 0
        ? 1.0
        : (widget.viewportExtent / scaledContentExtent).clamp(0.0, 1.0);
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
