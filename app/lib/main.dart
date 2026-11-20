import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MovieBoxApp());
}

class MovieBoxApp extends StatelessWidget {
  const MovieBoxApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MOVIE BOX',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF09090F),
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8B5CF6),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: const HomeScreen(),
  );
}
