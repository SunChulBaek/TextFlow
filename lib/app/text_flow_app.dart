import 'package:flutter/material.dart';

import 'package:text_flow/features/sms/presentation/sms_listener_page.dart';

class TextFlowApp extends StatelessWidget {
  const TextFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TextFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF9A825),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF07090E),
      ),
      home: const SmsListenerPage(),
    );
  }
}


