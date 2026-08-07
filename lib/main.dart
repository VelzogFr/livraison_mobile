import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signature/signature.dart';

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
    this.signature,
  });
  final String destinataire;
  final String adresse;
  String statut;
  File? photo;
  Uint8List? signature;
}

class TourneePage extends StatefulWidget {
  const TourneePage({super.key});

  @override
  State<TourneePage> createState() => _TourneePageState();
}

class _TourneePageState extends State<TourneePage> {
  final _notesController = TextEditingController();
  final _mileageController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  final _picker = ImagePicker();
  final _livraisons = <Livraison>[
    Livraison(
      destinataire: 'Sophie Martin',
      adresse: '12 rue des Lilas, Paris',
    ),
    Livraison(
      destinataire: 'Boulangerie des Arts',
      adresse: '8 avenue Victor Hugo, Paris',
      statut: 'Livré',
    ),
    Livraison(
      destinataire: 'Thomas Bernard',
      adresse: '4 impasse du Moulin, Montreuil',
    ),
  ];
  List<Map<String, dynamic>> _history = [];
  bool _historyLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getStringList('saved_days') ?? [];
    if (!mounted) return;
    setState(() {
      _history = encoded
          .map((item) => jsonDecode(item) as Map<String, dynamic>)
          .toList();
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
            'hasSignature': delivery.signature != null,
          },
        )
        .toList(),
  };

  Future<void> _persistDay() async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = _daySnapshot();
    final updated = [snapshot, ..._history];
    await prefs.setStringList(
      'saved_days',
      updated.map((item) => jsonEncode(item)).toList(),
    );
    if (!mounted) return;
    setState(() => _history = updated);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _mileageController.dispose();
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

  Future<void> _showSignature(Livraison livraison) async {
    final controller = SignatureController(
      penStrokeWidth: 3,
      penColor: const Color(0xFF172B4D),
      exportBackgroundColor: Colors.white,
    );
    final result = await showDialog<Uint8List>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Signature du destinataire'),
        content: SizedBox(
          width: 420,
          height: 230,
          child: Column(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Signature(
                    controller: controller,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: controller.clear,
                  child: const Text('Effacer'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.isEmpty) return;
              final png = await controller.toPngBytes();
              if (!context.mounted || png == null) return;
              Navigator.pop(context, png);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    final directory = await getApplicationDocumentsDirectory();
    final file = File(
      '${directory.path}/signature_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(result);
    if (!mounted) return;
    setState(() {
      livraison.signature = result;
      livraison.statut = 'Livré';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signature enregistrée hors ligne')),
    );
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
    await prefs.remove('saved_days');
    if (!mounted) return;
    setState(() => _history = []);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Historique local supprimé')));
  }

  Future<void> _exportHistory() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/historique_livraison.json');
    await file.writeAsString(jsonEncode(_history));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Export local créé : ${file.path}')));
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
              'Bonjour, Lucas 👋',
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
                hintText: 'Ex. 128450',
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
            ..._livraisons.asMap().entries.map(
              (entry) => _DeliveryCard(
                index: entry.key + 1,
                livraison: entry.value,
                onPhoto: () => _showPhotoOptions(entry.value),
                onSignature: () => _showSignature(entry.value),
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
    required this.onSignature,
  });
  final int index;
  final Livraison livraison;
  final VoidCallback onPhoto;
  final VoidCallback onSignature;

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
                        livraison.adresse,
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
                    if (livraison.signature != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            livraison.signature!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.contain,
                          ),
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
                        label: const Text('Photo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSignature,
                        icon: const Icon(Icons.draw_outlined),
                        label: const Text('Signature'),
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
