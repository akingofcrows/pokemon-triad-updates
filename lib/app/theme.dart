import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const seed = Color(0xFF2196F3);
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF10101C),
    colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
    fontFamily: 'PowerGreen',
    appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF181828), elevation: 0),
  );
}
