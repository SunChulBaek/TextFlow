import 'package:flutter/material.dart';

import 'package:text_flow/features/sms/presentation/sms_listener_page.dart';

const Color _brandSeedColorDark = Color(0xFF3D7CCC);
const Color _brandSeedColorLight = Color(0xFF2563EB);
const Color _brandPrimaryLight = Color(0xFF005BFF);

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
        ).copyWith(
          primary: _brandPrimaryLight,
          secondary: _brandPrimaryLight,
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


