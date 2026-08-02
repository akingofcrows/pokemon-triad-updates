import 'dart:math';

/// Simple game-world time and weather system.
enum DayPeriod { morning, afternoon, evening, night }

enum Weather { clear, rain, fog }

class WorldClock {
  WorldClock._();
  static final WorldClock instance = WorldClock._();

  final _rng = Random();

  /// Get the current day period based on real local time.
  DayPeriod get dayPeriod {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return DayPeriod.morning;
    if (hour >= 12 && hour < 17) return DayPeriod.afternoon;
    if (hour >= 17 && hour < 21) return DayPeriod.evening;
    return DayPeriod.night;
  }

  /// Get the current weather (randomized, weighted toward clear).
  Weather get weather {
    final roll = _rng.nextDouble();
    if (roll < 0.60) return Weather.clear;
    if (roll < 0.85) return Weather.rain;
    return Weather.fog;
  }

  /// Generate the opening narration based on time/weather.
  List<String> buildNarration(Weather weather, DayPeriod period) {
    final lines = <String>[];
    final isMorning = period == DayPeriod.morning;
    final periodWord = isMorning ? 'morning' : 'afternoon';

    switch (weather) {
      case Weather.clear:
        lines.addAll([
          '${isMorning ? "Morning sunlight" : "The $periodWord sun"} stretches across Pallet Town.',
          'A warm breeze moves through the trees, carrying the distant cries of Pidgey from Route 1. Beyond your window, the sky is clear and the road north waits beneath the ${isMorning ? "rising" : "bright"} sun.',
        ]);
      case Weather.rain:
        lines.addAll([
          'Rain falls steadily over Pallet Town.',
          'Droplets trace winding paths down your bedroom window while dark clouds gather above Route 1. Somewhere beyond the houses, distant thunder rolls across the coast.',
        ]);
      case Weather.fog:
        lines.addAll([
          'A pale fog has settled over Pallet Town.',
          'The nearby houses are little more than shapes beyond your window, and the entrance to Route 1 has vanished into the ${isMorning ? "morning" : "afternoon"} mist. Even the sea is unusually quiet.',
        ]);
    }

    lines.add('Today, your journey begins.');
    lines.add('You slowly open your eyes in your bedroom.');
    return lines;
  }

  /// Get a single word description of the weather.
  String get weatherWord {
    switch (weather) {
      case Weather.clear:
        return 'Clear';
      case Weather.rain:
        return 'Rain';
      case Weather.fog:
        return 'Fog';
    }
  }

  /// Get a display string for the current time.
  String get timeDisplay {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
