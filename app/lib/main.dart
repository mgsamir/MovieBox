import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
  runApp(const MovieBoxApp());
}
class MovieBoxApp extends StatelessWidget {
  const MovieBoxApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Movie Box', debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true, colorSchemeSeed: Colors.red),
    home: const HomeScreen());
}
