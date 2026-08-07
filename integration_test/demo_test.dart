import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livraison_mobile/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo des fonctionnalités principales', (tester) async {
    await tester.pumpWidget(const LivraisonApp());
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01-tournee-vide');

    await tester.tap(find.text('Ajouter une livraison'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Client de démonstration');
    await tester.enterText(fields.at(1), '1 rue de la Démonstration');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('02-livraison-ajoutee');

    await tester.tap(find.text('Photo de preuve'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('03-options-preuve-photo');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Enregistrer la journée'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Enregistrer la journée'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('04-journee-enregistree');

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('05-historique-local');
    await tester.tap(find.text('Exporter'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('06-export-chiffre');
  });
}
