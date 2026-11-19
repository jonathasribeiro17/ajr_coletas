import 'package:flutter/material.dart';
import '../screens/home/home_screen.dart';

class AJRColetasApp extends StatelessWidget {
const AJRColetasApp({super.key});

@override
Widget build(BuildContext context) {
return MaterialApp(
title: 'AJR Coletas',
debugShowCheckedModeBanner: false,


  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.deepPurple,
    ),
    useMaterial3: true,
  ),

  home: const HomeScreen(
    nomeMotorista: 'Motorista',
  ),
);
}
}
