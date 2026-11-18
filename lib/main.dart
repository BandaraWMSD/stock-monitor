import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'logic.dart';

const bg = Color(0xFF0B1215), sf = Color(0xFF121D22), bd = Color(0xFF223540);
const tx = Color(0xFFEAF2F4), mu = Color(0xFF8BA3AD);
const mint = Color(0xFF3DE0C0), amber = Color(0xFFFFB547), coral = Color(0xFFFF6B6B);
const tabular = [FontFeature.tabularFigures()];
const cap = TextStyle(color: mu, fontSize: 11);
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final s = Store();
  await s.init();
  runApp(MaterialApp(
    title: 'Stock Monitor',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: const ColorScheme.dark(primary: mint, onPrimary: Color(0xFF04201B), surface: sf, onSurface: tx),
    ),
    home: Home(s),
  ));
}

String fmt(double? g) => g == null ? '–'
    : g.abs() >= 1000 ? '${(g / 1000).toStringAsFixed(2)} kg' : '${g.round()} g';
String two(int n) => n.toString().padLeft(2, '0');
String stamp(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  return '${d.day} ${months[d.month - 1]}, ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
}

Widget pill(String t, Color c, IconData ic) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: c.withAlpha(30), borderRadius: BorderRadius.circular(20), border: Border.all(color: c.withAlpha(120))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, size: 14, color: c),
        const SizedBox(width: 5),
        Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );

// ---------- per-item display state ----------
class Stat {
  double? net;
  bool live = false, dev = false;
  String chip = 'No data', head = '–', sub = 'Waiting for data…';
  Color col = mu;
  IconData ic = Icons.sensors_off;
  int? p10, p50, p90, r;
  double level = 0;
}

Stat statOf(Store s, Map<String, dynamic> i) {
  final x = Stat(), l = s.latest[i['ch']], f = s.fc[i['id']];
  x.dev = s.online[(i['ch'] as String).split('/').first] == true;
  if (l == null) return x;
  final net = l[1].toDouble() - (i['tare'] as double);
  x.net = net;
  x.live = DateTime.now().millisecondsSinceEpoch / 1000 - l[0] < 15;
  x.level = (net / (i['full'] as double)).clamp(0.0, 1.0).toDouble();
  if (f?['learn'] != null) {
    x.head = 'Learning';
    x.sub = '${f!['learn']} of 7 days of usage data';
  } else if (f?['idle'] == true) {
    x.head = 'No usage';
    x.sub = 'Nothing used in 14 days';
  } else if (f != null) {
    x.p10 = f['p10']; x.p50 = f['p50']; x.p90 = f['p90'];
    x.r = (x.p10! - (i['lead'] as double)).round();
    x.head = x.p50! > 60 ? '60+ days' : '${x.p50} days';
    x.sub = x.p50! > 60 ? 'Plenty in stock' : 'Likely ${x.p10} to ${x.p90} days';
  }
  if (net <= (i['thr'] as double) || (x.r != null && x.r! <= 0)) {
    x.chip = 'Reorder now'; x.col = coral; x.ic = Icons.error_outline;
  } else if (x.r != null && x.r! <= 2) {
    x.chip = 'Reorder soon'; x.col = amber; x.ic = Icons.schedule;
  } else {
    x.chip = 'Healthy'; x.col = mint; x.ic = Icons.check_circle_outline;
  }
  return x;
}

// ---------- custom painters ----------
class RingPainter extends CustomPainter {
  final double v, mark;
  final Color col;
  RingPainter(this.v, this.mark, this.col);
  @override
  void paint(Canvas c, Size z) {
    final r = Rect.fromLTWH(12, 12, z.width - 24, z.height - 24);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 12..strokeCap = StrokeCap.round;
    const a0 = 2.356, sw = 4.712;
    c.drawArc(r, a0, sw, false, p..color = bd);
    if (v > 0.01) c.drawArc(r, a0, sw * v, false, p..color = col);
    final ang = a0 + sw * mark, d = Offset(cos(ang), sin(ang)), rad = r.width / 2;
    c.drawLine(r.center + d * (rad - 13), r.center + d * (rad + 13), Paint()..color = tx..strokeWidth = 2);
  }
  @override
  bool shouldRepaint(RingPainter o) => o.v != v || o.mark != mark || o.col != col;
}

class RunwayPainter extends CustomPainter {
  final int? a, m, b, r;
  final Color col;
  RunwayPainter(this.a, this.m, this.b, this.r, this.col);
  @override
  void paint(Canvas c, Size z) {
    double x(num d) => z.width * (d.clamp(0, 14) / 14);
    final y = z.height / 2;
    c.drawRRect(RRect.fromLTRBR(0, y - 3, z.width, y + 3, const Radius.circular(3)), Paint()..color = bd);
    if (a != null && b != null && m != null) {
      c.drawRRect(RRect.fromLTRBR(x(a!), y - 7, max(x(b!), x(a!) + 8), y + 7, const Radius.circular(7)),
          Paint()..color = col.withAlpha(90));
      c.drawCircle(Offset(x(m!), y), 6, Paint()..color = col);
    }
    if (r != null && r! > 0) {
      c.drawLine(Offset(x(r!), y - 12), Offset(x(r!), y + 12), Paint()..color = tx..strokeWidth = 2);
    }
  }
  @override
  bool shouldRepaint(RunwayPainter o) => true;
}

// ---------- screens ----------
class Home extends StatefulWidget {
  final Store s;
  const Home(this.s, {super.key});
  @override
  State<Home> createState() => _H();
}

class _H extends State<Home> {
  int idx = 0;
  static const titles = ['Overview', 'Activity', 'Connection'];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.s,
        builder: (ctx, _) {
          final s = widget.s, ok = s.conn == 'connected';
          return Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.circle, size: 8, color: ok ? mint : amber),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(ok ? 'CONNECTED' : s.conn.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: mu, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        const SizedBox(height: 2),
                        Text(titles[idx], style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                      ]),
                    ),
                    if (idx == 0)
                      IconButton.filled(onPressed: () => addSheet(ctx, s), icon: const Icon(Icons.add), tooltip: 'Add item'),
                  ]),
                  const SizedBox(height: 16),
                  Expanded(child: [overview(ctx, s), activity(s), ConnTab(s)][idx]),
                ]),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: idx,
              backgroundColor: sf,
              onDestinationSelected: (v) => setState(() => idx = v),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Overview'),
                NavigationDestination(icon: Icon(Icons.timeline), label: 'Activity'),
                NavigationDestination(icon: Icon(Icons.wifi_tethering), label: 'Connection'),
              ],
            ),
          );
        },
      );
}

Widget overview(BuildContext ctx, Store s) {
  final act = s.items.where((i) => i['archived'] != true).toList();
  if (act.isEmpty) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: sf, shape: BoxShape.circle, border: Border.all(color: bd)),
          child: const Icon(Icons.inventory_2_outlined, size: 44, color: mint),
        ),
        const SizedBox(height: 18),
        const Text('Track your first item', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Link a scale channel to see live weight\nand how long your stock will last.',
            textAlign: TextAlign.center, style: TextStyle(color: mu)),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: () => addSheet(ctx, s), icon: const Icon(Icons.add), label: const Text('Add item')),
      ]),
    );
  }
  final stats = act.map((i) => statOf(s, i)).toList();
  final urgent = stats.where((x) => x.chip == 'Reorder now' || x.chip == 'Reorder soon').length;
  return ListView(padding: const EdgeInsets.only(bottom: 20), children: [
    Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(urgent == 0 ? 'All ${act.length} items look healthy' : '$urgent of ${act.length} items need a reorder soon',
          style: const TextStyle(color: mu)),
    ),
    for (var k = 0; k < act.length; k++) card(ctx, s, act[k], stats[k]),
  ]);
}

Widget card(BuildContext ctx, Store s, Map<String, dynamic> i, Stat x) {
  final mark = ((i['thr'] as double) / (i['full'] as double)).clamp(0.0, 1.0).toDouble();
  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: bd),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [x.col.withAlpha(34), sf, sf]),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(i['name'], overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        pill(x.chip, x.col, x.ic),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.more_horiz, color: mu),
          tooltip: 'Archive item',
          onPressed: () => archiveAsk(ctx, s, i),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        SizedBox(
          width: 132,
          height: 132,
          child: Stack(alignment: Alignment.center, children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: x.level),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, __) => CustomPaint(size: const Size(132, 132), painter: RingPainter(v, mark, x.col)),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text(fmt(x.net), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, fontFeatures: tabular)),
              const Text('in stock', style: cap),
            ]),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('RUNWAY', style: TextStyle(color: mu, fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w600)),
            Text(x.head, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1, fontFeatures: tabular)),
            const SizedBox(height: 4),
            Text(x.sub, style: const TextStyle(color: mu, fontSize: 13)),
            if (x.r != null) ...[
              const SizedBox(height: 8),
              Text(x.r! <= 0 ? 'Order today' : 'Order within ${x.r} days',
                  style: TextStyle(color: x.col, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ]),
        ),
      ]),
      const SizedBox(height: 14),
      if (x.p50 != null) ...[
        SizedBox(height: 26, child: CustomPaint(size: Size.infinite, painter: RunwayPainter(x.p10, x.p50, x.p90, x.r, x.col))),
        const SizedBox(height: 4),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Today', style: cap), Text('1 week', style: cap), Text('2 weeks', style: cap),
        ]),
        const SizedBox(height: 10),
      ],
      Row(children: [
        Icon(Icons.circle, size: 8, color: x.live ? mint : mu),
        const SizedBox(width: 6),
        Text(x.live ? 'Live' : (x.net == null ? 'Waiting for data' : 'Stale reading'), style: const TextStyle(color: mu, fontSize: 12)),
        const Text('  ·  ', style: TextStyle(color: mu, fontSize: 12)),
        Text(x.dev ? 'Scale online' : 'Scale offline', style: const TextStyle(color: mu, fontSize: 12)),
      ]),
    ]),
  );
}

Future<void> archiveAsk(BuildContext ctx, Store s, Map<String, dynamic> i) async {
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (d) => AlertDialog(
      title: const Text('Archive this item?'),
      content: const Text('It leaves the list, but its history is kept.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Archive')),
      ],
    ),
  );
  if (ok == true) s.archive(i);
}

Widget activity(Store s) {
  if (s.events.isEmpty) {
    return const Center(
      child: Text('Every increase or decrease will appear here\nwith its exact time and amount.',
          textAlign: TextAlign.center, style: TextStyle(color: mu)),
    );
  }
  String name(id) => s.items.firstWhere((i) => i['id'] == id, orElse: () => <String, dynamic>{'name': 'Removed item'})['name'];
  return ListView.separated(
    padding: const EdgeInsets.only(bottom: 20),
    itemCount: min(s.events.length, 150),
    separatorBuilder: (_, __) => const SizedBox(height: 8),
    itemBuilder: (_, k) {
      final e = s.events[k], down = e['delta'] < 0, c = down ? coral : mint;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: sf, borderRadius: BorderRadius.circular(18), border: Border.all(color: bd)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: c.withAlpha(30), shape: BoxShape.circle),
            child: Icon(down ? Icons.south_east : Icons.north_east, size: 18, color: c),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name(e['item']), style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${e['gap'] == true ? '≈ ' : ''}${stamp(e['ts'])}  ·  ${e['before'].round()} → ${e['after'].round()} g',
                  style: const TextStyle(color: mu, fontSize: 12)),
            ]),
          ),
          Text('${down ? '−' : '+'}${e['delta'].abs().round()} g',
              style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 16, fontFeatures: tabular)),
        ]),
      );
    },
  );
}

class ConnTab extends StatefulWidget {
  final Store s;
  const ConnTab(this.s, {super.key});
  @override
  State<ConnTab> createState() => _C();
}

class _C extends State<ConnTab> {
  late final h = TextEditingController(text: widget.s.cfg['host'] ?? '');
  late final u = TextEditingController(text: widget.s.cfg['user'] ?? '');
  late final p = TextEditingController(text: widget.s.cfg['pass'] ?? '');

  @override
  Widget build(BuildContext context) {
    final s = widget.s, ok = s.conn == 'connected';
    InputDecoration dec(String l) => InputDecoration(
        labelText: l, filled: true, fillColor: sf,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: bd)));
    return ListView(children: [
      Align(alignment: Alignment.centerLeft,
          child: pill(s.conn, ok ? mint : amber, ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined)),
      const SizedBox(height: 16),
      TextField(controller: h, decoration: dec('Cluster host'), autocorrect: false),
      const SizedBox(height: 12),
      TextField(controller: u, decoration: dec('Username'), autocorrect: false),
      const SizedBox(height: 12),
      TextField(controller: p, decoration: dec('Password'), obscureText: true),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () {
          s.cfg = {'host': h.text.trim(), 'user': u.text.trim(), 'pass': p.text};
          s.sp.setString('cfg', jsonEncode(s.cfg));
          s.connect();
          FocusScope.of(context).unfocus();
        },
        child: const Text('Save and connect'),
      ),
      const SizedBox(height: 14),
      const Text('Use the subscribe-only app login. Enter the host name only, without https:// or a port.',
          style: TextStyle(color: mu, fontSize: 13)),
    ]);
  }
}

void addSheet(BuildContext ctx, Store s) => showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: sf,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (d) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(d).viewInsets.bottom),
        child: AddForm(s),
      ),
    );

class AddForm extends StatefulWidget {
  final Store s;
  const AddForm(this.s, {super.key});
  @override
  State<AddForm> createState() => _A();
}

class _A extends State<AddForm> {
  static const labels = [
    'Item name', 'Scale channel (e.g. esp32-01/ch1)', 'Empty container weight (g)',
    'Full capacity (g)', 'Reorder below (g)', 'Supplier lead time (days)',
  ];
  final c = [for (final v in ['', '', '0', '25000', '2000', '2']) TextEditingController(text: v)];

  @override
  Widget build(BuildContext context) {
    final seen = widget.s.latest.keys.toList();
    return SingleChildScrollView(
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('New item', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        for (var k = 0; k < 6; k++)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: c[k],
                keyboardType: k >= 2 ? TextInputType.number : TextInputType.text,
                decoration: InputDecoration(labelText: labels[k], border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
              ),
              if (k == 1 && seen.isNotEmpty)
                Wrap(spacing: 8, children: [
                  for (final ch in seen) ActionChip(label: Text(ch), onPressed: () => setState(() => c[1].text = ch)),
                ]),
            ]),
          ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              widget.s.addItem([for (final x in c) x.text.trim()]);
              Navigator.pop(context);
            },
            child: const Text('Add item'),
          ),
        ),
      ]),
    );
  }
}
