import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart'
    show AesGcm, Mac, SecretBox, SecretKey;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    this.statut = 'À faire',
    this.photo,
  });
  final String destinataire;
  final String adresse;
  String statut;
  File? photo;
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
  DateTime _selectedDate = DateTime.now();
  final _picker = ImagePicker();
  final _livraisons = <Livraison>[];
  List<Map<String, dynamic>> _history = [];
  bool _historyLoading = true;
  bool _profileLoading = true;
  final _secureStorage = const FlutterSecureStorage();
  final _cipher = AesGcm.with256bits();

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _profileNameController.text = prefs.getString('local_profile_name') ?? '';
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
            'status': delivery.statut,
            'hasPhoto': delivery.photo != null,
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
    if (file == null || !mounted) return;
    setState(() {
      livraison.photo = File(file.path);
      livraison.statut = 'Livré';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo de preuve enregistrée')),
    );
  }

  Future<void> _showPhotoOptions(Livraison livraison) async {
    await showModalBottomSheet<void>(
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
              title: const Text('Choisir dans la galerie'),
              onTap: () {
                Navigator.pop(context);
                _addPhoto(livraison, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addDelivery() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter une livraison'),
        content: Column(
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
                hintText: 'Laisser vide si inconnue',
              ),
            ),
          ],
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
    );
    if (confirmed == true && name.text.trim().isNotEmpty && mounted) {
      setState(
        () => _livraisons.add(
          Livraison(
            destinataire: name.text.trim(),
            adresse: address.text.trim(),
          ),
        ),
      );
    }
    name.dispose();
    address.dispose();
  }

  Future<void> _showProfile() async {
    if (_profileLoading) return;
    final controller = TextEditingController(text: _profileNameController.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(
                    'local_profile_name',
                    controller.text.trim(),
                  );
                  if (!sheetContext.mounted) return;
                  _profileNameController.text = controller.text.trim();
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
    );
    controller.dispose();
  }

  Future<void> _saveDay() async {
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
    await _persistDay();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Journée enregistrée localement : $_livrees/${_livraisons.length} livraisons',
        ),
      ),
    );
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

  Future<void> _exportHistory() async {
    final directory = await getApplicationDocumentsDirectory();
    final backup = {
      'format': 'livraison_mobile_encrypted_backup_v1',
      'createdAt': DateTime.now().toIso8601String(),
      'payload': await _encryptHistory(_history),
    };
    final file = File(
      '${directory.path}/historique_livraison.livraison-backup',
    );
    await file.writeAsString(jsonEncode(backup));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sauvegarde chiffrée créée : ${file.path}')),
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
                            'Kilométrage : ${day['mileage'].toString().isEmpty ? 'non renseigné' : '${day['mileage']} km'}',
                          ),
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
      appBar: AppBar(
        title: const Text(
          'Ma tournée',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Text(
              'Ma tournée du jour',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
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
                onPressed: _saveDay,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  'Enregistrer la journée',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
  });
  final int index;
  final Livraison livraison;
  final VoidCallback onPhoto;

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
                    ],
                  ),
                ),
                _StatusChip(done: done),
              ],
            ),
            if (done)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Row(
                  children: [
                    if (livraison.photo != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          livraison.photo!,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                        ),
                      ),

                    const Spacer(),
                    TextButton.icon(
                      onPressed: onPhoto,
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      label: const Text('Preuve'),
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
