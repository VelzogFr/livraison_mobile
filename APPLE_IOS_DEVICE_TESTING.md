# Test sur un vrai iPhone

Windows ne peut pas compiler ni signer directement une application iOS. Le projet contient maintenant le workflow GitHub Actions `.github/workflows/ios-device.yml` qui prépare une IPA signée sur un runner macOS.

## Prérequis Apple

1. Un compte Apple Developer payant.
2. Le bundle ID `com.velzog.livraison.livraisonMobile` enregistré dans Apple Developer.
3. Un certificat de distribution Apple exporté en `.p12`.
4. Un provisioning profile **Ad Hoc** associé au bundle ID.
5. L’UDID de l’iPhone enregistré dans le provisioning profile.

## Secrets GitHub requis

Configurer ces secrets dans `VelzogFr/livraison_mobile` avec `gh secret set` ou l’interface GitHub. Ne jamais les commiter ni les envoyer dans Discord :

- `IOS_CERTIFICATE_BASE64` : certificat `.p12` encodé en base64 ;
- `IOS_CERTIFICATE_PASSWORD` : mot de passe du `.p12` ;
- `IOS_KEYCHAIN_PASSWORD` : mot de passe temporaire du trousseau CI ;
- `IOS_PROVISIONING_PROFILE_BASE64` : profil `.mobileprovision` encodé en base64 ;
- `APPLE_TEAM_ID` : Team ID Apple, non secret mais conservé en secret CI.

Le workflow échoue explicitement si un secret manque. Aucun secret Apple n’est présent actuellement dans le dépôt.

## Exécution

Lancer manuellement l’action **Build signed iOS device IPA**. Si elle réussit, télécharger l’artefact `livraison_mobile-ios-device-ipa` puis installer l’IPA sur l’iPhone enregistré avec Apple Configurator, Xcode ou un outil de distribution Ad Hoc.

Pour une installation plus simple par TestFlight, il faudra ajouter séparément une publication App Store Connect avec une clé API Apple. Cette clé ne doit pas être ajoutée au dépôt ; elle doit rester dans les secrets GitHub.

## Limites actuelles

- Le compte Apple Developer et les secrets de signature ne sont pas configurés dans GitHub.
- Aucun appareil réel n’est encore enregistré dans un provisioning profile vérifié.
- Une IPA réelle ne peut donc pas encore être produite depuis cet environnement tant que ces prérequis Apple ne sont pas fournis.
- L’artefact Simulator `.app` existant n’est pas installable sur un iPhone réel.
