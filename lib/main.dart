import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_download.dart';

const _demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: false);

void main() => runApp(const LivraisonApp());

class LivraisonApp extends StatelessWidget {
  const LivraisonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ma tournée',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF155EEF)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
        ),
      ),
      home: const TourneePage(),
    );
  }
}

class Livraison {
  Livraison({
    required this.destinataire,
    required this.adresse,
    this.commentaire = '',
    this.statut = 'À faire',
    List<Uint8List>? photos,
  }) : photos = photos ?? <Uint8List>[];
  String destinataire;
  String adresse;
  String commentaire;
  String statut;
  final List<Uint8List> photos;

  Uint8List? get photoBytes => photos.isEmpty ? null : photos.first;

  set photoBytes(Uint8List? value) {
    photos
      ..clear()
      ..addAll(value == null ? const <Uint8List>[] : [value]);
  }
}

class TourneePage extends StatefulWidget {
  const TourneePage({super.key});

  @override
  State<TourneePage> createState() => _TourneePageState();
}

class _TourneePageState extends State<TourneePage> {
  final _notesController = TextEditingController();
  final _mileageController = TextEditingController();
  final _profileNameController = TextEditingController();
  final _profileLoginController = TextEditingController();
  Uint8List? _avatarBytes;
  DateTime _selectedDate = DateTime.now();
  final _picker = ImagePicker();
  final _livraisons = <Livraison>[];
  List<Map<String, dynamic>> _history = [];
  bool _historyLoading = true;
  bool _profileLoading = true;
  bool _savingDay = false;
  final _secureStorage = const FlutterSecureStorage();
  final _cipher = AesGcm.with256bits();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadProfile();
    if (_demoMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runDemo());
    }
  }

  Future<void> _runDemo() async {
    for (
      var attempt = 0;
      attempt < 50 && (_profileLoading || _historyLoading);
      attempt++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;
    await Future<void>.delayed(const Duration(seconds: 1));
    final delivery = Livraison(
      destinataire: 'Client de démonstration',
      adresse: '',
    );
    setState(() => _livraisons.add(delivery));
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    await _showPhotoOptions(delivery, demo: true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    await _persistDay();
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) await _showHistory();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _profileNameController.text = prefs.getString('local_profile_name') ?? '';
    _profileLoginController.text = prefs.getString('local_profile_login') ?? '';
    final avatar = prefs.getString('local_profile_avatar');
    _avatarBytes = avatar == null ? null : base64Decode(avatar);
    setState(() => _profileLoading = false);
  }

  Future<SecretKey> _getEncryptionKey() async {
    var encoded = await _secureStorage.read(key: 'local_history_key');
    if (encoded == null) {
      final key = await _cipher.newSecretKey();
      final bytes = await key.extractBytes();
      encoded = base64UrlEncode(bytes);
      await _secureStorage.write(key: 'local_history_key', value: encoded);
    }
    return SecretKey(base64Url.decode(encoded));
  }

  Future<String> _encryptHistory(List<Map<String, dynamic>> history) async {
    final key = await _getEncryptionKey();
    final nonce = _cipher.newNonce();
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(history)),
      secretKey: key,
      nonce: nonce,
    );
    return jsonEncode({
      'nonce': base64UrlEncode(nonce),
      'cipherText': base64UrlEncode(box.cipherText),
      'mac': base64UrlEncode(box.mac.bytes),
    });
  }

  Future<List<Map<String, dynamic>>> _decryptHistory(String encoded) async {
    final payload = jsonDecode(encoded) as Map<String, dynamic>;
    final box = SecretBox(
      base64Url.decode(payload['cipherText'] as String),
      nonce: base64Url.decode(payload['nonce'] as String),
      mac: Mac(base64Url.decode(payload['mac'] as String)),
    );
    final clear = await _cipher.decrypt(
      box,
      secretKey: await _getEncryptionKey(),
    );
    final values = jsonDecode(utf8.decode(clear)) as List<dynamic>;
    return values
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Uint8List> _compactPhoto(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final resized = decoded.width > 1280 || decoded.height > 1280
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 1280 : null,
            height: decoded.height > decoded.width ? 1280 : null,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: 60));
  }

  Future<List<Map<String, dynamic>>> _compactHistoryPhotos(
    List<Map<String, dynamic>> history,
  ) async {
    for (final day in history) {
      final deliveries = day['deliveries'];
      if (deliveries is! List) continue;
      for (final item in deliveries) {
        if (item is! Map) continue;
        final values = item['photosBase64'];
        if (values is List) {
          final compacted = <String>[];
          for (final value in values.whereType<String>()) {
            try {
              final bytes = await _compactPhoto(base64Decode(value));
              compacted.add(base64Encode(bytes));
            } on FormatException {
              compacted.add(value);
            }
          }
          item['photosBase64'] = compacted;
        } else if (item['photoBase64'] is String) {
          try {
            final bytes = await _compactPhoto(
              base64Decode(item['photoBase64'] as String),
            );
            item['photoBase64'] = base64Encode(bytes);
          } on FormatException {
            // Keep malformed legacy data unchanged for compatibility.
          }
        }
      }
    }
    return history;
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> loaded = [];
    final encrypted = prefs.getString('saved_days_encrypted');
    if (encrypted != null) {
      loaded = await _decryptHistory(encrypted);
    } else {
      final legacy = prefs.getStringList('saved_days') ?? [];
      if (legacy.isNotEmpty) {
        loaded = legacy
            .map((item) => jsonDecode(item) as Map<String, dynamic>)
            .toList();
        await prefs.setString(
          'saved_days_encrypted',
          await _encryptHistory(loaded),
        );
        await prefs.remove('saved_days');
      }
    }
    if (loaded.isNotEmpty) {
      loaded = await _compactHistoryPhotos(loaded);
      try {
        await prefs.setString(
          'saved_days_encrypted',
          await _encryptHistory(loaded),
        );
        await prefs.remove('saved_days');
      } catch (_) {
        // Keep the in-memory history available if the browser quota is full.
      }
    }
    if (!mounted) return;
    setState(() {
      _history = loaded;
      _historyLoading = false;
    });
  }

  Map<String, dynamic> _daySnapshot() => {
    'date': _dateLabel,
    'mileage': _mileageController.text.trim(),
    'notes': _notesController.text.trim(),
    'savedAt': DateTime.now().toIso8601String(),
    'deliveries': _livraisons
        .map(
          (delivery) => {
            'name': delivery.destinataire,
            'address': delivery.adresse,
            'comment': delivery.commentaire,
            'status': delivery.statut,
            'hasPhoto': delivery.photos.isNotEmpty,
            'photosBase64': delivery.photos.map(base64Encode).toList(),
          },
        )
        .toList(),
  };

  Future<void> _persistDay() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = _daySnapshot();
    final updated = [snapshot, ..._history];
    await prefs.setString(
      'saved_days_encrypted',
      await _encryptHistory(updated),
    );
    await prefs.remove('saved_days');
    if (!mounted) return;
    setState(() => _history = updated);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _mileageController.dispose();
    _profileNameController.dispose();
    _profileLoginController.dispose();
    super.dispose();
  }

  int get _livrees => _livraisons.where((l) => l.statut == 'Livré').length;

  String get _dateLabel =>
      '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}';

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) setState(() => _selectedDate = date);
  }

  Future<void> _addPhoto(Livraison livraison, ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    final bytes = await _compactPhoto(await file.readAsBytes());
    if (!mounted) return;
    setState(() {
      livraison.photos.add(bytes);
      livraison.statut = 'Livré';
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Photo de preuve ajoutée')));
  }

  Future<void> _addGalleryPhotos(Livraison livraison) async {
    final files = await _picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    final bytes = <Uint8List>[];
    for (final file in files) {
      bytes.add(await _compactPhoto(await file.readAsBytes()));
    }
    if (!mounted) return;
    setState(() {
      livraison.photos.addAll(bytes);
      livraison.statut = 'Livré';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${bytes.length} photo(s) ajoutée(s)')),
    );
  }

  Future<void> _showPhotoOptions(
    Livraison livraison, {
    bool demo = false,
  }) async {
    final sheet = showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(context);
                _addPhoto(livraison, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir une ou plusieurs photos'),
              onTap: () {
                Navigator.pop(context);
                _addGalleryPhotos(livraison);
              },
            ),
          ],
        ),
      ),
    );
    if (demo) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
    await sheet;
  }

  Future<void> _removePhoto(Livraison livraison, int photoIndex) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la photo ?'),
        content: const Text('La preuve photo sera retirée de cette livraison.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      livraison.photos.removeAt(photoIndex);
      if (livraison.photos.isEmpty) livraison.statut = 'À faire';
    });
  }

  Future<void> _addDelivery() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final comment = TextEditingController();
    Uint8List? photoBytes;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Ajouter une livraison'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nom du client'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(
                    labelText: 'Adresse (facultative)',
                    hintText: 'Laisser vide si inconnue',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: comment,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Commentaire (facultatif)',
                    hintText: 'Ajouter une précision pour cette livraison',
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Photo de preuve (facultatif)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (photoBytes != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(
                          photoBytes!,
                          width: 58,
                          height: 58,
                          fit: BoxFit.cover,
                        ),
                      ),
                    if (photoBytes != null) const SizedBox(width: 10),
                    Expanded(
                      child: Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              final file = await _picker.pickImage(
                                source: ImageSource.camera,
                                imageQuality: 85,
                              );
                              if (file == null) return;
                              final bytes = await _compactPhoto(
                                await file.readAsBytes(),
                              );
                              setDialogState(() => photoBytes = bytes);
                            },
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Caméra'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              final file = await _picker.pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 85,
                              );
                              if (file == null) return;
                              final bytes = await _compactPhoto(
                                await file.readAsBytes(),
                              );
                              setDialogState(() => photoBytes = bytes);
                            },
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Galerie'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && name.text.trim().isNotEmpty && mounted) {
      setState(
        () => _livraisons.add(
          Livraison(
            destinataire: name.text.trim(),
            adresse: address.text.trim(),
            commentaire: comment.text.trim(),
            statut: photoBytes == null ? 'À faire' : 'Livré',
            photos: photoBytes == null ? [] : [photoBytes!],
          ),
        ),
      );
    }
    name.dispose();
    address.dispose();
    comment.dispose();
  }

  Future<void> _editDelivery(Livraison livraison) async {
    final name = TextEditingController(text: livraison.destinataire);
    final address = TextEditingController(text: livraison.adresse);
    final comment = TextEditingController(text: livraison.commentaire);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Modifier la livraison'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nom du client'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: address,
                decoration: const InputDecoration(
                  labelText: 'Adresse (facultative)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: comment,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Commentaire (facultatif)',
                  hintText: 'Ajouter une précision pour cette livraison',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (confirmed == true && name.text.trim().isNotEmpty && mounted) {
      setState(() {
        livraison.destinataire = name.text.trim();
        livraison.adresse = address.text.trim();
        livraison.commentaire = comment.text.trim();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Livraison modifiée')));
    }
    name.dispose();
    address.dispose();
    comment.dispose();
  }

  Future<void> _showProfile() async {
    if (_profileLoading) return;
    final controller = TextEditingController(text: _profileNameController.text);
    final loginController = TextEditingController(
      text: _profileLoginController.text,
    );
    var avatarBytes = _avatarBytes;
    final sheet = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profil local',
                style: Theme.of(sheetContext).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Ce profil reste sur ce téléphone. Il ne s’agit pas d’une connexion Google ou d’un compte cloud.',
              ),
              const SizedBox(height: 16),
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundImage: avatarBytes == null
                          ? null
                          : MemoryImage(avatarBytes!),
                      child: avatarBytes == null
                          ? const Icon(Icons.person_outline, size: 42)
                          : null,
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await _picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 80,
                        );
                        if (picked == null || !sheetContext.mounted) return;
                        final bytes = await picked.readAsBytes();
                        if (!sheetContext.mounted) return;
                        setModalState(() => avatarBytes = bytes);
                      },
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Choisir un avatar'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nom du profil',
                  hintText: 'Saisir un nom',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: loginController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Identifiant de connexion local',
                  hintText: 'ex. prenom.nom',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString(
                      'local_profile_name',
                      controller.text.trim(),
                    );
                    await prefs.setString(
                      'local_profile_login',
                      loginController.text.trim(),
                    );
                    if (avatarBytes == null) {
                      await prefs.remove('local_profile_avatar');
                    } else {
                      await prefs.setString(
                        'local_profile_avatar',
                        base64Encode(avatarBytes!),
                      );
                    }
                    if (!sheetContext.mounted) return;
                    _profileNameController.text = controller.text.trim();
                    _profileLoginController.text = loginController.text.trim();
                    _avatarBytes = avatarBytes;
                    Navigator.pop(sheetContext);
                    if (!mounted) return;
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Profil local enregistré')),
                    );
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Enregistrer le profil'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await sheet;
    controller.dispose();
    loginController.dispose();
  }

  Future<void> _saveDay() async {
    if (_savingDay) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la journée'),
        content: const Text(
          'La journée sera enregistrée uniquement sur ce téléphone, sans envoi serveur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _savingDay = true);
    try {
      await _persistDay();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Journée enregistrée localement : $_livrees/${_livraisons.length} livraisons',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enregistrement impossible : ${error.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingDay = false);
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer l’historique ?'),
        content: const Text(
          'Cette action supprime toutes les journées enregistrées sur ce téléphone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_days_encrypted');
    await prefs.remove('saved_days');
    if (!mounted) return;
    setState(() => _history = []);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Historique local supprimé')));
  }

  Future<void> _importHistory() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'Sauvegarde Livraison',
          extensions: ['livraison-backup'],
        ),
      ],
    );
    if (file == null) return;
    try {
      final raw = utf8.decode(await file.readAsBytes());
      final backup = jsonDecode(raw) as Map<String, dynamic>;
      final encoded = backup['payload'] as String;
      final imported = await _decryptHistory(encoded);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'saved_days_encrypted',
        await _encryptHistory(imported),
      );
      await prefs.remove('saved_days');
      if (!mounted) return;
      setState(() => _history = imported);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${imported.length} journée(s) importée(s)')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d’importer cette sauvegarde chiffrée sur cet appareil.',
          ),
        ),
      );
    }
  }

  Future<void> _showPhotoPreview(Uint8List bytes, String title) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Stack(
            alignment: Alignment.topRight,
            children: [
              Image.memory(bytes, fit: BoxFit.contain),
              IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                tooltip: 'Fermer',
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportHistory() async {
    final backup = {
      'format': 'livraison_mobile_encrypted_backup_v1',
      'createdAt': DateTime.now().toIso8601String(),
      'payload': await _encryptHistory(_history),
    };
    final path = await saveBackupFile(
      'historique_livraison.livraison-backup',
      jsonEncode(backup),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sauvegarde chiffrée créée : $path')),
    );
  }

  List<Uint8List> _historyPhotos(Map<String, dynamic> delivery) {
    final values = delivery['photosBase64'];
    if (values is List) {
      return values
          .whereType<String>()
          .map((value) {
            try {
              return base64Decode(value);
            } on FormatException {
              return null;
            }
          })
          .whereType<Uint8List>()
          .toList();
    }
    final legacy = _historyPhoto(delivery);
    return legacy == null ? <Uint8List>[] : [legacy];
  }

  Uint8List? _historyPhoto(Map<String, dynamic> delivery) {
    final encoded = delivery['photoBase64'];
    if (encoded is! String || encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }

  Future<void> _showHistoryDay(Map<String, dynamic> day) async {
    final deliveries = (day['deliveries'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Journée du ${day['date']}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Kilométrage : ${day['mileage'].toString().isEmpty ? 'non renseigné' : '${day['mileage']} km'}',
                ),
                if ((day['notes'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Compte-rendu : ${day['notes']}'),
                ],
                const SizedBox(height: 16),
                if (deliveries.isEmpty)
                  const Text('Aucune livraison enregistrée.')
                else
                  ...deliveries.map(
                    (delivery) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _historyPhotos(delivery).isEmpty
                                ? const Icon(Icons.local_shipping_outlined)
                                : SizedBox(
                                    width: 160,
                                    height: 72,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _historyPhotos(
                                        delivery,
                                      ).length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(width: 6),
                                      itemBuilder: (context, index) {
                                        final photo = _historyPhotos(
                                          delivery,
                                        )[index];
                                        return GestureDetector(
                                          onTap: () => _showPhotoPreview(
                                            photo,
                                            delivery['name'] as String? ??
                                                'Photo de preuve',
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                            child: Image.memory(
                                              photo,
                                              width: 72,
                                              height: 72,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    delivery['name'] as String? ?? 'Client',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    (delivery['address'] as String?)
                                                ?.isNotEmpty ==
                                            true
                                        ? delivery['address'] as String
                                        : 'Adresse non renseignée',
                                  ),
                                  Text(
                                    'Statut : ${delivery['status'] ?? 'À faire'}',
                                  ),
                                  if ((delivery['comment'] as String? ?? '')
                                      .isNotEmpty)
                                    Text(
                                      'Commentaire : ${delivery['comment']}',
                                      style: TextStyle(
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                  if (_historyPhotos(delivery).isNotEmpty)
                                    const Text('Photo de preuve enregistrée'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showHistory() async {
    if (_historyLoading) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: _history.isEmpty
              ? const Center(child: Text('Aucune journée enregistrée.'))
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'Historique local',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _exportHistory,
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Exporter'),
                        ),
                        TextButton.icon(
                          onPressed: _importHistory,
                          icon: const Icon(Icons.upload_file_outlined),
                          label: const Text('Importer'),
                        ),
                        TextButton.icon(
                          onPressed: _clearHistory,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Tout supprimer'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ..._history.map(
                      (day) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.event_available),
                          title: Text('Journée du ${day['date']}'),
                          subtitle: Text(
                            '${(day['deliveries'] as List<dynamic>? ?? []).length} livraison(s) · Kilométrage : ${day['mileage'].toString().isEmpty ? 'non renseigné' : '${day['mileage']} km'}\nAppuyer pour voir les informations et les photos',
                          ),
                          onTap: () => _showHistoryDay(day),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Center(
              child: Text(
                'Journal de bord de ma journée',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('Date de la journée : $_dateLabel'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _mileageController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Kilométrage du jour',
                hintText: 'Saisir le kilométrage',
                suffixText: 'km',
                prefixIcon: Icon(Icons.speed_outlined),
              ),
            ),
            const SizedBox(height: 16),
            _ProgressCard(done: _livrees, total: _livraisons.length),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Livraisons du jour',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$_livrees/${_livraisons.length}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addDelivery,
              icon: const Icon(Icons.person_add_alt_1_outlined),
              label: const Text('Ajouter une livraison'),
            ),
            if (_livraisons.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('Aucune livraison ajoutée.')),
              ),
            ..._livraisons.asMap().entries.map(
              (entry) => _DeliveryCard(
                index: entry.key + 1,
                livraison: entry.value,
                onPhoto: () => _showPhotoOptions(entry.value),
                onRemovePhoto: (photoIndex) =>
                    _removePhoto(entry.value, photoIndex),
                onEdit: () => _editDelivery(entry.value),
                onPreview: (bytes) =>
                    _showPhotoPreview(bytes, entry.value.destinataire),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Compte-rendu de la journée',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText:
                    'Ajoutez une remarque, un incident ou une information utile…',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _savingDay ? null : _saveDay,
                icon: _savingDay
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  _savingDay ? 'Enregistrement…' : 'Enregistrer la journée',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (index) {
          if (index == 1) _showHistory();
          if (index == 2) _showProfile();
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Ma tournée',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: 'Historique'),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.done, required this.total});
  final int done;
  final int total;
  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : done / total;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF155EEF),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Progression de la tournée',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$done livraison${done > 1 ? 's' : ''} terminée${done > 1 ? 's' : ''} sur $total',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.index,
    required this.livraison,
    required this.onPhoto,
    required this.onRemovePhoto,
    required this.onEdit,
    required this.onPreview,
  });
  final int index;
  final Livraison livraison;
  final VoidCallback onPhoto;
  final ValueChanged<int> onRemovePhoto;
  final VoidCallback onEdit;
  final ValueChanged<Uint8List> onPreview;

  @override
  Widget build(BuildContext context) {
    final done = livraison.statut == 'Livré';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done ? Colors.green.shade50 : Colors.blue.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$index',
                    style: TextStyle(
                      color: done
                          ? Colors.green.shade700
                          : Colors.blue.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        livraison.destinataire,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        livraison.adresse.isEmpty
                            ? 'Adresse non renseignée'
                            : livraison.adresse,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                      if (livraison.commentaire.isNotEmpty)
                        Text(
                          livraison.commentaire,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                _StatusChip(done: done),
                IconButton(
                  onPressed: onEdit,
                  tooltip: 'Modifier la livraison',
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            if (done)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: livraison.photos.asMap().entries.map((
                            entry,
                          ) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Stack(
                                children: [
                                  GestureDetector(
                                    onTap: () => onPreview(entry.value),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.memory(
                                        entry.value,
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: InkWell(
                                      onTap: () => onRemovePhoto(entry.key),
                                      child: const CircleAvatar(
                                        radius: 10,
                                        child: Icon(Icons.close, size: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: onPhoto,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: const Text('Ajouter'),
                    ),
                  ],
                ),
              ),
            if (!done)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onPhoto,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Photo de preuve'),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.done});
  final bool done;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: done ? Colors.green.shade50 : Colors.orange.shade50,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      done ? 'Livré' : 'À faire',
      style: TextStyle(
        color: done ? Colors.green.shade700 : Colors.orange.shade800,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
