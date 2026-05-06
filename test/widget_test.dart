// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:text_flow/main.dart';

void main() {
  testWidgets('SMS/MMS listener page renders core text', (WidgetTester tester) async {
    await tester.pumpWidget(const TextFlowApp());
    await tester.pump();

    expect(find.text('TextFlow SMS/MMS Listener'), findsOneWidget);
    expect(find.text('최근 수신 메시지'), findsOneWidget);
    expect(find.text('테스트 방법'), findsOneWidget);
  });
}
