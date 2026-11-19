import 'package:flutter_test/flutter_test.dart';
import 'package:ajr_coletas/main.dart';

void main() {
  testWidgets('AJR Coletas inicia corretamente', (WidgetTester tester) async {
    await tester.pumpWidget(const AJRColetasApp());

    await tester.pump();

    expect(find.byType(AJRColetasApp), findsOneWidget);
  });
}
