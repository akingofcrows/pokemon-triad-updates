import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';

/// Battery level indicator used consistently across all screens.
/// Polls battery level every 20 seconds and shows icon + percentage.
class BatteryIndicator extends StatefulWidget {
  const BatteryIndicator({super.key});

  @override
  State<BatteryIndicator> createState() => _BatteryIndicatorState();
}

class _BatteryIndicatorState extends State<BatteryIndicator> {
  int _level = 100;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final level = await Battery().batteryLevel;
      if (mounted) setState(() => _level = level);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  IconData get _icon => _level > 80
      ? Icons.battery_full
      : _level > 50
          ? Icons.battery_5_bar
          : _level > 20
              ? Icons.battery_3_bar
              : Icons.battery_1_bar;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Shadowed(child: Icon(_icon, color: Colors.white, size: 18)),
        const SizedBox(width: 4),
        _Shadowed(
          child: Text(
            '$_level%',
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

/// Wraps [child] with a dark dropshadow offset by (2,2) for legibility
/// against light or animated backgrounds.
class _Shadowed extends StatelessWidget {
  const _Shadowed({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 2,
          top: 2,
          child: _recolor(child, const Color(0xFF404040)),
        ),
        child,
      ],
    );
  }

  static Widget _recolor(Widget child, Color color) {
    if (child is Icon) return Icon(child.icon, size: child.size, color: color);
    if (child is Text) {
      return DefaultTextStyle(
        style: child.style ?? const TextStyle(),
        child: Text(
          child.data ?? '',
          style: (child.style ?? const TextStyle()).copyWith(color: color),
        ),
      );
    }
    return child;
  }
}
