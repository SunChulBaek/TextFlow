import 'package:flutter/material.dart';

import 'package:text_flow/features/sms/presentation/sms_listener_page.dart';

const Color _brandSeedColorDark = Color(0xFF3D7CCC);
const Color _brandSeedColorLight = Color(0xFF4A90E2);

class TextFlowApp extends StatelessWidget {
  const TextFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TextFlow',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brandSeedColorLight,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brandSeedColorDark,
          brightness: Brightness.dark,
        ),
      ),
      home: const SmsListenerPage(),
    );
  }
}


