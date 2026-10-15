import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    });
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
            const Text('BUDGET vs GASTOS',
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
  final List<GroupedExpense> data;
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
  State<HomeScreen> createState() => _HomeState();
}

class _HomeState extends State<HomeScreen> {
  double budget = 50000;
  List<Expense> all = [];
  late DateTime sDate, eDate;
  Map<String, Color> colorMap = {};
  int? selectedIndex;
  final NumberFormat commaFormat = NumberFormat('#,##0');
  String fmt(num n) => commaFormat.format(n.toInt());
  String peso(num n) => '₱${fmt(n)}';

  static const bool isTrialVersion = true;
  static const int trialLimit = 5;

  final List<Color> dynamicColors = [
    const Color(0xFF00E676),
    const Color(0xFF00BFA5),
    const Color(0xFF29B6F6),
    const Color(0xFFFF9800),
    const Color(0xFFAB47BC),
    const Color(0xFF26A69A),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    sDate = DateTime(now.year, now.month - 1, 1);
    eDate = DateTime(now.year, now.month + 2, 0);
    _loadData();
  }

  Future<void> _loadData() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      budget = p.getDouble('budget') ?? 50000;
      String? d = p.getString('expenses');
      if (d != null) {
        List l = jsonDecode(d);
        all = l.map((e) => Expense.fromJson(e)).toList();
        colorMap.clear();
      }
    });
  }

  Future<void> _saveData() async {
    final p = await SharedPreferences.getInstance();
    await p.setDouble('budget', budget);
    await p.setString(
        'expenses', jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  // 🛠️ UNIVERSAL WEB AND ANDROID RESOLVER FIX: Inayos ang routing system parameters para maging open web standard sa FlutLab preview window panel
  Future<void> _launchComplianceUrl(String urlString) async {
    final Uri url = Uri.parse(urlString.trim());
    try {
      await launchUrl(
        url,
        mode: LaunchMode
            .platformDefault, // Ligtas sa Flutlab network sandbox rules
      );
    } catch (_) {
      // Fallback solution para sa native environment redirection layer bypass
      await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
    }
  }

  Future<void> _clearAllApplicationData() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('expenses');
    setState(() {
      all.clear();
      colorMap.clear();
      selectedIndex = null;
    });
  }

  Future<void> _openProVersion() async {
    final Uri url = Uri.parse('https://google.com');
    await launchUrl(url, mode: LaunchMode.platformDefault);
  }

  void _showTrialLockDialog() {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E1E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFFFD700), width: 1.5)),
              title: const Row(children: [
                Icon(Icons.lock, color: Color(0xFFFFD700)),
                SizedBox(width: 8),
                Text('TRIAL LIMIT REACHED!',
                    style: TextStyle(color: Colors.white, fontSize: 18)),
              ]),
              content: const Text(
                  'Naka-abot na sa maximum na 5 entries ang iyong trial list. I-download ang Pro Version para sa unlimitadong encoding.',
                  style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _openProVersion();
                  },
                  child: const Text('UPGRADE TO PRO',
                      style: TextStyle(
                          color: Color(0xFFFFD700),
                          fontWeight: FontWeight.bold)),
                )
              ],
            ));
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
          'Babala boss, nasa mahigit 90% na ang iyong nagagastos!\n\n'
          'Kasalukuyang Gastos: ${peso(currentTotal)}\n'
          'Idaragdag na Halaga: ${peso(newAmount)}\n'
          'Kabuuang Halaga: ${peso(currentTotal + newAmount)}\n'
          'Ang iyong Maximum Budget ay ${peso(budget)}.',
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
          'Sobra na sa budget ang iyong binabalak boss!\n\n'
          'Kasalukuyang Gastos: ${peso(currentTotal)}\n'
          'Idaragdag na Halaga: ${peso(newAmount)}\n'
          'Kabuuang Halaga: ${peso(currentTotal + newAmount)}\n'
          'Ang iyong Maximum Budget ay ${peso(budget)} lamang.',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OKAY, NOTED',
                style: TextStyle(
                    color: Colors.redAccent, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  void _showEditBudgetDialog() {
    final controller = TextEditingController(text: budget.toInt().toString());
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('I-edit ang iyong Budget'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            CommaFormatter()
          ],
          decoration: const InputDecoration(
              prefixText: '₱ ', hintText: 'Ipasok ang halaga'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I-CANCEL',
                  style: TextStyle(color: Colors.white30))),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                setState(() {
                  budget =
                      double.tryParse(controller.text.replaceAll(',', '')) ??
                          budget;
                  _saveData();
                });
              }
              Navigator.pop(context);
            },
            child: const Text('I-SAVE',
                style: TextStyle(color: Color(0xFFFFD700))),
          )
        ],
      ),
    );
  }

  void _showAddExpenseDialog() {
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
              child: const Text('CANCEL',
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
                  _saveData();
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
              child: const Text('CANCEL',
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
                  _saveData();
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
        border: Border.all(color: color.withOpacity(0.3), width: 1),
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
                      color: Colors.white.withOpacity(0.5),
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
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('BUDGET vs GASTOS',
                style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 0.5)),
            SizedBox(height: 3),
            Text('Trial Version',
                style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                    fontWeight: FontWeight.normal,
                    letterSpacing: 0.3)),
          ],
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white70, size: 20),
            tooltip: 'I-edit ang Budget',
            onPressed: _showEditBudgetDialog,
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
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.calculate,
                            color: Color(0xFFFFD700),
                            size: 60)),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BUDGET vs GASTOS',
                              style: TextStyle(
                                  color: Color(0xFFFFD700),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          SizedBox(height: 2),
                          Text('by RAS Mobilelabs',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 10)),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.privacy_tip, color: Color(0xFF00E676)),
                title: const Text('Privacy Policy',
                    style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  _launchComplianceUrl(
                      'https://docs.google.com/document/d/e/2PACX-1vTDUc4jwmf6m2-LTQDg1w3PUYHgxAIOzLf8Al5kt5ZtyldBaMnxkLgPqzS7dig81LZzw0Wo8wJrFr3v/pub');
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.description, color: Color(0xFF29B6F6)),
                title: const Text('Terms of Use (EULA)',
                    style: TextStyle(fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  _launchComplianceUrl(
                      'https://docs.google.com/document/d/e/2PACX-1vSR7xMdzXbQgXhsj64WyWiJZSooHLmWo0jaosoMdk3coYhezOTuvjJFIHkw4taTtdiikmjfXsG4DPzi/pub');
                },
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
                          'Sigurado ka ba boss? Buburahin nito ang lahat ng na-save mong gastos sa device mo.'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('CANCEL',
                                style: TextStyle(color: Colors.white30))),
                        TextButton(
                            onPressed: () {
                              _clearAllApplicationData();
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
                    Expanded(
                      child: _buildSummaryCard(
                        title: 'BUDGET',
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
                  const Text('ANG IYONG GASTOS CHART',
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
                          data: chartData.cast(),
                          total: totalGastos,
                          selectedIndex: selectedIndex,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? item.color.withOpacity(0.25)
                                : const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? item.color : Colors.white10,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                    color: item.color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${item.title}: ${peso(item.total)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color:
                                      isSelected ? item.color : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                ],
                GestureDetector(
                  onTap: _openProVersion,
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 24),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFFFD700).withOpacity(0.15),
                          const Color(0xFF1E1E1E)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0xFFFFD700).withOpacity(0.4),
                          width: 1),
                    ),
                    child: const Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Color(0xFFFFD700),
                          radius: 18,
                          child:
                              Icon(Icons.star, color: Colors.black87, size: 20),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gusto ng unlimitadong encoding?',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.white),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'I-unlock ang buong features, i-download ang Pro Version!',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            color: Color(0xFFFFD700), size: 14),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('HISTORY NG MGA GASTOS',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white70)),
                    Text('${all.length} / $trialLimit items',
                        style: TextStyle(
                            color: all.length >= trialLimit
                                ? Colors.redAccent
                                : Colors.white30)),
                  ],
                ),
                const SizedBox(height: 10),
                if (all.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                          'Walang gastos encoded. I-tap ang + sa ibaba!',
                          style: TextStyle(
                              color: Colors.white30,
                              fontStyle: FontStyle.italic)),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: all.length,
                    itemBuilder: (context, index) {
                      final item = all[all.length - 1 - index];
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
                                  color: Colors.white30, fontSize: 12)),
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
                                    _saveData();
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
        child: const Icon(Icons.add, color: Colors.black, size: 30),
        onPressed: () {
          if (isTrialVersion && all.length >= trialLimit) {
            _showTrialLockDialog();
          } else {
            _showAddExpenseDialog();
          }
        },
      ),
    );
  }
}
