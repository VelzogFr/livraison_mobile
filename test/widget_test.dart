import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livraison_mobile/main.dart';

void main() {
  testWidgets('affiche le tableau de tournée du chauffeur', (tester) async {
    await tester.pumpWidget(const LivraisonApp());

    expect(find.text('Ma tournée'), findsAtLeastNWidgets(1));
    expect(find.text('Livraisons du jour'), findsOneWidget);
    expect(find.text('Sophie Martin'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Enregistrer la journée'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Enregistrer la journée'), findsOneWidget);
  });
}
