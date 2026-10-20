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

    String? installDateStr = prefs.getString('app_install_date');
    DateTime now = DateTime.now();
    bool isExpired = false;

    if (installDateStr == null) {
      await prefs.setString('app_install_date', now.toIso8601String());
    } else {
      DateTime installDate = DateTime.parse(installDateStr);
      int daysUsed = now.difference(installDate).inDays;
      bool isPremium = prefs.getBool('is_premium_user') ?? false;

      if (daysUsed >= 30 && !isPremium) {
        isExpired = true;
      }
    }

    final savedPin = prefs.getString('user_pincode');

    if (savedPin == null || savedPin.isEmpty) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const RegistrationScreen()));
    } else {
      Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => PinCodeScreen(
                    isRegistration: false,
                    isTrialExpiredMode: isExpired,
                  )));
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
  final bool isTrialExpiredMode;
  const PinCodeScreen({
    super.key,
    required this.isRegistration,
    this.isTrialExpiredMode = false,
  });

  @override
  State<PinCodeScreen> createState() => _PinCodeScreenState();
}

class _PinCodeScreenState extends State<PinCodeScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _answerController = TextEditingController();
  String _savedPin = "";
  String _errorText = "";
  bool _isRecovering = false;
  bool _isUpdatingPin = false;
  String _currentLocale = "tl";

  int _failedAttempts = 0;
  final int _maxAttempts = 3;

  final Map<String, Map<String, String>> _pinLocalization = {
    'en': {
      'set_pin': 'SET YOUR PINCODE',
      'enter_pin': 'ENTER YOUR PINCODE',
      'trial_expired_title': '🔒 TRIAL EXPIRED LOCK',
      'trial_expired_info':
          'Your 30-day free trial has expired. Enter PIN to view limited historical data.',
      'pin_len_err': 'PIN code must be 4 digits.',
      'pin_success': 'Your PIN has been successfully updated!',
      'security_title': '🔒 SECURITY QUESTION',
      'security_question': 'What is the name of your first Pet?',
      'security_hint': 'Your answer here...',
      'setup_success': 'PIN and Security Recovery successfully set!',
      'btn_save': 'SAVE',
      'recover_title': 'RECOVER PIN CODE',
      'max_attempts': '🔒 Attempts exhausted! Here is the recovery layer.',
      'wrong_pin': 'Wrong PIN Code! ({left}/{max} attempts left)',
      'recovery_instruction':
          'Answer the question below:\nWhat is the name of your first Pet?',
      'reg_info':
          'You will use this PIN every time you open the app for your security.',
      'lock_info': 'Enter your 4-digit code to unlock.',
      'type_ans': 'Type your answer...',
      'correct_ans': 'Correct answer! Please set a new PIN.',
      'wrong_ans': 'Wrong answer! Think carefully.',
      'btn_verify': 'VERIFY ANSWER',
      'btn_confirm': 'CONFIRM & SAVE',
      'btn_unlock': 'UNLOCK',
      'forgot_pin': 'Forgot PIN Code?',
      'back_lock': 'Back to Lock Screen',
    },
    'tl': {
      'set_pin': 'MAG-SET NG IYONG PINCODE',
      'enter_pin': 'I-ENTER ANG IYONG PINCODE',
      'trial_expired_title': '🔒 EXPIRATION LOCK SCREEN',
      'trial_expired_info':
          'Tapos na ang iyong 30-day free trial. Ipasok ang PIN para mabuksan ang app sa limitadong mode.',
      'pin_len_err': 'Dapat ay may 4-digits ang PIN code.',
      'pin_success': 'Matagumpay na na-update ang iyong PIN!',
      'security_title': '🔒 SECURITY QUESTION',
      'security_question':
          'Ano ang pangalan ng iyong unang naging Alagang Hayop (Pet)?',
      'security_hint': 'Sagot mo dito...',
      'setup_success':
          'Matagumpay na nai-set ang iyong PIN at Security Recovery!',
      'btn_save': 'I-SAVE',
      'recover_title': 'IREKOBER ANG PIN CODE',
      'max_attempts': '🔒 Naubos na ang attempts mo! Heto ang recovery layer.',
      'wrong_pin': 'Maling PIN Code! ({left}/{max} attempts left)',
      'recovery_instruction':
          'Sagutin ang tanong sa ibaba:\nAno ang pangalan ng iyong unang naging Alagang Hayop (Pet)?',
      'reg_info':
          'Gagamitin mo ang PIN na ito tuwing bubuksan ang app para sa iyong seguridad.',
      'lock_info': 'Ipasok ang iyong 4-digit code para mag-unlock.',
      'type_ans': 'I-type ang iyong sagot...',
      'correct_ans': 'Tama ang sagot mo! Mag-set ka na ng bagong PIN.',
      'wrong_ans': 'Maling sagot! Isiping mabuti.',
      'btn_verify': 'I-VERIFY ANG SAGOT',
      'btn_confirm': 'I-CONFIRM AT I-SAVE',
      'btn_unlock': 'I-UNLOCK',
      'forgot_pin': 'Nakalimutan ang PIN Code?',
      'back_lock': 'Bumalik sa Lock Screen',
    }
  };

  String _getTxt(String key) => _pinLocalization[_currentLocale]?[key] ?? key;

  @override
  void initState() {
    super.initState();
    _loadSavedPinAndLocale();
  }

  Future<void> _loadSavedPinAndLocale() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _savedPin = prefs.getString('user_pincode') ?? "";
      _currentLocale = prefs.getString('app_lang_locale') ?? "tl";
    });
  }

  Future<void> _handlePinSubmit(String pin) async {
    if (pin.length < 4) {
      setState(() {
        _errorText = _getTxt('pin_len_err');
      });
      return;
    }

    if (_isUpdatingPin) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_pincode', pin);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getTxt('pin_success'))),
        );
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (context) => const HomeScreen()));
      }
    } else if (widget.isRegistration) {
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
            _errorText = _getTxt('max_attempts');
          } else {
            int natitira = _maxAttempts - _failedAttempts;
            _errorText = _getTxt('wrong_pin')
                .replaceAll('{left}', natitira.toString())
                .replaceAll('{max}', _maxAttempts.toString());
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
        title: Text(_getTxt('security_title'),
            style: const TextStyle(
                fontSize: 16,
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_getTxt('security_question'),
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
            const SizedBox(height: 12),
            TextField(
              controller: _answerController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                  hintText: _getTxt('security_hint'),
                  hintStyle: const TextStyle(color: Colors.white30)),
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
                    SnackBar(content: Text(_getTxt('setup_success'))),
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
            child: Text(_getTxt('btn_save'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
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
        _errorText = "";
        _pinController.clear();
        _answerController.clear();
      });
      await prefs.remove('user_pincode');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(_getTxt('correct_ans')),
              backgroundColor: Colors.green),
        );
      }
    } else {
      setState(() {
        _errorText = _getTxt('wrong_ans');
        _answerController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String currentTitle =
        widget.isRegistration ? _getTxt('set_pin') : _getTxt('enter_pin');
    if (widget.isTrialExpiredMode) {
      currentTitle = _getTxt('trial_expired_title');
    }
    if (_isUpdatingPin) currentTitle = _getTxt('set_pin');
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
                      : (widget.isTrialExpiredMode
                          ? Icons.timer_off_outlined
                          : ((widget.isRegistration || _isUpdatingPin)
                              ? Icons.lock_open_rounded
                              : Icons.lock_outline_rounded)),
                  size: 80,
                  color: widget.isTrialExpiredMode
                      ? Colors.redAccent
                      : const Color(0xFFFFD700),
                ),
                const SizedBox(height: 24),
                Text(
                  _isRecovering ? _getTxt('recover_title') : currentTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: widget.isTrialExpiredMode
                          ? Colors.redAccent
                          : Colors.white,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  _isRecovering
                      ? _getTxt('recovery_instruction')
                      : (widget.isTrialExpiredMode
                          ? _getTxt('trial_expired_info')
                          : ((widget.isRegistration || _isUpdatingPin)
                              ? _getTxt('reg_info')
                              : _getTxt('lock_info'))),
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
                      style: TextStyle(
                          fontSize: 28,
                          letterSpacing: 20,
                          color: widget.isTrialExpiredMode
                              ? Colors.redAccent
                              : const Color(0xFFFFD700)),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: "",
                        enabledBorder: const UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Colors.white30, width: 2)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: widget.isTrialExpiredMode
                                    ? Colors.redAccent
                                    : const Color(0xFFFFD700),
                                width: 2)),
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
                      decoration: InputDecoration(
                        hintText: _getTxt('type_ans'),
                        hintStyle: const TextStyle(
                            color: Colors.white24, fontSize: 14),
                        enabledBorder: const UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Colors.white30, width: 2)),
                        focusedBorder: const UnderlineInputBorder(
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
                    backgroundColor: widget.isTrialExpiredMode
                        ? Colors.redAccent
                        : const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 40, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text(
                    _isRecovering
                        ? _getTxt('btn_verify')
                        : ((widget.isRegistration || _isUpdatingPin)
                            ? _getTxt('btn_confirm')
                            : _getTxt('btn_unlock')),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (!widget.isRegistration &&
                    !_isRecovering &&
                    !_isUpdatingPin) ...[
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _isRecovering = true;
                        _errorText = "";
                      });
                    },
                    child: Text(
                      _getTxt('forgot_pin'),
                      style: TextStyle(
                          color: widget.isTrialExpiredMode
                              ? Colors.redAccent
                              : const Color(0xFFFFD700),
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
                    child: Text(
                      _getTxt('back_lock'),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 13),
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
  bool shouldRepaint(covariant PiePainter oldDelegate) =>
      oldDelegate.selectedIndex != selectedIndex || oldDelegate.data != data;
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
  bool _isTrialExpired = false;
  int _trialDaysLeft = 30;
  String _purchasedPlanTitle = "";
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
  String _currentLocale = "tl";
  String _activeDateFilter = "all";
  DateTimeRange? _selectedDateRange;
  Color _appBgColor = const Color(0xFF121212);
  Color _appFontColor = Colors.white;
  Color _boxBgColor = const Color(0xFF1E1E1E);
  final Map<String, Map<String, String>> _localizedText = {
    'en': {
      'total_budget': 'TOTAL BUDGET',
      'total_expenses': 'TOTAL EXPENSES',
      'remaining_budget': 'REMAINING BUDGET',
      'chart_title': 'Visual Expense Chart',
      'history_title': 'Expense Entry History',
      'no_items': 'No encoded expenses. Tap + below!',
      'search_hint': 'Search category (e.g., Food)...',
      'search_disabled_hint': 'Search disabled (Trial Expired)',
      'no_match': 'No matching category found.',
      'add_expense': 'Add Expense',
      'edit_expense': 'Edit Entry',
      'category_label': 'Category (e.g., Food)',
      'amount_label': 'Amount / Cost',
      'date_label': 'Transaction Date',
      'filter_all': 'All',
      'filter_today': 'Today',
      'btn_cancel': 'Cancel',
      'btn_save': 'Save',
      'btn_update': 'Update',
      'btn_add': 'Add',
      'wallet_manager': 'WALLET MANAGER',
      'btn_add_wallet': 'ADD NEW WALLET',
      'reset_data': 'Reset App Data',
      'reset_subtitle': 'Will delete all items',
      'upgrade_title': 'Upgrade to PRO version',
      'upgrade_subtitle': 'To unlock all features',
      'no_exp_err': 'No expenses to export!',
      'file_sheet_web_warn':
          'The file sharing sheet only works when installed on a physical phone!',
      'csv_hdr_wallet': 'Wallet Name',
      'csv_hdr_budget': 'Current Budget (₱)',
      'csv_hdr_id': 'Expense ID',
      'csv_hdr_cat': 'Category / Title',
      'csv_hdr_amt': 'Amount (₱)',
      'csv_hdr_date': 'Date and Time',
      'csv_share_txt': 'Here is my export file from the Gastos Ko App!',
      'csv_err': 'Error exporting data: ',
      'billing_err': 'Transaction error. Please try again.',
      'billing_success': 'Thank you! Your PRO Activation was successful! 🎉',
      'google_store_err': 'Product from Google Store is not ready yet.',
      'congrats_title': 'CONGRATULATIONS!',
      'congrats_desc':
          'Your new wallet "{name}" has been created with a budget of {budget}.',
      'email_app_err': 'No email app found or could not be opened.',
      'email_open_err': 'Error opening email app: ',
      'edit_wallet_title': 'Edit Name: {name}',
      'new_budget_lbl': 'New Wallet Name',
      'add_fund_title': 'Add Funds: {name}',
      'current_budget_lbl': 'Current Budget: ',
      'add_fund_lbl': 'How much to add?',
      'add_fund_success': 'Successfully added {amount} to your budget!',
      'btn_add_fund': 'ADD',
      'main_wallet_del_err': '⚠️ Cannot delete the Main Wallet!',
      'del_wallet_title': 'Delete Wallet?',
      'del_wallet_desc':
          'Are you sure? The wallet "{name}" and ALL its expense history will be permanently lost from the database!',
      'btn_delete': 'DELETE',
      'no_wallet_found': 'No wallets found.',
      'add_fund_tooltip': 'Add Funds',
      'edit_wallet_tooltip': 'Edit Name',
      'del_wallet_tooltip': 'Delete Wallet',
      'create_wallet_title': 'Create New Wallet',
      'wallet_name_lbl': 'Wallet Name (e.g., Salary)',
      'wallet_budget_lbl': 'How much is the budget?',
      'near_limit_title': 'NEARLY EXHAUSTED!',
      'near_limit_desc':
          'Warning! You have spent over 90% of your budget!\n\nAdded Amount: {amount}\n\nYour Maximum Budget is only {budget}.',
      'btn_near_limit': 'I CAN HANDLE IT',
      'exhausted_title': 'BUDGET EXHAUSTED!',
      'exhausted_desc': 'Your budget is completely used up. Add funds or not?',
      'btn_no': 'NO',
      'pre_add_budget_title': 'Please add a budget first!',
      'btn_set_budget': 'SET BUDGET',
      'pro_plan_title': 'SELECT A PRO PLAN',
      'pro_plan_desc':
          'Choose the right package. Supports GCash, Cards, etc. via Google Play Console Secure Checkout.',
      'lang_lbl': 'App Language',
      'reset_confirm_title': 'Reset all data?',
      'reset_confirm_desc':
          'Are you sure? This will delete all your saved data including your PIN code.',
      'btn_reset': 'RESET',
      'edit_entry_tooltip': 'Edit entry',
      'del_entry_tooltip': 'Delete entry',
      'settings_menu_lbl': 'Settings',
      'preset_themes_lbl': 'Preset Color Themes',
    },
    'tl': {
      'total_budget': 'TOTAL BADGET',
      'total_expenses': 'TOTAL GASTOS',
      'remaining_budget': 'NATITIRANG BADGET',
      'chart_title': 'Gastos Biswal Chart',
      'history_title': 'History ng mga Ginastos',
      'no_items': 'Walang pang ginastos. I-tap ang + sa ibaba!',
      'search_hint': 'Maghanap ng kategorya (e.g. Pagkain)...',
      'search_disabled_hint': 'Bawal maghanap (Expired na ang Trial)',
      'no_match': 'Walang nahanap na tugmang kategorya.',
      'add_expense': 'Magdagdag ng Gastos',
      'edit_expense': 'I-Edit ang Entry',
      'category_label': 'Kategorya (e.g. Pagkain)',
      'amount_label': 'Magkano / Halaga',
      'date_label': 'Petsa ng Transaksyon',
      'filter_all': 'Lahat',
      'filter_today': 'Ngayon',
      'btn_cancel': 'I-Kansela',
      'btn_save': 'I-Save',
      'btn_update': 'I-Update',
      'btn_add': 'Idagdag',
      'wallet_manager': 'WALLET MANAGER',
      'btn_add_wallet': 'MAGDAGDAG',
      'reset_data': 'I-Reset ang App',
      'reset_subtitle': 'Buburahin lahat ng entries',
      'upgrade_title': 'Mag-upgrade sa PRO version',
      'upgrade_subtitle': 'Para ma-unlock ang lahat ng features',
      'no_exp_err': 'Walang mga gastos na maie-export!',
      'file_sheet_web_warn':
          'Ang file sharing sheet ay gumagana lang kapag naka-install na sa totoong CP!',
      'csv_hdr_wallet': 'Wallet Name',
      'csv_hdr_budget': 'Current Budget (₱)',
      'csv_hdr_id': 'Expense ID',
      'csv_hdr_cat': 'Kategorya / Pamagat',
      'csv_hdr_amt': 'Halaga (₱)',
      'csv_hdr_date': 'Petsa at Oras',
      'csv_share_txt': 'Narito ang aking export file galing sa Gastos Ko App!',
      'csv_err': 'May error sa pag-export: ',
      'billing_err': 'May error sa transaksyon. Subukan muli.',
      'billing_success': 'Salamat! Matagumpay ang iyong PRO Activation! 🎉',
      'google_store_err': 'Hindi pa handa ang produkto mula sa Google Store.',
      'congrats_title': 'CONGRATULATIONS!',
      'congrats_desc':
          'Ang iyong bagong wallet "{name}" ay nagawa na at may budget na {budget}.',
      'email_app_err': 'Walang nahanap na email app o hindi mabuksan.',
      'email_open_err': 'May error sa pagbubukas ng email app: ',
      'edit_wallet_title': 'I-edit Pangalan: {name}',
      'new_budget_lbl': 'Bagong Pangalan ng Wallet',
      'add_fund_title': 'Magdagdag Pondo: {name}',
      'current_budget_lbl': 'Kasalukuyang Budget: ',
      'add_fund_lbl': 'Magkano ang idadagdag?',
      'add_fund_success':
          'Matagumpay na nakapagdagdag ng {amount} sa iyong budget!',
      'btn_add_fund': 'I-DAGDAG',
      'main_wallet_del_err': '⚠️ Hindi pwedeng burahin ang Main Wallet!',
      'del_wallet_title': 'Burahin ang Wallet?',
      'del_wallet_desc':
          'Sigurado ka ba? Permanenteng mawawala ang wallet na "{name}" pati ang LAHAT ng history ng expenses nito sa database!',
      'btn_delete': 'I-DELETE',
      'no_wallet_found': 'Walang nahanap na wallet.',
      'add_fund_tooltip': 'Magdagdag Pondo',
      'edit_wallet_tooltip': 'I-edit ang Pangalan',
      'del_wallet_tooltip': 'Delete Wallet',
      'create_wallet_title': 'Gumawa ng Bagong Wallet',
      'wallet_name_lbl': 'Pangalan ng Wallet (e.g. Sweldo)',
      'wallet_budget_lbl': 'Magkano ang Budget?',
      'near_limit_title': 'MALAPIT NA MAUBOS!',
      'near_limit_desc':
          'Babala! nasa mahigit 90% na ang iyong nagagastos!\n\nIdaragdag na Halaga: {amount}\n\nAng iyong Maximum Budget lamang ay {budget}.',
      'btn_near_limit': 'KAYANG-KAYA PA',
      'exhausted_title': 'UBOS NA ANG BUDGET!',
      'exhausted_desc': 'Ubos na ang iyong budget. Magdagdag o hindi?',
      'btn_no': 'HINDI',
      'pre_add_budget_title': 'Mag-add ka muna ng budget!',
      'btn_set_budget': 'I-SET BUDGET',
      'pro_plan_title': 'PUMILI NG PRO PLAN',
      'pro_plan_desc':
          'Piliin ang tamang package. Sinusuportahan nito ang GCash, Cards, atbp. sa pamamagitan ng Google Play Console Secure Checkout.',
      'lang_lbl': 'Wika ng App',
      'reset_confirm_title': 'I-reset lahat ng data?',
      'reset_confirm_desc':
          'Sigurado ka ba? Buburahin nito ang lahat ng na-save mong data pati ang iyong PIN code.',
      'btn_reset': 'I-RESET',
      'edit_entry_tooltip': 'I-edit ang entry',
      'del_entry_tooltip': 'Burahin ang entry',
      'settings_menu_lbl': 'Mga Setting',
      'preset_themes_lbl': 'Mga Preset Color Theme',
    }
  };
  String _getTxt(String key) {
    return _localizedText[_currentLocale]?[key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadData();
    _checkPremiumAndTrialState();
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
    SharedPreferences.getInstance().then((p) {
      String? installDateStr = p.getString('app_install_date');
      bool isExpired = false;
      if (installDateStr != null) {
        DateTime installDate = DateTime.parse(installDateStr);
        int daysUsed = DateTime.now().difference(installDate).inDays;
        bool isPremium = p.getBool('is_premium_user') ?? false;
        if (daysUsed >= 30 && !isPremium) {
          isExpired = true;
        }
      }
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
              builder: (context) => PinCodeScreen(
                  isRegistration: false, isTrialExpiredMode: isExpired)),
          (route) => false,
        );
      }
    });
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
    if (_isTrialExpired && !_isPremiumUser) {
      _showUpgradeOptionsBottomSheet();
      return;
    }
    if (all.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getTxt('no_exp_err'))),
      );
      return;
    }
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_getTxt('file_sheet_web_warn')),
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
          _getTxt('csv_hdr_wallet'),
          _getTxt('csv_hdr_budget'),
          _getTxt('csv_hdr_id'),
          _getTxt('csv_hdr_cat'),
          _getTxt('csv_hdr_amt'),
          _getTxt('csv_hdr_date')
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
      await Share.shareXFiles([xFile], text: _getTxt('csv_share_txt'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${_getTxt('csv_err')}$e")),
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
            SnackBar(content: Text(_getTxt('billing_err'))),
          );
        } else if (purchaseDetails.status == PurchaseStatus.purchased ||
            purchaseDetails.status == PurchaseStatus.restored) {
          String recognizedPlan = "Premium Plan";
          if (purchaseDetails.productID == 'gastos_ko_monthly') {
            recognizedPlan = "Monthly Plan";
          }
          if (purchaseDetails.productID == 'gastos_ko_semiannual') {
            recognizedPlan = "Semi-Annual Plan";
          }
          if (purchaseDetails.productID == 'gastos_ko_annual') {
            recognizedPlan = "Annual Plan";
          }
          _markAsPremiumUserFromSystem(recognizedPlan);
        }
        if (purchaseDetails.pendingCompletePurchase) {
          _inAppPurchase.completePurchase(purchaseDetails);
        }
      }
    }
  }

  Future _markAsPremiumUserFromSystem(String planName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium_user', true);
    await prefs.setString('purchased_plan_title', planName);
    setState(() {
      _isPremiumUser = true;
      _isTrialExpired = false;
      _purchasedPlanTitle = planName;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getTxt('billing_success'))),
      );
    }
  }

  void _buyPlan(String productId) {
    if (_products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_getTxt('google_store_err'))),
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

  Future _checkPremiumAndTrialState() async {
    final p = await SharedPreferences.getInstance();
    String? installDateStr = p.getString('app_install_date');
    int calculatedLeft = 30;
    bool expired = false;
    bool isPremium = kIsWeb ? false : (p.getBool('is_premium_user') ?? false);
    if (installDateStr != null) {
      DateTime installDate = DateTime.parse(installDateStr);
      int daysUsed = DateTime.now().difference(installDate).inDays;
      calculatedLeft = 30 - daysUsed;
      if (calculatedLeft <= 0) {
        calculatedLeft = 0;
        if (!isPremium) {
          expired = true;
        }
      }
    }
    setState(() {
      _isPremiumUser = isPremium;
      _currentLocale = p.getString('app_lang_locale') ?? "tl";
      _trialDaysLeft = calculatedLeft;
      _isTrialExpired = expired;
      _purchasedPlanTitle = p.getString('purchased_plan_title') ?? "Pro Plan";
      int? savedBgColorValue = p.getInt('app_background_color_value');
      _appBgColor = savedBgColorValue != null
          ? Color(savedBgColorValue)
          : const Color(0xFF121212);
      int? savedFontColorValue = p.getInt('app_font_color_value');
      _appFontColor = savedFontColorValue != null
          ? Color(savedFontColorValue)
          : Colors.white;
      int? savedBoxColorValue = p.getInt('app_box_color_value');
      _boxBgColor = savedBoxColorValue != null
          ? Color(savedBoxColorValue)
          : const Color(0xFF1E1E1E);
      if (expired) {
        activeWalletId = "default";
      }
    });
    if (expired) {
      loadData();
    }
  }

  Future loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _currentLocale = p.getString('app_lang_locale') ?? "tl";
      String? wData = p.getString('app_wallets');
      if (wData != null) {
        List l = jsonDecode(wData);
        wallets = l.map((e) => AppWallet.fromJson(e)).toList();
      } else {
        wallets = [AppWallet(id: "default", name: "Main Wallet", budget: 0.0)];
      }
      activeWalletId = _isTrialExpired
          ? "default"
          : (p.getString('active_wallet_id') ?? "default");
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
      String? d = p.getString('expenses$activeWalletId');
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
    await p.setString('app_lang_locale', _currentLocale);
    await p.setString(
        'app_wallets', jsonEncode(wallets.map((w) => w.toJson()).toList()));
    await p.setString('active_wallet_id', activeWalletId);
    await p.setString('expenses$activeWalletId',
        jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  void _switchWallet(String id) async {
    if (_isTrialExpired && !_isPremiumUser) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('active_wallet_id', id);
    setState(() {
      activeWalletId = id;
      selectedIndex = null;
      searchQuery = "";
      _searchController.clear();
      _activeDateFilter = "all";
      _selectedDateRange = null;
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
            Text(
              _getTxt('congrats_title'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontStyle: FontStyle.normal,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _getTxt('congrats_desc')
                  .replaceAll('{name}', name)
                  .replaceAll('{budget}', peso(budgetAmt)),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Navigator.canPop(context)
                ? ElevatedButton(
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
                : const SizedBox(),
          ],
        ),
      ),
    );
  }

  Future _launchComplianceUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    try {
      await launchUrl(
        url,
        mode: LaunchMode.platformDefault,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hindi mabuksan ang link: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
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
          SnackBar(content: Text(_getTxt('email_app_err'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${_getTxt('email_open_err')}$e")),
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
    final nameCtrl = TextEditingController(text: wallet.name);
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          _currentLocale == 'tl'
              ? 'I-edit Pangalan: ${wallet.name}'
              : 'Edit Name: ${wallet.name}',
        ),
        content: TextField(
          controller: nameCtrl,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
              labelText: _currentLocale == 'tl'
                  ? 'Bagong Pangalan ng Wallet'
                  : 'New Wallet Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_getTxt('btn_cancel'),
                style: const TextStyle(color: Colors.white30)),
          ),
          TextButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                setState(() {
                  wallet.name = nameCtrl.text.trim();
                  saveData();
                });
                setModalState(() {});
                Navigator.pop(context);
              }
            },
            child: Text(_getTxt('btn_save'),
                style: const TextStyle(
                    color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showAddAmountToWalletDialog(AppWallet wallet) {
    final amountCtrl = TextEditingController(text: "0");
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title:
            Text(_getTxt('add_fund_title').replaceAll('{name}', wallet.name)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("${_getTxt('current_budget_lbl')}${peso(wallet.budget)}",
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CommaFormatter()
              ],
              decoration: InputDecoration(
                  prefixText: '₱ ', labelText: _getTxt('add_fund_lbl')),
              onTap: () {
                amountCtrl.clear();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_getTxt('btn_cancel'),
                style: const TextStyle(color: Colors.white30)),
          ),
          TextButton(
            onPressed: () {
              double addedAmt =
                  double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0.0;
              setState(() {
                wallet.budget += addedAmt;
                if (wallet.id == activeWalletId) {
                  budget = wallet.budget;
                }
                amountCtrl.clear();
                saveData();
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(_getTxt('add_fund_success')
                        .replaceAll('{amount}', peso(addedAmt)))),
              );
            },
            child: Text(_getTxt('btn_add_fund'),
                style: const TextStyle(
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
        SnackBar(
          content: Text(_getTxt('main_wallet_del_err')),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(_getTxt('del_wallet_title'),
            style: const TextStyle(color: Colors.redAccent)),
        content:
            Text(_getTxt('del_wallet_desc').replaceAll('{name}', wallet.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_getTxt('btn_cancel'),
                style: const TextStyle(color: Colors.white30)),
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
              });
              await p.setString('app_wallets',
                  jsonEncode(wallets.map((w) => w.toJson()).toList()));
              await p.setString('active_wallet_id', activeWalletId);
              setModalState(() {});
              loadData();
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: Text(_getTxt('btn_delete'),
                style: const TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showWalletManagerDialog() {
    if (_isTrialExpired && !_isPremiumUser) {
      _showUpgradeOptionsBottomSheet();
      return;
    }
    showDialog(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet,
                      color: Color(0xFFFFD700)),
                  const SizedBox(width: 10),
                  Text(_getTxt('wallet_manager'),
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: wallets.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(20.0),
                          child:
                              Center(child: Text(_getTxt('no_wallet_found'))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: wallets.length,
                          itemBuilder: (context, idx) {
                            final w = wallets[idx];
                            final isSelected = w.id == activeWalletId;
                            return Card(
                              color: isSelected
                                  ? const Color(0xFF252525)
                                  : Colors.transparent,
                              elevation: 0,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 4),
                                leading: Icon(Icons.wallet,
                                    color: isSelected
                                        ? const Color(0xFFFFD700)
                                        : Colors.white30),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            w.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: isSelected
                                                    ? const Color(0xFFFFD700)
                                                    : _appFontColor,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.normal),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Budget: ${peso(w.budget)}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.white54),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.add,
                                              color: Color(0xFFFFD700),
                                              size: 18),
                                          tooltip: _getTxt('add_fund_tooltip'),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () {
                                            Navigator.pop(context);
                                            _showAddAmountToWalletDialog(w);
                                          },
                                        ),
                                        const SizedBox(width: 4),
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: Colors.white38, size: 18),
                                          tooltip: _currentLocale == 'tl'
                                              ? 'I-edit ang Pangalan'
                                              : 'Edit Name',
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              _showEditWalletBudgetDialog(
                                                  w, setModalState),
                                        ),
                                        if (w.id != "default") ...[
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: const Icon(
                                                Icons.delete_outline,
                                                color: Colors.redAccent,
                                                size: 18),
                                            tooltip:
                                                _getTxt('del_wallet_tooltip'),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () =>
                                                _showDeleteWalletConfirmDialog(
                                                    w, setModalState),
                                          ),
                                        ],
                                        if (isSelected) ...[
                                          const SizedBox(width: 4),
                                          const Icon(Icons.check_circle,
                                              color: Color(0xFF00E676),
                                              size: 18),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                                onTap: () {
                                  setModalState(() {
                                    activeWalletId = w.id;
                                  });
                                  Navigator.pop(context);
                                  _switchWallet(w.id);
                                },
                              ),
                            );
                          },
                        ),
                ),
                const Divider(color: Colors.white10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 4),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddWalletDialog();
                    },
                    icon: const Icon(Icons.add_card, size: 18),
                    label: Text(_getTxt('btn_add_wallet')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          const Color(0xFFFFD700).withValues(alpha: 0.15),
                      foregroundColor: const Color(0xFFFFD700),
                      minimumSize: const Size(double.infinity, 45),
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
        title: Text(_getTxt('create_wallet_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration:
                  InputDecoration(labelText: _getTxt('wallet_name_lbl')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: budgetCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                CommaFormatter()
              ],
              decoration: InputDecoration(
                  prefixText: '₱ ', labelText: _getTxt('wallet_budget_lbl')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_getTxt('btn_cancel'),
                  style: const TextStyle(color: Colors.white30))),
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
            child: Text(_getTxt('btn_save'),
                style: const TextStyle(
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
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.orangeAccent, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getTxt('near_limit_title'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          _getTxt('near_limit_desc')
              .replaceAll('{amount}', peso(newAmount))
              .replaceAll('{budget}', peso(budget)),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_getTxt('btn_near_limit'),
                style: const TextStyle(
                    color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showBudgetExhaustedAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF2C1A1A),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.redAccent, width: 1.5)),
        title: Row(
          children: [
            const Icon(Icons.error_outline_rounded,
                color: Colors.redAccent, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _getTxt('exhausted_title'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          _getTxt('exhausted_desc'),
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_getTxt('btn_no'),
                style: const TextStyle(
                    color: Colors.white38, fontWeight: FontWeight.bold)),
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
                _showAddAmountToWalletDialog(currentWallet);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: Text(_getTxt('btn_add_fund').replaceAll('I-', ''),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
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
          title: Text(
            _getTxt('pre_add_budget_title'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_getTxt('btn_cancel'),
                  style: const TextStyle(color: Colors.white38)),
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
                  _showAddAmountToWalletDialog(currentWallet);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: Colors.black,
              ),
              child: Text(_getTxt('btn_set_budget'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
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
    DateTime napilingPetsa = DateTime.now();
    showDialog(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Text(_getTxt('add_expense')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.words,
                decoration:
                    InputDecoration(labelText: _getTxt('category_label')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  CommaFormatter()
                ],
                decoration: InputDecoration(
                    prefixText: '₱ ', labelText: _getTxt('amount_label')),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.calendar_today, color: Color(0xFFFFD700)),
                title: Text(_getTxt('date_label'),
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white54)),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(napilingPetsa),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: napilingPetsa,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2101),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: Color(0xFFFFD700),
                          onPrimary: Colors.black,
                          surface: Color(0xFF1E1E1E),
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null && picked != napilingPetsa) {
                    setModalState(() {
                      napilingPetsa = picked;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_getTxt('btn_cancel'),
                    style: const TextStyle(color: Colors.white30))),
            TextButton(
              onPressed: () {
                if (titleCtrl.text.isNotEmpty && amountCtrl.text.isNotEmpty) {
                  String key = titleCtrl.text.toLowerCase().trim();
                  double amt =
                      double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
                  double kasalukuyangTotal =
                      all.fold(0, (sum, item) => sum + item.amount);
                  double bagongTotal = kasalukuyangTotal + amt;
                  double natitiraPagkatapos = budget - bagongTotal;
                  Color itemColor = colorMap[key] ??
                      dynamicColors[colorMap.length % dynamicColors.length];
                  setState(() {
                    final newExpense = Expense(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: titleCtrl.text.trim(),
                      amount: amt,
                      date: napilingPetsa,
                      color: itemColor,
                    );
                    all.add(newExpense);
                    saveData();
                  });
                  Navigator.pop(context);
                  if (natitiraPagkatapos <= 0) {
                    Future.delayed(const Duration(milliseconds: 150), () {
                      _showBudgetExhaustedAlert();
                    });
                  } else if (bagongTotal >= (budget * 0.9)) {
                    Future.delayed(const Duration(milliseconds: 150), () {
                      _showNearLimitBudgetDialog(kasalukuyangTotal, amt);
                    });
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: Text(_getTxt('btn_add'),
                  style: const TextStyle(color: Color(0xFFFFD700))),
            )
          ],
        ),
      ),
    );
  }

  void _showEditExpenseDialog(Expense item) {
    if (_isTrialExpired && !_isPremiumUser) {
      _showUpgradeOptionsBottomSheet();
      return;
    }
    final titleCtrl = TextEditingController(text: item.title);
    final amountCtrl = TextEditingController(text: fmt(item.amount));
    DateTime napilingPetsa = item.date;
    showDialog(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Row(
            children: [
              const Icon(Icons.edit, color: Color(0xFFFFD700)),
              const SizedBox(width: 8),
              Text(_getTxt('edit_expense')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                textCapitalization: TextCapitalization.words,
                decoration:
                    InputDecoration(labelText: _getTxt('category_label')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  CommaFormatter()
                ],
                decoration: InputDecoration(
                    prefixText: '₱ ', labelText: _getTxt('amount_label')),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading:
                    const Icon(Icons.calendar_today, color: Color(0xFFFFD700)),
                title: Text(_getTxt('date_label'),
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white54)),
                subtitle: Text(DateFormat('yyyy-MM-dd').format(napilingPetsa),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: napilingPetsa,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2101),
                    builder: (context, child) => Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: Color(0xFFFFD700),
                          onPrimary: Colors.black,
                          surface: Color(0xFF1E1E1E),
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null && picked != napilingPetsa) {
                    setModalState(() {
                      napilingPetsa = picked;
                    });
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_getTxt('btn_cancel'),
                    style: const TextStyle(color: Colors.white30))),
            TextButton(
              onPressed: () {
                if (titleCtrl.text.isNotEmpty && amountCtrl.text.isNotEmpty) {
                  String newKey = titleCtrl.text.toLowerCase().trim();
                  double newAmt =
                      double.tryParse(amountCtrl.text.replaceAll(',', '')) ?? 0;
                  double kasalukuyangTotalIwan = all
                      .where((e) => e.id != item.id)
                      .fold(0, (sum, e) => sum + e.amount);
                  double bagongTotalIwan = kasalukuyangTotalIwan + newAmt;
                  double natitiraPagkatapos = budget - bagongTotalIwan;
                  Color updatedColor = colorMap[newKey] ?? item.color;
                  setState(() {
                    item.title = titleCtrl.text.trim();
                    item.amount = newAmt;
                    item.color = updatedColor;
                    item.date = napilingPetsa;
                    saveData();
                  });
                  Navigator.pop(context);
                  if (natitiraPagkatapos <= 0) {
                    Future.delayed(const Duration(milliseconds: 150), () {
                      _showBudgetExhaustedAlert();
                    });
                  } else if (bagongTotalIwan >= (budget * 0.9)) {
                    Future.delayed(const Duration(milliseconds: 150), () {
                      _showNearLimitBudgetDialog(kasalukuyangTotalIwan, newAmt);
                    });
                  }
                } else {
                  Navigator.pop(context);
                }
              },
              child: Text(_getTxt('btn_update'),
                  style: const TextStyle(
                      color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
            )
          ],
        ),
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFFFD700), size: 26),
                      const SizedBox(width: 8),
                      Text(
                        _getTxt('pro_plan_title'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFFD700),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _getTxt('pro_plan_desc'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
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
      bool isFullWidth = false,
      bool highlightCard = false}) {
    return Container(
      width: isFullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _boxBgColor,
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
                      fontSize: highlightCard ? 13 : 11,
                      color: _appFontColor.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600)),
              Icon(icon, color: color, size: highlightCard ? 19 : 16),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              textAlign: TextAlign.start,
              style: TextStyle(
                  fontSize: highlightCard ? 26 : (isFullWidth ? 22 : 18),
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  Widget _buildSummaryCardDateFilters() {
    String customBtnLabel = _selectedDateRange == null
        ? (_currentLocale == 'tl' ? "Pumili ng Range" : "Pick Range")
        : "${DateFormat('MM/dd').format(_selectedDateRange!.start)} - ${DateFormat('MM/dd').format(_selectedDateRange!.end)}";
    final bool canInteract = !(_isTrialExpired && !_isPremiumUser);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            ChoiceChip(
              label: Text(_getTxt('filter_all')),
              selected: _activeDateFilter == "all",
              selectedColor: const Color(0xFFFFD700),
              labelStyle: TextStyle(
                  color: _activeDateFilter == "all"
                      ? Colors.black
                      : Colors.white70),
              onSelected: canInteract
                  ? (val) {
                      if (val) {
                        setState(() {
                          _activeDateFilter = "all";
                          selectedIndex = null;
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(_getTxt('filter_today')),
              selected: _activeDateFilter == "today",
              selectedColor: const Color(0xFFFFD700),
              labelStyle: TextStyle(
                  color: _activeDateFilter == "today"
                      ? Colors.black
                      : Colors.white70),
              onSelected: canInteract
                  ? (val) {
                      if (val) {
                        setState(() {
                          _activeDateFilter = "today";
                          selectedIndex = null;
                        });
                      }
                    }
                  : null,
            ),
            const SizedBox(width: 8),
            InputChip(
              avatar: Icon(Icons.calendar_month,
                  size: 16,
                  color: _activeDateFilter == "custom"
                      ? Colors.black
                      : const Color(0xFFFFD700)),
              label: Text(customBtnLabel),
              selected: _activeDateFilter == "custom",
              selectedColor: const Color(0xFFFFD700),
              labelStyle: TextStyle(
                  color: _activeDateFilter == "custom"
                      ? Colors.black
                      : Colors.white70),
              onPressed: canInteract
                  ? () async {
                      final DateTimeRange? picked = await showDateRangePicker(
                        context: context,
                        initialDateRange: _selectedDateRange,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2101),
                        builder: (context, child) => Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFFFFD700),
                              onPrimary: Colors.black,
                              surface: Color(0xFF1E1E1E),
                              onSurface: Colors.white,
                              primaryContainer: Color(0xFFFFD700),
                              onPrimaryContainer: Colors.black,
                            ),
                            scaffoldBackgroundColor: const Color(0xFF121212),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedDateRange = picked;
                          _activeDateFilter = "custom";
                          selectedIndex = null;
                        });
                      }
                    }
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    List dateFilteredExpenses = all.where((item) {
      if (_activeDateFilter == "today") {
        final ngayon = DateTime.now();
        return item.date.year == ngayon.year &&
            item.date.month == ngayon.month &&
            item.date.day == ngayon.day;
      } else if (_activeDateFilter == "custom" && _selectedDateRange != null) {
        final startBoundary = DateTime(
            _selectedDateRange!.start.year,
            _selectedDateRange!.start.month,
            _selectedDateRange!.start.day,
            0,
            0,
            0);
        final endBoundary = DateTime(
            _selectedDateRange!.end.year,
            _selectedDateRange!.end.month,
            _selectedDateRange!.end.day,
            23,
            59,
            59);
        return item.date
                .isAfter(startBoundary.subtract(const Duration(seconds: 1))) &&
            item.date.isBefore(endBoundary.add(const Duration(seconds: 1)));
      }
      return true;
    }).toList();
    Map<String, List> grouped = {};
    double totalGastos = 0;
    int colorIndex = 0;
    Map<String, Color> activeSessionColors = {};
    for (var e in dateFilteredExpenses) {
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
    List finalFilteredExpenses = dateFilteredExpenses.where((item) {
      return item.title.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();
    final bool trialExpiredWithNoPremium = _isTrialExpired && !_isPremiumUser;
    return Scaffold(
      backgroundColor: _appBgColor,
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
                Text(
                    _isPremiumUser
                        ? 'Pro Active'
                        : (trialExpiredWithNoPremium
                            ? 'Trial Expired'
                            : 'Free Trial Version'),
                    style: TextStyle(
                        color: trialExpiredWithNoPremium
                            ? Colors.redAccent
                            : Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0.3)),
                Icon(
                  Icons.fiber_manual_record,
                  size: 6,
                  color: trialExpiredWithNoPremium
                      ? Colors.redAccent
                      : const Color(0xFF00E676),
                ),
                Text(
                  _isPremiumUser
                      ? _purchasedPlanTitle
                      : (trialExpiredWithNoPremium
                          ? 'Locked'
                          : '$_trialDaysLeft days left'),
                  style: TextStyle(
                      color: trialExpiredWithNoPremium
                          ? Colors.redAccent
                          : const Color(0xFF00E676),
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
            icon: Icon(Icons.download_rounded,
                color: trialExpiredWithNoPremium
                    ? Colors.white10
                    : const Color(0xFFFFD700),
                size: 24),
            tooltip: 'Export sa CSV',
            onPressed: _exportWalletToCSV,
          ),
          IconButton(
            icon: Icon(Icons.account_balance_wallet,
                color: trialExpiredWithNoPremium
                    ? Colors.white10
                    : const Color(0xFFFFD700),
                size: 24),
            tooltip: _getTxt('wallet_manager'),
            onPressed: _showWalletManagerDialog,
          )
        ],
      ),
      drawer: Drawer(
        child: Container(
          color: const Color(0xFF121212),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      DrawerHeader(
                        decoration:
                            const BoxDecoration(color: Color(0xFF1E1E1E)),
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
                                          ? "Pro Active ($_purchasedPlanTitle)"
                                          : (trialExpiredWithNoPremium
                                              ? 'Trial Expired'
                                              : "Free Trial ($_trialDaysLeft days left)"),
                                      style: TextStyle(
                                          color: trialExpiredWithNoPremium
                                              ? Colors.redAccent
                                              : Colors.white38,
                                          fontSize: 10)),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.language,
                            color: Color(0xFFFFD700)),
                        title: Text(_getTxt('lang_lbl'),
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold)),
                        subtitle: Text(
                            _currentLocale == 'en' ? 'English' : 'Tagalog',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white38)),
                        trailing: DropdownButton(
                          value: _currentLocale,
                          dropdownColor: const Color(0xFF1E1E1E),
                          underline: const SizedBox(),
                          onChanged: (String? newLocale) {
                            if (newLocale != null) {
                              setState(() {
                                _currentLocale = newLocale;
                                saveData();
                              });
                            }
                          },
                          items: const [
                            DropdownMenuItem(
                                value: 'en',
                                child: Text('English',
                                    style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(
                                value: 'tl',
                                child: Text('Tagalog',
                                    style: TextStyle(fontSize: 13))),
                          ],
                        ),
                      ),
                      const Divider(color: Colors.white10),
                      if (!_isPremiumUser) ...[
                        ListTile(
                          leading: const Icon(Icons.star_rounded,
                              color: Color(0xFFFFD700)),
                          title: Text(
                            _getTxt('upgrade_title'),
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFFD700)),
                          ),
                          subtitle: Text(
                            _getTxt('upgrade_subtitle'),
                            style: const TextStyle(
                                fontSize: 10, color: Colors.white38),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _showUpgradeOptionsBottomSheet();
                          },
                        ),
                      ],
                      ListTile(
                        leading: const Icon(Icons.privacy_tip,
                            color: Color(0xFF00E676)),
                        title: const Text('Privacy Policy',
                            style: TextStyle(fontSize: 14)),
                        onTap: () {
                          Navigator.pop(context);
                          _launchComplianceUrl(
                              'https://docs.google.com/document/d/e/2PACX-1vTjonFfWFs9UiUqNne5Ro0c2ab2UhR1mnwe0E1BBl68qrK5gdaqWc9STAAvTAapBSve_7AuS8-rNNpx/pub');
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.description,
                            color: Color(0xFF29B6F6)),
                        title: const Text('Terms of Use (EULA)',
                            style: TextStyle(fontSize: 14)),
                        onTap: () {
                          Navigator.pop(context);
                          _launchComplianceUrl(
                              'https://docs.google.com/document/d/e/2PACX-1vS4ekakFeVHrKq98abpasJFDV9tdEQGFWf9USDoSOADmlY859l75tURqA5qPrcbFwEKfMPb-Bg-hLpL/pub');
                        },
                      ),
                      ExpansionTile(
                        leading: const Icon(Icons.mail_outline,
                            color: Color(0xFFFFD700)),
                        title: const Text('Contact Us',
                            style: TextStyle(fontSize: 14)),
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
                    ],
                  ),
                ),
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.settings, color: Color(0xFFFFD700)),
                title: Text(_currentLocale == 'en' ? 'Settings' : 'Mga Setting',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Text(
                    _currentLocale == 'en'
                        ? 'App configurations & reset'
                        : 'Mga config ng app & reset',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.white38)),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context,
                    builder: (context) => StatefulBuilder(
                      builder: (context, setDialogState) => AlertDialog(
                        backgroundColor: const Color(0xFF1E1E1E),
                        title: Text(
                            _currentLocale == 'en' ? 'Settings' : 'Mga Setting',
                            style: const TextStyle(
                                color: Color(0xFFFFD700),
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        content: Container(
                          width: MediaQuery.of(context).size.width * 0.85,
                          height: MediaQuery.of(context).size.height * 0.45,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getTxt('preset_themes_lbl'),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white38),
                              ),
                              const SizedBox(height: 10),
                              Expanded(
                                child: ListView(
                                  physics: const BouncingScrollPhysics(),
                                  children: [
                                    // 1 hanggang 10 (Hindi ginalaw ang mga nauna mo)
                                    _buildPresetRowItem(
                                        "Classic Dark 🕶️",
                                        const Color(0xFF121212),
                                        Colors.white,
                                        const Color(0xFF1E1E1E),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Golden Pro 💼",
                                        Colors.black,
                                        const Color(0xFFFFD700),
                                        const Color(0xFF1A1916),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Midnight Neon 👾",
                                        const Color(0xFF0A001F),
                                        const Color(0xFF00FFCC),
                                        const Color(0xFF1A0B36),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Rose Gold 👑",
                                        const Color(0xFF1A1216),
                                        const Color(0xFFFFB7CE),
                                        const Color(0xFF2E1F27),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Deep Ocean ⚓",
                                        const Color(0xFF0B132B),
                                        const Color(0xFF48CAE4),
                                        const Color(0xFF1C2541),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Matte Commando 🎖️",
                                        const Color(0xFF1B221B),
                                        const Color(0xFFD4AF37),
                                        const Color(0xFF2A342A),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Sakura Pink 🌸",
                                        const Color(0xFF1F1619),
                                        const Color(0xFFFFC0CB),
                                        const Color(0xFF332025),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Lavender Dreams 🔮",
                                        const Color(0xFF120E2E),
                                        const Color(0xFFE0B0FF),
                                        const Color(0xFF241B4B),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Crimson Stealth 🚗",
                                        const Color(0xFF140D0D),
                                        const Color(0xFFFF4D4D),
                                        const Color(0xFF241717),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Mint Fresh 🍃",
                                        const Color(0xFF0F171A),
                                        const Color(0xFFB9F6CA),
                                        const Color(0xFF1C282C),
                                        setDialogState),

                                    // 11 hanggang 20 (Mga bagong dagdag na kulay at kombinasyon)
                                    _buildPresetRowItem(
                                        "Barbie Dream 💅",
                                        const Color(0xFF2B0A1A),
                                        const Color(0xFFFF69B4),
                                        const Color(0xFF4A1530),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Cyberpunk ⚡",
                                        const Color(0xFF1A0033),
                                        const Color(0xFFFFF000),
                                        const Color(0xFF330066),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Emerald Luxury 💎",
                                        const Color(0xFF06140E),
                                        const Color(0xFF50C878),
                                        const Color(0xFF0D281C),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Ice Princess ❄️",
                                        const Color(0xFF0F1C2E),
                                        const Color(0xFFE0F7FA),
                                        const Color(0xFF1F3A60),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Chocolate Mocha ☕",
                                        const Color(0xFF1A110B),
                                        const Color(0xFFD7CCC8),
                                        const Color(0xFF2D1E15),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Cotton Candy 🍧",
                                        const Color(0xFF141724),
                                        const Color(0xFFFBB6CE),
                                        const Color(0xFF23293F),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Sunset Vibe 🌅",
                                        const Color(0xFF1F0D0D),
                                        const Color(0xFFFF9E79),
                                        const Color(0xFF3D1919),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Orchid Glam 💄",
                                        const Color(0xFF180A22),
                                        const Color(0xFFDA70D6),
                                        const Color(0xFF2E1542),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Stealth Carbon 🛹",
                                        const Color(0xFF0F0F0F),
                                        const Color(0xFF90A4AE),
                                        const Color(0xFF212121),
                                        setDialogState),
                                    _buildPresetRowItem(
                                        "Vintage Autumn 🍂",
                                        const Color(0xFF1B140E),
                                        const Color(0xFFFFB300),
                                        const Color(0xFF2E2216),
                                        setDialogState),
                                  ],
                                ),
                              ),
                              const Divider(color: Colors.white10, height: 20),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.delete_forever,
                                    color: Colors.redAccent),
                                title: Text(_getTxt('reset_data'),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(_getTxt('reset_subtitle'),
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white38)),
                                onTap: () {
                                  Navigator.pop(context);
                                  showDialog(
                                    context: context,
                                    builder: (BuildContext context) =>
                                        AlertDialog(
                                      backgroundColor: const Color(0xFF1E1E1E),
                                      title:
                                          Text(_getTxt('reset_confirm_title')),
                                      content:
                                          Text(_getTxt('reset_confirm_desc')),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: Text(_getTxt('btn_cancel'),
                                                style: const TextStyle(
                                                    color: Colors.white30))),
                                        TextButton(
                                            onPressed: () {
                                              clearAllApplicationData();
                                              Navigator.pop(context);
                                            },
                                            child: Text(_getTxt('btn_reset'),
                                                style: const TextStyle(
                                                    color: Colors.redAccent,
                                                    fontWeight:
                                                        FontWeight.bold))),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                                _currentLocale == 'en' ? 'CLOSE' : 'ISARA',
                                style: const TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontWeight: FontWeight.bold)),
                          )
                        ],
                      ),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _appFontColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSummaryCardDateFilters(),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        title: _getTxt('total_budget'),
                        value: peso(budget),
                        color: const Color(0xFFFFD700),
                        icon: Icons.account_balance_wallet,
                        highlightCard: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        title: _getTxt('total_expenses'),
                        value: peso(totalGastos),
                        color: totalGastos > budget
                            ? Colors.redAccent
                            : (totalGastos >= budget * 0.9
                                ? Colors.orangeAccent
                                : const Color(0xFF00E676)),
                        icon: Icons.trending_up,
                        highlightCard: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSummaryCard(
                  title: _getTxt('remaining_budget'),
                  value: peso(natirangBudget),
                  color: natirangBudget < 0
                      ? Colors.redAccent
                      : (totalGastos >= budget * 0.9
                          ? Colors.orangeAccent
                          : Colors.greenAccent),
                  icon: Icons.monetization_on,
                  isFullWidth: true,
                  highlightCard: true,
                ),
                const SizedBox(height: 24),
                if (chartData.isNotEmpty) ...[
                  Text(_getTxt('chart_title'),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _appFontColor.withValues(alpha: 0.7))),
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
                    Text(_getTxt('history_title'),
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _appFontColor.withValues(alpha: 0.7))),
                    Text('${finalFilteredExpenses.length} items',
                        style: const TextStyle(color: Colors.white38)),
                  ],
                ),
                const SizedBox(height: 12),
                if (all.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextField(
                      controller: _searchController,
                      enabled: !trialExpiredWithNoPremium,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: trialExpiredWithNoPremium
                            ? _getTxt('search_disabled_hint')
                            : _getTxt('search_hint'),
                        hintStyle: const TextStyle(
                            color: Colors.white38, fontSize: 13),
                        prefixIcon: const Icon(Icons.search,
                            color: Color(0xFFFFD700), size: 20),
                        suffixIcon:
                            searchQuery.isNotEmpty && !trialExpiredWithNoPremium
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
                        fillColor: _boxBgColor,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 0, horizontal: 16),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.white10),
                        ),
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
                if (finalFilteredExpenses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                          searchQuery.isNotEmpty
                              ? _getTxt('no_match')
                              : _getTxt('no_items'),
                          style: const TextStyle(
                              color: Colors.white38,
                              fontStyle: FontStyle.italic)),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: finalFilteredExpenses.length,
                    itemBuilder: (context, index) {
                      final item = finalFilteredExpenses[
                          finalFilteredExpenses.length - 1 - index];
                      return Card(
                        color: _boxBgColor,
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
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _appFontColor)),
                          subtitle: Text(
                              DateFormat('MMM dd, yyyy - hh:mm a')
                                  .format(item.date),
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(peso(item.amount),
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _appFontColor)),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(Icons.edit,
                                    color: trialExpiredWithNoPremium
                                        ? Colors.white10
                                        : const Color(0xFFFFD700),
                                    size: 20),
                                tooltip: _getTxt('edit_entry_tooltip'),
                                onPressed: () => _showEditExpenseDialog(item),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: trialExpiredWithNoPremium
                                        ? Colors.white10
                                        : Colors.redAccent,
                                    size: 20),
                                tooltip: _getTxt('del_entry_tooltip'),
                                onPressed: trialExpiredWithNoPremium
                                    ? null
                                    : () {
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
        backgroundColor:
            trialExpiredWithNoPremium ? Colors.grey : const Color(0xFFFFD700),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.black, size: 30),
        onPressed: () {
          if (trialExpiredWithNoPremium) {
            _showUpgradeOptionsBottomSheet();
          } else {
            _checkBudgetBeforeAdding();
          }
        },
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
              color:
                  isSelected ? item.color.withValues(alpha: 0.25) : _boxBgColor,
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
                    color: isSelected
                        ? item.color
                        : _appFontColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPresetRowItem(String label, Color bg, Color font, Color box,
      StateSetter setDialogState) {
    final bool isCurrentSelected = _appBgColor.value == bg.value &&
        _appFontColor.value == font.value &&
        _boxBgColor.value == box.value;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: box.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentSelected ? font : Colors.white10,
          width: isCurrentSelected ? 1.8 : 1.0,
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        title: Text(
          label,
          style:
              TextStyle(color: font, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        trailing: isCurrentSelected
            ? Icon(Icons.radio_button_checked, color: font, size: 18)
            : const Icon(Icons.radio_button_off,
                color: Colors.white24, size: 18),
        onTap: () async {
          setState(() {
            _appBgColor = bg;
            _appFontColor = font;
            _boxBgColor = box;
          });
          setDialogState(() {});
          final p = await SharedPreferences.getInstance();
          await p.setInt('app_background_color_value', bg.value);
          await p.setInt('app_font_color_value', font.value);
          await p.setInt('app_box_color_value', box.value);
        },
      ),
    );
  }
}
