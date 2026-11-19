import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


import 'screens/login/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://qeczjzxnoinjprdiwtxn.supabase.co',
    publishableKey: 'sb_publishable_xJhXMefVhnrD0bBmZv3kbQ_9tNUVZPC',
  );

  runApp(const AJRColetasApp());
}

class AJRColetasApp extends StatelessWidget {
  const AJRColetasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AJR Coletas',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}