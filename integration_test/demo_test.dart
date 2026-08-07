import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livraison_mobile/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demonstration fonctionnelle tournée, photo et profil local', (
    tester,
  ) async {
    await tester.pumpWidget(const LivraisonApp());
    await tester.pumpAndSettle();
    await binding.takeScreenshot('01-tournee-vide');

    await tester.tap(find.text('Ajouter une livraison'));
    await tester.pumpAndSettle();
    final dialogFields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogFields.at(0), 'Client de test');
    // L'adresse est volontairement laissée vide : elle est facultative.
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Adresse non renseignée'), findsOneWidget);
    await binding.takeScreenshot('02-adresse-facultative');

    await tester.tap(find.text('Photo de preuve'));
    await tester.pumpAndSettle();
    expect(find.text('Prendre une photo'), findsOneWidget);
    expect(find.text('Choisir dans la galerie'), findsOneWidget);
    await binding.takeScreenshot('03-options-photo');
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Profil local'), findsOneWidget);
    final profileField = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    await tester.enterText(profileField, 'Profil de test local');
    await tester.tap(find.text('Enregistrer le profil'));
    await tester.pumpAndSettle();
    expect(find.text('Profil local enregistré'), findsOneWidget);
    await binding.takeScreenshot('04-profil-local');

    await tester.scrollUntilVisible(
      find.text('Enregistrer la journée'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Enregistrer la journée'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('05-journee-enregistree');

    await tester.tap(find.text('Historique'));
    await tester.pumpAndSettle();
    expect(find.text('Historique local'), findsOneWidget);
    await binding.takeScreenshot('06-historique-local');
  });
}
