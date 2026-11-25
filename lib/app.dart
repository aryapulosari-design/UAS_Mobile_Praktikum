import 'package:flutter/material.dart';

import 'screens/weather_screen.dart';
import 'services/favorites_store.dart';
import 'services/weather_service.dart';

class LangitKitaApp extends StatelessWidget {
  const LangitKitaApp({super.key, this.service, this.favoritesStore});

  final WeatherService? service;
  final FavoritesStore? favoritesStore;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF173E38);
    const background = Color(0xFFF7F8F2);
    return MaterialApp(
      title: 'LangitKita',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: ink,
          primary: ink,
          surface: background,
        ),
        cardTheme: const CardThemeData(color: Colors.white, elevation: 0),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          height: 64,
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: ink,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFDAE2D8)),
          ),
        ),
      ),
      home: WeatherScreen(service: service, favoritesStore: favoritesStore),
    );
  }
}
