import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

void main() => runApp(const GastosKoApp());

class GastosKoApp extends StatelessWidget {
  const GastosKoApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark()
            .copyWith(scaffoldBackgroundColor: const Color(0xFF121212)),
        home: const SplashScreen());
  }
}

class CommaFormatter extends TextInputFormatter {
  final NumberFormat _fmt = NumberFormat('#,##0');
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String clean = newValue.text
        .replaceAll(',', '')
        .replaceAll('₱', '')
        .replaceAll(' ', '')
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) return const TextEditingValue(text: '');
    int val = int.tryParse(clean) ?? 0;
    return TextEditingValue(
        text: _fmt.format(val),
        selection: TextSelection.collapsed(offset: _fmt.format(val).length));
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashState();
}

class _SplashState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale, _glow;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.15)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _glow = Tween<double>(begin: 25, end: 70)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    await Future.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('user_pincode');

    // Diretso na sa PIN verification nang walang 30-day block layer
    if (savedPin == null || savedPin.isEmpty) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const RegistrationScreen()));
    } else {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) =>
                  const PinCodeScreen(isRegistration: false)));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) =>
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Transform.scale(
              scale: _scale.value,
              child: Container(
                decoration: BoxDecoration(boxShadow: [
                  BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.8),
                      blurRadius: _glow.value,
                      spreadRadius: 5),
                  BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                      blurRadius: _glow.value * 1.8,
                      spreadRadius: 15)
                ]),
                child: Image.asset('assets/icon.png', width: 130, height: 130),
              ),
            ),
            const SizedBox(height: 30),
            const Text('GASTOS KO',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 26,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('by RAS Mobilelabs',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    letterSpacing: 0.5)),
          ]),
        ),
      ),
    );
  }
}

class RegistrationScreen extends StatelessWidget {
  const RegistrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PinCodeScreen(isRegistration: true);
  }
}

class PinCodeScreen extends StatefulWidget {
  final bool isRegistration;
  const PinCodeScreen({super.key, required this.isRegistration});

  @override
  State<PinCodeScreen> createState() => _PinCodeScreenState();
}

class _PinCodeScreenState extends State<PinCodeScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _answerController = TextEditingController();
  String _savedPin = "";
  String _titleText = "";
  String _errorText = "";
  bool _isRecovering = false;
  bool _forceNewPin = false;
  bool _isUpdatingPin = false;

  int _failedAttempts = 0;
  final int _maxAttempts = 3;

  @override
  void initState() {
    super.initState();
    _titleText = widget.isRegistration
        ? "MAG-SET NG IYONG PINCODE"
        : "I-ENTER ANG IYONG PINCODE";
    if (!widget.isRegistration) {
      _loadSavedPin();
    }
  }

  Future<void> _loadSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedPin = prefs.getString('user_pincode') ?? "";
    });
  }

  Future<void> _handlePinSubmit(String pin) async {
    if (pin.length < 4) {
      setState(() {
        _errorText = "Dapat ay may 4-digits ang PIN code.";
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    if (_isUpdatingPin) {
      await prefs.setString('user_pincode', pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Matagumpay na na-update ang iyong PIN!')),
        );
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (context) => const HomeScreen()));
      }
    } else if (widget.isRegistration || _forceNewPin) {
      _showSecurityQuestionSetupDialog(pin);
    } else {
      if (pin == _savedPin) {
        setState(() {
          _failedAttempts = 0;
        });
        if (mounted) {
          Navigator.pushReplacement(context,
              MaterialPageRoute(builder: (context) => const HomeScreen()));
        }
      } else {
        setState(() {
          _failedAttempts++;
          _pinController.clear();
          if (_failedAttempts >= _maxAttempts) {
            _isRecovering = true;
            _errorText =
                "🔒 Naubos na ang attempts mo! Heto ang recovery layer.";
          } else {
            int natitira = _maxAttempts - _failedAttempts;
            _errorText =
                "Maling PIN Code! ($natitira/$_maxAttempts attempts left)";
          }
        });
      }
    }
  }

  void _showSecurityQuestionSetupDialog(String targetPin) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('🔒 SECURITY QUESTION',
            style: TextStyle(
                fontSize: 16,
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Ano ang pangalan ng iyong unang naging Alagang Hayop (Pet)?',
                style: TextStyle(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: _answerController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  hintText: 'Sagot mo dito...',
                  hintStyle: TextStyle(color: Colors.white30)),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (_answerController.text.trim().isNotEmpty) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('user_pincode', targetPin);
                await prefs.setString('security_answer',
                    _answerController.text.trim().toLowerCase());
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text(
                            'Matagumpay na nai-set ang iyong PIN at Security Recovery!')),
                  );
                  Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const HomeScreen()));
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black),
            child: const Text('I-SAVE',
                style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Future _handleRecoverySubmit() async {
    final prefs = await SharedPreferences.getInstance();
    String savedAnswer = prefs.getString('security_answer') ?? "";
    String inputAnswer = _answerController.text.trim().toLowerCase();
    if (inputAnswer == savedAnswer && savedAnswer.isNotEmpty) {
      setState(() {
        _isRecovering = false;
        _isUpdatingPin = true;
        _titleText = "MAG-SET NG BAGONG PINCODE";
        _errorText = "";
        _pinController.clear();
        _answerController.clear();
      });
      await prefs.remove('user_pincode');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Tama ang sagot mo! Mag-set ka na ng bagong PIN.'),
              backgroundColor: Colors.green),
        );
      }
    } else {
      setState(() {
        _errorText = "Maling sagot! Isiping mabuti.";
        _answerController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isRecovering
                      ? Icons.help_outline_rounded
                      : ((widget.isRegistration ||
                              _forceNewPin ||
                              _isUpdatingPin)
                          ? Icons.lock_open_rounded
                          : Icons.lock_outline_rounded),
                  size: 80,
                  color: const Color(0xFFFFD700),
                ),
                const SizedBox(height: 24),
                Text(
                  _isRecovering ? "PIN CODE RECOVERY" : _titleText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  _isRecovering
                      ? "Sagutin ang tanong sa ibaba:\nAno ang pangalan ng iyong unang naging Alagang Hayop (Pet)?"
                      : ((widget.isRegistration ||
                              _forceNewPin ||
                              _isUpdatingPin)
                          ? "Gagamitin mo ang PIN na ito tuwing bubuksan ang app para sa iyong seguridad."
                          : "Ipasok ang iyong 4-digit code para mag-unlock."),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.white54),
                ),
                const SizedBox(height: 32),
                if (!_isRecovering)
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      textAlign: TextAlign.center,
                      maxLength: 4,
                      style: const TextStyle(
                          fontSize: 28,
                          letterSpacing: 20,
                          color: Color(0xFFFFD700)),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        counterText: "",
                        enabledBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Colors.white30, width: 2)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Color(0xFFFFD700), width: 2)),
                      ),
                      onChanged: (val) {
                        if (val.length == 4) {
                          _handlePinSubmit(val);
                        }
                      },
                    ),
                  )
                else
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _answerController,
                      textCapitalization: TextCapitalization.words,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: "I-type ang iyong sagot...",
                        hintStyle:
                            TextStyle(color: Colors.white24, fontSize: 14),
                        enabledBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Colors.white30, width: 2)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Color(0xFFFFD700), width: 2)),
                      ),
                    ),
                  ),
                if (_errorText.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ],
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () => _isRecovering
                      ? _handleRecoverySubmit()
                      : _handlePinSubmit(_pinController.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text(
                    _isRecovering
                        ? 'I-VERIFY SAGOT'
                        : ((widget.isRegistration ||
                                _forceNewPin ||
                                _isUpdatingPin)
                            ? 'I-CONFIRM & SAVE'
                            : 'I-UNLOCK'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (!widget.isRegistration &&
                    !_isRecovering &&
                    !_forceNewPin &&
                    !_isUpdatingPin) ...[
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isRecovering = true;
                        _errorText = "";
                      });
                    },
                    child: const Text(
                      'Nakalimutan ang PIN Code?',
                      style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 13,
                          decoration: TextDecoration.underline),
                    ),
                  )
                ] else if (_isRecovering && _failedAttempts < _maxAttempts) ...[
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isRecovering = false;
                        _errorText = "";
                      });
                    },
                    child: const Text(
                      'Bumalik sa Lock Screen',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                ]
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Expense {
  String id;
  String title;
  double amount;
  DateTime date;
  Color color;
  Expense(
      {required this.id,
      required this.title,
      required this.amount,
      required this.date,
      required this.color});
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'date': date.toIso8601String(),
        'color': color.toARGB32()
      };
  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
      id: j['id'],
      title: j['title'],
      amount: (j['amount'] as num).toDouble(),
      date: DateTime.parse(j['date']),
      color: Color(j['color']));
}

class AppWallet {
  String id;
  String name;
  double budget;
  AppWallet({required this.id, required this.name, required this.budget});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'budget': budget};
  factory AppWallet.fromJson(Map<String, dynamic> j) => AppWallet(
      id: j['id'], name: j['name'], budget: (j['budget'] as num).toDouble());
}

class GroupedExpense {
  String title;
  double total;
  Color color;
  int count;
  GroupedExpense(
      {required this.title,
      required this.total,
      required this.color,
      required this.count});
}

class PiePainter extends CustomPainter {
  final List data;
  final double total;
  final int? selectedIndex;
  PiePainter({required this.data, required this.total, this.selectedIndex});
  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || data.isEmpty) return;
    double start = -math.pi / 2;
    final center = Offset(size.width / 2, size.height / 2);
    double radius = math.min(size.width, size.height) / 2;
    for (int i = 0; i < data.length; i++) {
      var g = data[i];
      double sweep = (g.total / total) * 2 * math.pi;
      bool sel = i == selectedIndex;
      Offset off = Offset.zero;
      if (sel) {
        double mid = start + sweep / 2;
        off = Offset(math.cos(mid) * 15, math.sin(mid) * 15);
      }
      final paint = Paint()
        ..color = sel ? g.color : g.color.withValues(alpha: 0.70)
        ..style = PaintingStyle.fill;
      canvas.drawArc(
          Rect.fromCircle(center: center + off, radius: radius + (sel ? 8 : 0)),
          start,
          sweep,
          true,
          paint);
      start += sweep;
    }
    canvas.drawCircle(
        center, radius * 0.55, Paint()..color = const Color(0xFF1E1E1E));
  }

  @override
  bool shouldRepaint(covariant PiePainter o) =>
      o.selectedIndex != selectedIndex || o.data != data;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State createState() => HomeScreenState();
}

class HomeScreenState extends State with WidgetsBindingObserver {
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription? _subscription;
  List _products = [];
  bool _isPremiumUser = false;
  List wallets = [];
  String activeWalletId = "default";
  double budget = 0;
  List all = [];
  String searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  int? selectedIndex;
  final NumberFormat commaFormat = NumberFormat('#,##0');
  String fmt(num n) => commaFormat.format(n.toInt());
  String peso(num n) => '₱${fmt(n)}';
  final List dynamicColors = [
    const Color(0xFF00E676),
    const Color(0xFF00BFA5),
    const Color(0xFF29B6F6),
    const Color(0xFFFF9800),
    const Color(0xFFAB47BC),
    const Color(0xFF26A69A),
  ];
  Map<String, Color> colorMap = {};
  Timer? _bgSessionTimer;
  final Duration _sessionTimeoutDuration = const Duration(minutes: 5);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadData();
    _checkPremiumState();
    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((Duration timestamp) {
        _initializeBilling();
      });
    } else {
      setState(() {
        _isPremiumUser = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _bgSessionTimer?.cancel();
      _bgSessionTimer = Timer(_sessionTimeoutDuration, () {
        _lockAppSession();
      });
    } else if (state == AppLifecycleState.resumed) {
      _bgSessionTimer?.cancel();
    }
  }

  void _lockAppSession() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
          builder: (context) => const PinCodeScreen(isRegistration: false)),
      (route) => false,
    );
  }

  void _initializeBilling() {
    if (kIsWeb) return;
    final Stream purchaseUpdated = _inAppPurchase.purchaseStream;
    _subscription = purchaseUpdated.listen((purchaseDetailsList) {
      _listenToPurchaseUpdated(purchaseDetailsList);
    }, onDone: () {
      _subscription?.cancel();
    }, onError: (error) {
      debugPrint("Billing engine bridge error: $error");
    });
    _loadProductsFromGoogleConsole();
  }

  Future _loadProductsFromGoogleConsole() async {
    if (kIsWeb) return;
    final bool isAvailable = await _inAppPurchase.isAvailable();
    if (!isAvailable) return;
    final Set kIds = {
      'gastos_ko_monthly',
      'gastos_ko_semiannual',
      'gastos_ko_annual',
    };
    final ProductDetailsResponse response =
        await _inAppPurchase.queryProductDetails(kIds.cast());
    if (response.notFoundIDs.isEmpty) {
      setState(() {
        _products = response.productDetails;
      });
    }
  }

  Future _exportWalletToCSV() async {
    if (all.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Walang mga gastos na maie-export!')),
      );
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Ang file sharing sheet ay gumagana lang kapag naka-install na sa totoong CP!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    try {
      String activeWalletName = "Main Wallet";
      double activeWalletBudget = budget;
      for (var w in wallets) {
        if (w.id == activeWalletId) {
          activeWalletName = w.name;
          activeWalletBudget = w.budget;
          break;
        }
      }
      List<List> csvRows = [
        [
          'Wallet Name',
          'Current Budget (₱)',
          'Expense ID',
          'Kategorya / Pamagat',
          'Halaga (₱)',
          'Petsa at Oras'
        ]
      ];
      for (var expense in all) {
        csvRows.add([
          activeWalletName,
          activeWalletBudget,
          expense.id,
          expense.title,
          expense.amount,
          DateFormat('yyyy-MM-dd hh:mm a').format(expense.date),
        ]);
      }
      String csvData = '\uFEFF' + const ListToCsvConverter().convert(csvRows);
      final directory = await getTemporaryDirectory();
      String cleanFileName =
          activeWalletName.replaceAll(RegExp(r'[^\w\s]+'), '');
      final String filePath =
          '${directory.path}/GastosKo${cleanFileName}_Export.csv';
      final File file = File(filePath);
      await file.writeAsString(csvData, encoding: utf8);
      final XFile xFile = XFile(filePath);
      await Share.shareXFiles([xFile],
          text: 'Narito ang aking export file galing sa Gastos Ko App!');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('May error sa pag-export: $e')),
        );
      }
    }
  }

  void _listenToPurchaseUpdated(List purchaseDetailsList) {
    for (final purchaseDetails in purchaseDetailsList) {
      if (purchaseDetails.status == PurchaseStatus.pending) {
      } else {
        if (purchaseDetails.status == PurchaseStatus.error) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('May error sa transaksyon. Subukan muli.')),
          );
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          _markAsPremiumUser();
        }
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future _markAsPremiumUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium_user', true);
    setState(() {
      _isPremiumUser = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Salamat! Matagumpay ang iyong PRO Activation! 🎉')),
    );
  }

  void _buyPlan(String productId) {
    if (_products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Hindi pa handa ang produkto mula sa Google Store.')),
      );
      return;
    }
    ProductDetails product = _products.firstWhere(
      (element) => element.id == productId,
      orElse: () => _products.first,
    );
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bgSessionTimer?.cancel();
    _subscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future _checkPremiumState() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _isPremiumUser = kIsWeb ? false : (p.getBool('is_premium_user') ?? false);
    });
  }

  Future loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      String? wData = p.getString('app_wallets');
      if (wData != null) {
        List l = jsonDecode(wData);
        wallets = l.map((e) => AppWallet.fromJson(e)).toList();
      } else {
        wallets = [AppWallet(id: "default", name: "Main Wallet", budget: 0.0)];
      }
      activeWalletId = p.getString('active_wallet_id') ?? "default";
      AppWallet? selectedWallet;
      for (var w in wallets) {
        if (w.id == activeWalletId) {
          selectedWallet = w;
          break;
        }
      }
      AppWallet activeWallet = selectedWallet ??
          (wallets.isNotEmpty
              ? wallets.first
              : AppWallet(id: "default", name: "Main Wallet", budget: 0.0));
      activeWalletId = activeWallet.id;
      budget = activeWallet.budget;
      String? d = p.getString('expenses_$activeWalletId');
      if (d != null) {
        List l = jsonDecode(d);
        all = l.map((e) => Expense.fromJson(e)).toList();
        colorMap.clear();
      } else {
        all.clear();
        colorMap.clear();
      }
    });
  }

  Future saveData() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'app_wallets', jsonEncode(wallets.map((w) => w.toJson()).toList()));
    await p.setString('active_wallet_id', activeWalletId);
    await p.setString('expenses_$activeWalletId',
        jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  void _switchWallet(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('active_wallet_id', id);
    setState(() {
      activeWalletId = id;
      selectedIndex = null;
      searchQuery = "";
      _searchController.clear();
    });
    loadData();
  }

  void _showCongratulationsDialog(String name, double budgetAmt) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                color: Color(0xFF00E676), size: 60),
            const SizedBox(height: 16),
            const Text(
              'CONGRATULATIONS!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontStyle: FontStyle.normal,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Ang iyong bagong wallet "$name" ay nagawa na at may budget na ${peso(budgetAmt)}.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('OKAY',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  Future _launchComplianceUrl(String urlString) async {
    final Uri url = Uri.parse('https://$urlString');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.platformDefault);
    }
  }

  String _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  Future _sendSupportEmail(String subjectText) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'rasmobilelabs.support@gmail.com',
      query: _encodeQueryParameters(<String, String>{
        'subject': subjectText,
      }),
    );
    try {
      bool launched = await launchUrl(
        emailUri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Walang nahanap na email app o hindi mabuksan.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('May error sa pagbubukas ng email app: $e')),
        );
      }
    }
  }

  Future clearAllApplicationData() async {
    final p = await SharedPreferences.getInstance();
    await p.clear();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SplashScreen()),
        (route) => false,
      );
    }
  }

  void _showEditWalletBudgetDialog(
      AppWallet wallet, StateSetter setModalState) {
    final budgetCtrl = TextEditingController(text: fmt(wallet.budget));
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('I-edit Budget: ${wallet.name}'),
        content: TextField(
          controller: budgetCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            CommaFormatter()
          ],
          decoration: const InputDecoration(
              prefixText: '₱ ', labelText: 'Bagong Budget Amount'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I-KANSELA',
                style: TextStyle(color: Colors.white30)),
          ),
          TextButton(
            onPressed: () {
              if (budgetCtrl.text.isNotEmpty) {
                double newBudget =
                    double.tryParse(budgetCtrl.text.replaceAll(',', '')) ??
                        wallet.budget;
                setState(() {
                  wallet.budget = newBudget;
                  if (wallet.id == activeWalletId) {
                    budget = newBudget;
                  }
                  saveData();
                });
                setModalState(() {});
                Navigator.pop(context);
              }
            },
            child: const Text('I-SAVE',
                style: TextStyle(
                    color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showDeleteWalletConfirmDialog(
      AppWallet wallet, StateSetter setModalState) {
    if (wallet.id == "default") {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Hindi pwedeng burahin ang Main Wallet!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Burahin ang Wallet?',
            style: TextStyle(color: Colors.redAccent)),
        content: Text(
            'Sigurado ka ba? Permanenteng mawawala ang wallet na "${wallet.name}" pati ang LAHAT ng history ng expenses nito sa database!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I-KANSELA',
                style: TextStyle(color: Colors.white30)),
          ),
          TextButton(
            onPressed: () async {
              final p = await SharedPreferences.getInstance();
              await p.remove('expenses${wallet.id}');
              setState(() {
                wallets.removeWhere((w) => w.id == wallet.id);
                if (activeWalletId == wallet.id) {
                  if (wallets.isNotEmpty) {
                    activeWalletId = wallets.first.id;
                  } else {
                    wallets = [
                      AppWallet(id: "default", name: "Main Wallet", budget: 0.0)
                    ];
                    activeWalletId = "default";
                  }
                }
                saveData();
              });
              loadData();
              setModalState(() {});
              Navigator.pop(context);
            },
            child: const Text('I-DELETE',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showWalletManagerDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet, color: Color(0xFFFFD700)),
                  SExpandingLabel(width: 8),
                  Text('WALLET MANAGER', style: TextStyle(fontSize: 16)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: wallets.isEmpty
                      ? const Center(child: Text('Walang nahanap na wallet.'))
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: wallets.length,
                          itemBuilder: (context, idx) {
                            final w = wallets[idx];
                            final isSelected = w.id == activeWalletId;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 0),
                              leading: Icon(Icons.wallet,
                                  color: isSelected
                                      ? const Color(0xFFFFD700)
                                      : Colors.white30),
                              title: Text(w.name,
                                  style: TextStyle(
                                      color: isSelected
                                          ? const Color(0xFFFFD700)
                                          : Colors.white,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal)),
                              subtitle: Text('Budget: ${peso(w.budget)}',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit,
                                        color: Colors.white38, size: 18),
                                    tooltip: 'Edit Budget',
                                    onPressed: () =>
                                        _showEditWalletBudgetDialog(
                                            w, setModalState),
                                  ),
                                  if (w.id != "default")
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.redAccent, size: 18),
                                      tooltip: 'Delete Wallet',
                                      onPressed: () =>
                                          _showDeleteWalletConfirmDialog(
                                              w, setModalState),
                                    ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle,
                                        color: Color(0xFF00E676), size: 18),
                                ],
                              ),
                              onTap: () {
                                setModalState(() {
                                  activeWalletId = w.id;
                                });
                                Navigator.pop(context);
                                _switchWallet(w.id);
                              },
                            );
                          },
                        ),
                ),
                const Divider(color: Colors.white10),
                ButtonTheme(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddWalletDialog();
                    },
                    icon: const Icon(Icons.add_card, size: 18),
                    label: const Text('MAGDAGDAG'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFFFD700).withValues(alpha: 0.15),
                      foregroundColor: const Color(0xFFFFD700),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddWalletDialog() {
    final nameCtrl = TextEditingController();
    final budgetCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Gumawa ng Bagong Wallet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Pangalan ng Wallet (e.g. Sweldo)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: budgetCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CommaFormatter()
              ],
              decoration: const InputDecoration(
                  prefixText: '₱ ', labelText: 'Magkano ang Budget?'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I-KANSELA',
                  style: TextStyle(color: Colors.white30))),
          TextButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && budgetCtrl.text.isNotEmpty) {
                String wName = nameCtrl.text.trim();
                double wBudget =
                    double.tryParse(budgetCtrl.text.replaceAll(',', '')) ?? 0;
                String wId = DateTime.now().millisecondsSinceEpoch.toString();
                setState(() {
                  final newWallet =
                      AppWallet(id: wId, name: wName, budget: wBudget);
                  wallets.add(newWallet);
                  activeWalletId = wId;
                  budget = wBudget;
                  all.clear();
                  saveData();
                });
                Navigator.pop(context);
                Future.delayed(const Duration(milliseconds: 150), () {
                  _showCongratulationsDialog(wName, wBudget);
                });
              }
            },
            child: const Text('I-SAVE',
                style: TextStyle(
                    color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showNearLimitBudgetDialog(double currentTotal, double newAmount) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF2C221A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.orangeAccent, width: 1.5)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.orangeAccent, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'MALAPIT NA MAUBOS!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Babala! nasa mahigit 90% na ang iyong nagagastos!\n\n'
          'Idaragdag na Halaga: ${peso(newAmount)}\n\n'
          'Ang iyong Maximum Budget lamang ay ${peso(budget)}.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('KAYANG-KAYA PA',
                style: TextStyle(
                    color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showOverbudgetDialog(double currentTotal, double newAmount) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF2C1A1A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.redAccent, width: 1.5)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'OVERBUDGET WARNING!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'Sobra na sa budget ag iyong ginastos.\n\n'
          'Idaragdag na Halaga: ${peso(newAmount)}\n\n'
          'Ang iyong Maximum Budget lamang ay ${peso(budget)}.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Okay',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _checkBudgetBeforeAdding() {
    if (budget <= 0) {
      showDialog(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          actionsAlignment: MainAxisAlignment.end,
          title: const Text(
            'Mag-add ka muna ng budget!',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I-KANSELA',
                  style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                AppWallet? currentWallet;
                for (var w in wallets) {
                  if (w.id == activeWalletId) {
                    currentWallet = w;
                    break;
                  }
                }
                if (currentWallet != null) {
                  _showEditWalletBudgetDialog(currentWallet, (fn) {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
              ),
              child: const Text('I-SET BUDGET',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      _showCounselingAddExpenseDialog();
    }
  }

  void _showCounselingAddExpenseDialog() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Magdagdag ng Gastos'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(labelText: 'Kategorya (e.g. Pagkain)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CommaFormatter()
              ],
              decoration: const InputDecoration(
                  prefixText: '₱ ', labelText: 'Magkano / Halaga'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I-KANSELA',
                  style: TextStyle(color: Colors.white30))),
          TextButton(
            onPressed: () {
              if (titleCtrl.text.isNotEmpty && amountCtrl.text.isNotEmpty) {
                String key = titleCtrl.text.toLowerCase().trim();
                double amt =
                    double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
                double kasalukuyangTotal =
                    all.fold(0, (sum, item) => sum + item.amount);
                double bagongTotal = kasalukuyangTotal + amt;
                bool isOver100 = bagongTotal > budget;
                bool isOver90 =
                    (bagongTotal >= (budget * 0.9)) && (bagongTotal <= budget);
                Color itemColor = colorMap[key] ??
                    dynamicColors[colorMap.length % dynamicColors.length];
                setState(() {
                  final newExpense = Expense(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: titleCtrl.text.trim(),
                    amount: amt,
                    date: DateTime.now(),
                    color: itemColor,
                  );
                  all.add(newExpense);
                  saveData();
                });
                Navigator.pop(context);
                if (isOver100) {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _showOverbudgetDialog(kasalukuyangTotal, amt);
                  });
                } else if (isOver90) {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _showNearLimitBudgetDialog(kasalukuyangTotal, amt);
                  });
                }
              } else {
                Navigator.pop(context);
              }
            },
            child: const Text('I-ADD GASTOS',
                style: TextStyle(color: Color(0xFFFFD700))),
          )
        ],
      ),
    );
  }

  void _showEditExpenseDialog(Expense item) {
    final titleCtrl = TextEditingController(text: item.title);
    final amountCtrl = TextEditingController(text: fmt(item.amount));
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.edit, color: Color(0xFFFFD700)),
            SizedBox(width: 8),
            Text('I-edit ang Entry'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              textCapitalization: TextCapitalization.words,
              decoration:
                  const InputDecoration(labelText: 'Kategorya (e.g. Pagkain)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CommaFormatter()
              ],
              decoration: const InputDecoration(
                  prefixText: '₱ ', labelText: 'Magkano / Halaga'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I-KANSELA',
                  style: TextStyle(color: Colors.white30))),
          TextButton(
            onPressed: () {
              if (titleCtrl.text.isNotEmpty && amountCtrl.text.isNotEmpty) {
                String newKey = titleCtrl.text.toLowerCase().trim();
                double newAmt =
                    double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
                double kasalukuyangTotalIwan = all
                    .where((e) => e.id != item.id)
                    .fold(0, (sum, item) => sum + item.amount);
                double bagongTotalIwan = kasalukuyangTotalIwan + newAmt;
                bool isOver100 = bagongTotalIwan > budget;
                bool isOver90 = (bagongTotalIwan >= (budget * 0.9)) &&
                    (bagongTotalIwan <= budget);
                Color updatedColor = colorMap[newKey] ?? item.color;
                setState(() {
                  item.title = titleCtrl.text.trim();
                  item.amount = newAmt;
                  item.color = updatedColor;
                  saveData();
                });
                Navigator.pop(context);
                if (isOver100) {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _showOverbudgetDialog(kasalukuyangTotalIwan, newAmt);
                  });
                } else if (isOver90) {
                  Future.delayed(const Duration(milliseconds: 100), () {
                    _showNearLimitBudgetDialog(kasalukuyangTotalIwan, newAmt);
                  });
                }
              } else {
                Navigator.pop(context);
              }
            },
            child: const Text('I-UPDATE',
                style: TextStyle(
                    color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showUpgradeOptionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_rounded,
                          color: Color(0xFFFFD700), size: 26),
                      SizedBox(width: 8),
                      Text(
                        'PUMILI NG PRO PLAN',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFD700),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Piliin ang tamang package. Sinusuportahan nito ang GCash, Cards, atbp. sa pamamagitan ng Google Play Console Secure Checkout.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                  const SizedBox(height: 20),
                  _buildPlanTile(
                    title: 'Monthly Plan',
                    price: '₱30 / month',
                    badgeText: 'Base Plan',
                    badgeColor: Colors.white24,
                    onTap: () {
                      Navigator.pop(context);
                      _buyPlan('gastos_ko_monthly');
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildPlanTile(
                    title: 'Semi-Annual Plan',
                    price: '₱149 / 6 months',
                    badgeText: 'Save 17%',
                    badgeColor: Colors.orangeAccent,
                    onTap: () {
                      Navigator.pop(context);
                      _buyPlan('gastos_ko_semiannual');
                    },
                  ),
                  _buildPlanTile(
                    title: 'Annual Plan',
                    price: '₱249 / 1 year',
                    badgeText: 'Best Value - Save 30%',
                    badgeColor: const Color(0xFF00E676),
                    isFeatured: true,
                    onTap: () {
                      Navigator.pop(context);
                      _buyPlan('gastos_ko_annual');
                    },
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlanTile({
    required String title,
    required String price,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onTap,
    bool isFeatured = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFeatured ? const Color(0xFFFFD700) : Colors.white10,
          width: isFeatured ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isFeatured ? const Color(0xFFFFD700) : Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: badgeColor, width: 0.8),
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                      color: badgeColor,
                      fontSize: 9,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4.0),
          child: Text(
            price,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          color: isFeatured ? const Color(0xFFFFD700) : Colors.white30,
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSummaryCard(
      {required String title,
      required String value,
      required Color color,
      required IconData icon,
      bool isFullWidth = false}) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600)),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: isFullWidth ? 22 : 18,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Map<String, List> grouped = {};
    double totalGastos = 0;
    int colorIndex = 0;
    Map<String, Color> activeSessionColors = {};
    for (var e in all) {
      String key = e.title.toLowerCase().trim();
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(e);
      totalGastos += e.amount;
      if (!activeSessionColors.containsKey(key)) {
        activeSessionColors[key] =
            dynamicColors[colorIndex % dynamicColors.length];
        colorIndex++;
      }
      e.color = activeSessionColors[key]!;
      colorMap[key] = e.color;
    }
    List chartData = [];
    grouped.forEach((key, list) {
      double sum = list.fold(0, (prev, e) => prev + e.amount);
      Color assignedColor = activeSessionColors[key] ?? dynamicColors.first;
      chartData.add(GroupedExpense(
        title: list.first.title,
        total: sum,
        color: assignedColor,
        count: list.length,
      ));
    });
    double natirangBudget = budget - totalGastos;
    String activeWalletName = "Main Wallet";
    for (var w in wallets) {
      if (w.id == activeWalletId) {
        activeWalletName = w.name;
        break;
      }
    }
    List filteredExpenses = all.where((item) {
      return item.title.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('GASTOS KO',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 5,
              runSpacing: 2,
              children: [
                Text(_isPremiumUser ? 'Premium Active' : 'Free Full Version',
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0.3)),
                const Icon(
                  Icons.fiber_manual_record,
                  size: 6,
                  color: Color(0xFF00E676),
                ),
                const Text(
                  'Lifetime / Active',
                  style: TextStyle(
                      color: Color(0xFF00E676),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded,
                color: Color(0xFFFFD700), size: 24),
            tooltip: 'Export sa CSV',
            onPressed: _exportWalletToCSV,
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet,
                color: Color(0xFFFFD700), size: 24),
            tooltip: 'Wallet Manager',
            onPressed: _showWalletManagerDialog,
          )
        ],
      ),
      drawer: Drawer(
        child: Container(
          color: const Color(0xFF121212),
          child: Column(
            children: [
              DrawerHeader(
                decoration: const BoxDecoration(color: Color(0xFF1E1E1E)),
                child: Row(
                  children: [
                    Image.asset('assets/icon.png',
                        width: 60,
                        height: 60,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.calculate,
                                color: Color(0xFFFFD700), size: 60)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('GASTOS KO',
                              style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                              _isPremiumUser
                                  ? 'Premium Active'
                                  : 'Free Full Version (Active)',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              if (!_isPremiumUser)
                ListTile(
                  leading:
                      const Icon(Icons.star_rounded, color: Color(0xFFFFD700)),
                  title: const Text(
                    'Mag-upgrade sa PRO version',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFD700)),
                  ),
                  subtitle: const Text('Para ma-unlock ang lahat ng features',
                      style: TextStyle(fontSize: 10, color: Colors.white38)),
                  onTap: () {
                    Navigator.pop(context);
                    _showUpgradeOptionsBottomSheet();
                  },
                ),
              const Divider(color: Colors.white10),
              ListTile(
                leading:
                    const Icon(Icons.privacy_tip, color: Color(0xFF00E676)),
                title: const Text('Privacy Policy',
                    style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  _launchComplianceUrl('google.com');
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.description, color: Color(0xFF29B6F6)),
                title: const Text('Terms of Use (EULA)',
                    style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  _launchComplianceUrl('google.com');
                },
              ),
              ExpansionTile(
                leading:
                    const Icon(Icons.mail_outline, color: Color(0xFFFFD700)),
                title: const Text('Contact Us', style: TextStyle(fontSize: 14)),
                iconColor: const Color(0xFFFFD700),
                collapsedIconColor: Colors.white54,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 32),
                    leading: const Icon(Icons.bug_report,
                        color: Colors.redAccent, size: 20),
                    title: const Text('Report a Bug or Problem',
                        style: TextStyle(fontSize: 13)),
                    onTap: () {
                      Navigator.pop(context);
                      _sendSupportEmail('GASTOS KO - Bug Report');
                    },
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.only(left: 32),
                    leading: const Icon(Icons.lightbulb_outline,
                        color: Colors.amber, size: 20),
                    title: const Text('Send Suggestion',
                        style: TextStyle(fontSize: 13)),
                    onTap: () {
                      Navigator.pop(context);
                      _sendSupportEmail('GASTOS KO - App Suggestion');
                    },
                  ),
                ],
              ),
              const Divider(color: Colors.white10),
              const Spacer(),
              const Divider(color: Colors.white10),
              ListTile(
                leading:
                    const Icon(Icons.delete_forever, color: Colors.redAccent),
                title: const Text('Reset App Data',
                    style: TextStyle(fontSize: 14, color: Colors.redAccent)),
                subtitle: const Text('Buburahin lahat ng entries',
                    style: TextStyle(fontSize: 10, color: Colors.white38)),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (BuildContext context) => AlertDialog(
                      backgroundColor: const Color(0xFF1E1E1E),
                      title: const Text('I-reset lahat ng data?'),
                      content: const Text(
                          'Sigurado ka ba? Buburahin nito ang lahat ng na-save mong data pati ang iyong PIN code.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('I-KANSELA',
                                style: TextStyle(color: Colors.white30))),
                        TextButton(
                            onPressed: () {
                              clearAllApplicationData();
                              Navigator.pop(context);
                            },
                            child: const Text('I-RESET',
                                style: TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold))),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.wallet,
                        color: Color(0xFFFFD700), size: 22),
                    const SizedBox(width: 8),
                    Text(
                      activeWalletName.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        title: 'TOTAL BUDGET',
                        value: peso(budget),
                        color: const Color(0xFFFFD700),
                        icon: Icons.account_balance_wallet,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        title: 'TOTAL GASTOS',
                        value: peso(totalGastos),
                        color: totalGastos > budget
                            ? Colors.redAccent
                            : (totalGastos >= budget * 0.9
                                ? Colors.orangeAccent
                                : const Color(0xFF00E676)),
                        icon: Icons.trending_up,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSummaryCard(
                  title: 'NATITIRANG BUDGET',
                  value: peso(natirangBudget),
                  color: natirangBudget < 0
                      ? Colors.redAccent
                      : (totalGastos >= budget * 0.9
                          ? Colors.orangeAccent
                          : Colors.greenAccent),
                  icon: Icons.monetization_on,
                  isFullWidth: true,
                ),
                const SizedBox(height: 24),
                if (chartData.isNotEmpty) ...[
                  const Text('Gastos Biswal Chart',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70)),
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                      width: 180,
                      height: 180,
                      child: CustomPaint(
                        painter: PiePainter(
                          data: chartData,
                          total: totalGastos,
                          selectedIndex: selectedIndex,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  runWalletCategoryLegends(chartData),
                  const SizedBox(height: 24),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('History ng mga Ginastos',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70)),
                    Text('${all.length} items',
                        style: const TextStyle(color: Colors.white38)),
                  ],
                ),
                const SizedBox(height: 12),
                if (all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Maghanap ng kategorya (e.g. Pagkain)...',
                        hintStyle: const TextStyle(
                            color: Colors.white38, fontSize: 13),
                        prefixIcon: const Icon(Icons.search,
                            color: Color(0xFFFFD700), size: 20),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear,
                                    size: 18, color: Colors.white54),
                                onPressed: () {
                                  setState(() {
                                    searchQuery = "";
                                    _searchController.clear();
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 0, horizontal: 16),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFFFFD700), width: 1),
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {
                          searchQuery = val.trim();
                        });
                      },
                    ),
                  ),
                const SizedBox(height: 4),
                if (filteredExpenses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                          searchQuery.isNotEmpty
                              ? 'Walang nahanap na tugmang kategorya.'
                              : 'Walang gastos encoded. I-tap ang + sa ibaba!',
                          style: const TextStyle(
                              color: Colors.white38,
                              fontStyle: FontStyle.italic)),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredExpenses.length,
                    itemBuilder: (context, index) {
                      final item =
                          filteredExpenses[filteredExpenses.length - 1 - index];
                      return Card(
                        color: const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: item.color,
                            child: const Icon(Icons.payments,
                                color: Colors.black87),
                          ),
                          title: Text(item.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                              DateFormat('MMM dd, yyyy - hh:mm a')
                                  .format(item.date),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(peso(item.amount),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.edit,
                                    color: Color(0xFFFFD700), size: 20),
                                tooltip: 'I-edit ang entry',
                                onPressed: () => _showEditExpenseDialog(item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.redAccent, size: 20),
                                tooltip: 'Burahin ang entry',
                                onPressed: () {
                                  setState(() {
                                    all.remove(item);
                                    saveData();
                                  });
                                },
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 70),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFFD700),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.black, size: 30),
        onPressed: _checkBudgetBeforeAdding,
      ),
    );
  }

  Widget runWalletCategoryLegends(List chartData) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: List.generate(chartData.length, (index) {
        final item = chartData[index];
        final bool isSelected = selectedIndex == index;
        return GestureDetector(
          onTap: () {
            setState(() {
              selectedIndex = isSelected ? null : index;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? item.color.withValues(alpha: 0.25)
                  : const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected ? item.color : Colors.white10,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: item.color, shape: BoxShape.circle),
                ),
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? item.color : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// Helper utility para sa design structure ng list layout spacing
class SExpandingLabel extends StatelessWidget {
  final double width;
  const SExpandingLabel({super.key, required this.width});
  @override
  Widget build(BuildContext context) => SizedBox(width: width);
}
