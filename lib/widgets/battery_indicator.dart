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
        _Shadowed(child: Icon(_icon, color: Colors.white.withValues(alpha: 0.4), size: 18)),
        const SizedBox(width: 4),
        _Shadowed(
          child: Text(
            '$_level%',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Wraps [child] with a dark dropshadow offset right by 2px for legibility
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
          top: 0,
          child: child is Text
              ? Text(
                  (child as Text).data ?? '',
                  style: ((child as Text).style ?? const TextStyle()).copyWith(color: const Color(0xFF242529)),
                )
              : child is Icon
                  ? Icon((child as Icon).icon, size: (child as Icon).size, color: const Color(0xFF242529))
                  : child,
        ),
        child,
      ],
    );
  }
}
