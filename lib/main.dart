import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'firebase_options.dart';
import 'auth_screen.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notlarım',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF), brightness: Brightness.light),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6C63FF), brightness: Brightness.dark),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      themeMode: ThemeMode.system,
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasData) return const NotListesi();
          return const AuthScreen();
        },
      ),
    );
  }
}

class Not {
  String? id;
  String baslik;
  String icerik;
  DateTime tarih;
  Color renk;
  List<Map<String, dynamic>> gorselVerileri;
  List<String> etiketler;
  String? userId;

  Not({
    this.id, required this.baslik, required this.icerik,
    required this.tarih, required this.renk,
    this.gorselVerileri = const [], this.etiketler = const [],
    this.userId,
  });

  Map<String, dynamic> toFirestore() => {
    'baslik': baslik, 'icerik': icerik, 'tarih': Timestamp.fromDate(tarih),
    'renk': renk.value, 'gorselVerileri': gorselVerileri, 'etiketler': etiketler,
    'userID': FirebaseAuth.instance.currentUser?.uid,
  };

  factory Not.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Not(
      id: doc.id, baslik: data['baslik'] ?? '', icerik: data['icerik'] ?? '',
      tarih: (data['tarih'] as Timestamp).toDate(), renk: Color(data['renk'] ?? 0xFF6C63FF),
      gorselVerileri: List<Map<String, dynamic>>.from(data['gorselVerileri'] ?? []),
      etiketler: List<String>.from(data['etiketler'] ?? []),
      userId: data['userID'],
    );
  }
}

final List<Color> kartRenkleri = [
  const Color(0xFFFF6B6B), const Color(0xFF6C63FF), const Color(0xFF48CFAD),
  const Color(0xFFFFCE54), const Color(0xFF4FC1E9), const Color(0xFFFF9F43),
];

class NotListesi extends StatefulWidget {
  const NotListesi({super.key});

  @override
  State<NotListesi> createState() => _NotListesiState();
}

class _NotListesiState extends State<NotListesi> {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _picker = ImagePicker();
  final stt.SpeechToText _speech = stt.SpeechToText();

  List<Not> tumNotlar = [];
  List<Not> filtrelenmisNotlar = [];
  List<String> dinamikEtiketler = [];
  String aramaMetni = '';
  String _seciliFiltre = 'Tümü';
  bool _yukleniyor = true;
  bool _secimModu = false;
  Set<String> _seciliNotlar = {};
  int _kullaniciXP = 0;

  @override
  void initState() {
    super.initState();
    _notlariDinle();
    _xpYukle();
  }

  void _notlariDinle() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    _firestore
        .collection('notlar')
        .where('userID', isEqualTo: uid)
        .orderBy('tarih', descending: true)
        .snapshots()
        .listen((snap) {
      List<Not> yuklenenler = snap.docs.map((doc) => Not.fromFirestore(doc)).toList();
      Set<String> etiketlerSeti = {};
      for (var n in yuklenenler) { etiketlerSeti.addAll(n.etiketler); }
      setState(() {
        tumNotlar = yuklenenler;
        dinamikEtiketler = etiketlerSeti.toList();
        _yukleniyor = false;
        _filtrele();
      });
    });
  }

  void _filtrele() {
    setState(() {
      filtrelenmisNotlar = tumNotlar.where((n) {
        bool aramaUyuyor = n.baslik.toLowerCase().contains(aramaMetni.toLowerCase()) ||
            n.icerik.toLowerCase().contains(aramaMetni.toLowerCase());
        bool etiketUyuyor = _seciliFiltre == 'Tümü' || n.etiketler.contains(_seciliFiltre);
        return aramaUyuyor && etiketUyuyor;
      }).toList();
    });
  }

  Future<void> _xpYukle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _kullaniciXP = prefs.getInt('kullaniciXP') ?? 0);
  }

  Future<void> _xpEkle(int miktar) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _kullaniciXP += miktar; });
    await prefs.setInt('kullaniciXP', _kullaniciXP);
  }

  Future<String> _tekGorselYukle(XFile dosya, String notId) async {
    final ref = _storage.ref().child('notlar/$notId/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(File(dosya.path));
    return await ref.getDownloadURL();
  }

  Future<void> _seciliNotlariSil() async {
    for (final id in _seciliNotlar) {
      await _firestore.collection('notlar').doc(id).delete();
    }
    setState(() { _seciliNotlar.clear(); _secimModu = false; });
  }

  String _tarihFormat(DateTime tarih) {
    final fark = DateTime.now().difference(tarih);
    if (fark.inMinutes < 1) return 'Az önce';
    if (fark.inHours < 1) return '${fark.inMinutes} dk önce';
    if (fark.inDays < 1) return '${fark.inHours} saat önce';
    return '${tarih.day}.${tarih.month}.${tarih.year}';
  }

  Widget _mdButon(String etiket, String metin, TextEditingController controller) {
    return ActionChip(
      label: Text(etiket, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
      onPressed: () => controller.text = controller.text + metin,
    );
  }

  Future<void> _notEkleVeyaDuzenle({Not? mevcutNot}) async {
    final bController = TextEditingController(text: mevcutNot?.baslik ?? '');
    final iController = TextEditingController(text: mevcutNot?.icerik ?? '');
    final eController = TextEditingController();
    final notId = mevcutNot?.id ?? _firestore.collection('notlar').doc().id;

    int seciliRenkIndex = mevcutNot != null
        ? kartRenkleri.indexOf(mevcutNot.renk).clamp(0, kartRenkleri.length - 1)
        : 0;
    bool onizlemeAcik = false;
    bool isListening = false;
    List<Map<String, dynamic>> yerelGorselVerileri = List.from(mevcutNot?.gorselVerileri ?? []);
    List<String> seciliEtiketler = List.from(mevcutNot?.etiketler ?? []);

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.95,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              left: 24, right: 24, top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(mevcutNot == null ? '✏️ Yeni Not' : '📝 Düzenle',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Row(children: [
                      Container(
                        decoration: BoxDecoration(color: isListening ? Colors.red.withOpacity(0.1) : Colors.transparent, shape: BoxShape.circle),
                        child: IconButton(
                          icon: Icon(isListening ? Icons.mic : Icons.mic_none,
                              color: isListening ? Colors.red : const Color(0xFF6C63FF)),
                          onPressed: () async {
                            if (!isListening) {
                              bool available = await _speech.initialize();
                              if (available) {
                                String oncekiMetin = iController.text;
                                setModalState(() => isListening = true);
                                _speech.listen(
                                  localeId: 'tr_TR',
                                  onResult: (val) => setModalState(() =>
                                      iController.text = oncekiMetin + (oncekiMetin.isEmpty ? '' : ' ') + val.recognizedWords),
                                );
                              }
                            } else {
                              setModalState(() => isListening = false);
                              _speech.stop();
                            }
                          },
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setModalState(() => onizlemeAcik = !onizlemeAcik),
                        icon: Icon(onizlemeAcik ? Icons.edit : Icons.preview, size: 18),
                        label: Text(onizlemeAcik ? 'Düzenle' : 'Önizle', style: const TextStyle(fontSize: 13)),
                      ),
                    ]),
                  ],
                ),
                const SizedBox(height: 10),

                const Text('Görsel Panosu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                const SizedBox(height: 6),
                Container(
                  height: 160, width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.withOpacity(0.2)),
                  ),
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      if (yerelGorselVerileri.isEmpty)
                        const Center(child: Text('Aşağıdan fotoğraf ekle ve sürükle', style: TextStyle(color: Colors.grey, fontSize: 12))),
                      ...yerelGorselVerileri.asMap().entries.map((entry) {
                        int index = entry.key;
                        Map<String, dynamic> gorsel = entry.value;
                        return Positioned(
                          left: (gorsel['x'] as num).toDouble(),
                          top: (gorsel['y'] as num).toDouble(),
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setModalState(() {
                                gorsel['x'] = (gorsel['x'] as num).toDouble() + details.delta.dx;
                                gorsel['y'] = (gorsel['y'] as num).toDouble() + details.delta.dy;
                              });
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 5)],
                                    image: DecorationImage(image: NetworkImage(gorsel['url']), fit: BoxFit.cover),
                                  ),
                                ),
                                Positioned(
                                  top: -8, right: -8,
                                  child: GestureDetector(
                                    onTap: () => setModalState(() => yerelGorselVerileri.removeAt(index)),
                                    child: Container(decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle), child: const Icon(Icons.close, color: Colors.white, size: 16)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  TextButton.icon(
                    onPressed: () async {
                      final secilen = await _picker.pickImage(source: ImageSource.gallery);
                      if (secilen != null) {
                        if (context.mounted) showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
                        final url = await _tekGorselYukle(secilen, notId);
                        if (context.mounted) Navigator.pop(context);
                        setModalState(() => yerelGorselVerileri.add({'url': url, 'x': 20.0, 'y': 20.0}));
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate, size: 16), label: const Text('Galeri', style: TextStyle(fontSize: 13)),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final secilen = await _picker.pickImage(source: ImageSource.camera);
                      if (secilen != null) {
                        if (context.mounted) showDialog(context: context, barrierDismissible: false, builder: (ctx) => const Center(child: CircularProgressIndicator()));
                        final url = await _tekGorselYukle(secilen, notId);
                        if (context.mounted) Navigator.pop(context);
                        setModalState(() => yerelGorselVerileri.add({'url': url, 'x': 20.0, 'y': 20.0}));
                      }
                    },
                    icon: const Icon(Icons.camera_alt, size: 16), label: const Text('Kamera', style: TextStyle(fontSize: 13)),
                  ),
                ]),

                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: eController,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Etiket ekle...', hintStyle: const TextStyle(fontSize: 13),
                        filled: true, fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFF6C63FF), size: 26),
                    onPressed: () {
                      if (eController.text.trim().isNotEmpty && !seciliEtiketler.contains(eController.text.trim())) {
                        setModalState(() => seciliEtiketler.add(eController.text.trim()));
                        eController.clear();
                      }
                    },
                  ),
                ]),
                if (seciliEtiketler.isNotEmpty)
                  Wrap(spacing: 6, children: seciliEtiketler.map((e) => Chip(
                    label: Text(e, style: const TextStyle(fontSize: 11)),
                    onDeleted: () => setModalState(() => seciliEtiketler.remove(e)),
                    backgroundColor: kartRenkleri[seciliRenkIndex].withOpacity(0.2),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )).toList()),

                const SizedBox(height: 8),
                TextField(
                  controller: bController,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: 'Başlık...', filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),

                if (!onizlemeAcik) ...[
                  TextField(
                    controller: iController,
                    maxLines: 5,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'İçerik...', filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    _mdButon('**B**', '**kalın**', iController),
                    _mdButon('*I*', '*italik*', iController),
                    _mdButon('# H', '# Başlık\n', iController),
                    _mdButon('- L', '- liste\n', iController),
                    _mdButon('`K`', '`kod`', iController),
                  ]),
                ] else ...[
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 120),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
                    child: MarkdownBody(data: iController.text.isEmpty ? '*İçerik yok*' : iController.text),
                  ),
                ],
                const SizedBox(height: 10),

                Row(children: List.generate(kartRenkleri.length, (i) => GestureDetector(
                  onTap: () => setModalState(() => seciliRenkIndex = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 10),
                    width: seciliRenkIndex == i ? 34 : 28,
                    height: seciliRenkIndex == i ? 34 : 28,
                    decoration: BoxDecoration(
                      color: kartRenkleri[i], shape: BoxShape.circle,
                      border: seciliRenkIndex == i ? Border.all(color: Colors.white, width: 3) : null,
                    ),
                  ),
                ))),
                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kartRenkleri[seciliRenkIndex], foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () async {
                      if (bController.text.isEmpty) return;
                      final n = Not(
                        id: notId, baslik: bController.text, icerik: iController.text,
                        tarih: mevcutNot?.tarih ?? DateTime.now(),
                        renk: kartRenkleri[seciliRenkIndex],
                        gorselVerileri: yerelGorselVerileri, etiketler: seciliEtiketler,
                      );
                      if (mevcutNot == null) {
                        await _firestore.collection('notlar').doc(notId).set(n.toFirestore());
                        _xpEkle(20);
                      } else {
                        await _firestore.collection('notlar').doc(notId).update(n.toFirestore());
                        _xpEkle(5);
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text(mevcutNot == null ? 'Kaydet' : 'Güncelle',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120,
            floating: true, pinned: true,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
            flexibleSpace: FlexibleSpaceBar(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_secimModu ? '${_seciliNotlar.length} seçildi' : 'Notlarım',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
                  if (!_secimModu) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(10)),
                      child: Text('⭐ $_kullaniciXP XP',
                          style: TextStyle(fontSize: 11, color: Colors.amber.shade900, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
            ),
            actions: [
              if (_secimModu) ...[
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _seciliNotlar.isEmpty ? null : () async {
                    final onay = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Toplu Sil'),
                        content: Text('${_seciliNotlar.length} notu silmek istediğine emin misin?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('İptal')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sil', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                    if (onay == true) await _seciliNotlariSil();
                  },
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _secimModu = false; _seciliNotlar.clear(); })),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  tooltip: 'Çıkış yap',
                ),
              ],
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(90),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    onChanged: (m) { aramaMetni = m; _filtrele(); },
                    decoration: InputDecoration(
                      hintText: 'Notlarda ara...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: const Text('Tümü'), selected: _seciliFiltre == 'Tümü',
                            onSelected: (s) { if (s) setState(() { _seciliFiltre = 'Tümü'; _filtrele(); }); }),
                      ),
                      ...dinamikEtiketler.map((e) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(label: Text(e), selected: _seciliFiltre == e,
                            onSelected: (s) { if (s) setState(() { _seciliFiltre = e; _filtrele(); }); }),
                      )),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          _yukleniyor
              ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              : filtrelenmisNotlar.isEmpty
                  ? SliverFillRemaining(
                      child: Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(aramaMetni.isEmpty ? Icons.note_alt_outlined : Icons.search_off,
                              size: 70, color: Colors.grey.withOpacity(0.4)),
                          const SizedBox(height: 12),
                          Text(aramaMetni.isEmpty ? 'Henüz not yok' : '"$aramaMetni" bulunamadı',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.grey.withOpacity(0.7))),
                          const SizedBox(height: 8),
                          Text(aramaMetni.isEmpty ? '+ Yeni Not butonuna bas' : 'Farklı bir kelime dene',
                              style: TextStyle(fontSize: 14, color: Colors.grey.withOpacity(0.5))),
                        ],
                      )),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final not = filtrelenmisNotlar[index];
                            final secili = _seciliNotlar.contains(not.id);
                            return GestureDetector(
                              onTap: () {
                                if (_secimModu) {
                                  setState(() { secili ? _seciliNotlar.remove(not.id) : _seciliNotlar.add(not.id!); });
                                } else {
                                  _notEkleVeyaDuzenle(mevcutNot: not);
                                }
                              },
                              onLongPress: () { if (!_secimModu) setState(() { _secimModu = true; _seciliNotlar.add(not.id!); }); },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: secili ? not.renk.withOpacity(0.35) : not.renk.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: secili ? not.renk : not.renk.withOpacity(0.3), width: secili ? 2.5 : 1.5),
                                ),
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (not.etiketler.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        margin: const EdgeInsets.only(bottom: 6),
                                        decoration: BoxDecoration(color: not.renk.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                        child: Text(not.etiketler.first, style: TextStyle(fontSize: 10, color: not.renk, fontWeight: FontWeight.bold)),
                                      ),
                                    Row(children: [
                                      Expanded(child: Text(not.baslik,
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: not.renk.withOpacity(0.9)),
                                          maxLines: 2, overflow: TextOverflow.ellipsis)),
                                      if (secili) Icon(Icons.check_circle, color: not.renk, size: 18),
                                    ]),
                                    const SizedBox(height: 6),
                                    if (not.gorselVerileri.isNotEmpty) ...[
                                      ClipRRect(borderRadius: BorderRadius.circular(8),
                                          child: Image.network(not.gorselVerileri.first['url'], height: 55, width: double.infinity, fit: BoxFit.cover)),
                                      const SizedBox(height: 6),
                                    ],
                                    Expanded(child: MarkdownBody(
                                      data: not.icerik,
                                      styleSheet: MarkdownStyleSheet(p: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
                                    )),
                                    const SizedBox(height: 6),
                                    Text(_tarihFormat(not.tarih),
                                        style: TextStyle(fontSize: 10, color: not.renk.withOpacity(0.7), fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: filtrelenmisNotlar.length,
                        ),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.65,
                        ),
                      ),
                    ),
        ],
      ),
      floatingActionButton: _secimModu ? null : FloatingActionButton.extended(
        onPressed: () => _notEkleVeyaDuzenle(),
        icon: const Icon(Icons.add),
        label: const Text('Yeni Not'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
    );
  }
}