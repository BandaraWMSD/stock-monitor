import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Change-detector tuning (grams / seconds). Adjust to your scale's noise level.
const trig = 20.0, band = 5.0, settle = 6, minEv = 20.0, gapS = 120;
final rnd = Random();

// ---------- change detector: one per scale channel ----------
class Det {
  double? base;
  bool act = false, gap = false;
  int st = 0;
  int? last;
  final win = <List<num>>[];

  Map<String, dynamic>? feed(int ts, double g) {
    if (last != null && ts <= last!) return null;
    final isGap = last != null && ts - last! > gapS;
    last = ts;
    if (isGap) win.clear();
    win.add([ts, g]);
    while (ts - win.first[0] > settle) {
      win.removeAt(0);
    }
    final v = win.map((x) => x[1].toDouble()).toList();
    final span = ts - win.first[0];
    final stable = span >= settle - 2 && v.reduce(max) - v.reduce(min) <= band;
    final mean = v.reduce((a, b) => a + b) / v.length;
    if (base == null) {
      if (stable) base = mean;
      return null;
    }
    if (!act) {
      if ((g - base!).abs() > trig) {
        act = true; st = ts; gap = isGap;
      } else if (stable) {
        base = base! + 0.1 * (mean - base!);
      }
      return null;
    }
    if (stable) {
      final b = base!, d = mean - b;
      base = mean; act = false;
      if (d.abs() >= minEv) {
        return {'ts': st, 'before': b, 'after': mean, 'delta': d, 'gap': gap};
      }
    }
    return null;
  }
}

// ---------- runout forecast: Monte Carlo over past daily usage ----------
Map<String, dynamic> forecast(Map it, List events, double cur) {
  DateTime day(DateTime t) => DateTime(t.year, t.month, t.day);
  final today = day(DateTime.now());
  final use = <DateTime, double>{};
  for (final e in events) {
    if (e['item'] == it['id'] && e['delta'] < 0) {
      final k = day(DateTime.fromMillisecondsSinceEpoch(e['ts'] * 1000));
      use[k] = (use[k] ?? 0) - e['delta'];
    }
  }
  final days = <DateTime>[];
  for (var d = day(DateTime.fromMillisecondsSinceEpoch(it['created']));
      d.isBefore(today);
      d = DateTime(d.year, d.month, d.day + 1)) {
    days.add(d);
  }
  if (days.length < 7) return {'learn': days.length};
  final wk = days.length >= 28, last = days.last;
  final pool = <int, List<List<double>>>{};
  final tot = <int, double>{};
  for (final d in days) {
    final k = wk ? d.weekday : 0;
    final w = pow(0.5, last.difference(d).inDays / 10).toDouble();
    tot[k] = (tot[k] ?? 0) + w;
    (pool[k] ??= []).add([use[d] ?? 0, tot[k]!]);
  }
  if (days.skip(max(0, days.length - 14)).every((d) => (use[d] ?? 0) == 0)) {
    return {'idle': true};
  }
  double pick(int k) {
    final r = rnd.nextDouble() * tot[k]!;
    return pool[k]!.firstWhere((p) => p[1] >= r)[0];
  }
  const n = 1500, h = 60;
  final wd = [for (var j = 0; j <= h; j++) wk ? today.add(Duration(days: j)).weekday : 0];
  final hits = <int>[];
  for (var i = 0; i < n; i++) {
    var rem = cur, hit = h + 1;
    for (var j = 1; j <= h; j++) {
      rem -= pick(wd[j]);
      if (rem <= 0) { hit = j; break; }
    }
    hits.add(hit);
  }
  hits.sort();
  return {'p10': hits[(n * .1).floor()], 'p50': hits[(n * .5).floor()], 'p90': hits[(n * .9).floor()]};
}

// ---------- app state: MQTT, items, events ----------
class Store extends ChangeNotifier {
  List<Map<String, dynamic>> items = [], events = [];
  Map<String, dynamic> cfg = {};
  final latest = <String, List<num>>{};
  final online = <String, bool>{};
  final fc = <int, Map<String, dynamic>?>{};
  final det = <String, Det>{};
  String conn = 'not connected';
  MqttServerClient? client;
  late SharedPreferences sp;

  Future<void> init() async {
    sp = await SharedPreferences.getInstance();
    cfg = Map<String, dynamic>.from(jsonDecode(sp.getString('cfg') ?? '{}'));
    items = (jsonDecode(sp.getString('items') ?? '[]') as List).cast<Map<String, dynamic>>();
    events = (jsonDecode(sp.getString('events') ?? '[]') as List).cast<Map<String, dynamic>>();
    Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    Timer.periodic(const Duration(seconds: 60), (_) => refreshFc());
    connect();
  }

  void saveAll() {
    sp.setString('items', jsonEncode(items));
    sp.setString('events', jsonEncode(events));
  }

  Future<void> connect() async {
    client?.disconnect();
    if ((cfg['host'] ?? '') == '') return;
    final c = MqttServerClient.withPort(cfg['host'], 'app-${rnd.nextInt(99999)}', 8883)
      ..secure = true
      ..keepAlivePeriod = 20
      ..autoReconnect = true
      ..logging(on: false);
    client = c;
    conn = 'connecting…';
    notifyListeners();
    c.onDisconnected = () { if (conn == 'connected') { conn = 'disconnected'; notifyListeners(); } };
    try {
      await c.connect(cfg['user'], cfg['pass']);
    } catch (e) {
      conn = 'connection failed';
      c.disconnect();
      notifyListeners();
      return;
    }
    if (c.connectionStatus?.state != MqttConnectionState.connected) {
      conn = 'connection refused (check credentials)';
      notifyListeners();
      return;
    }
    conn = 'connected';
    c.subscribe('stock/+/+/weight', MqttQos.atLeastOnce);
    c.subscribe('stock/+/status', MqttQos.atLeastOnce);
    c.updates!.listen((msgs) {
      for (final m in msgs) {
        try {
          final s = utf8.decode((m.payload as MqttPublishMessage).payload.message);
          final t = (m.topic ?? '').split('/');
          if (t.length == 3) {
            online[t[1]] = s == 'online';
          } else {
            final d = jsonDecode(s);
            onReading('${t[1]}/${t[2]}', (d['ts'] as num).toInt(), (d['g'] as num).toDouble());
          }
        } catch (_) {}
      }
    });
    notifyListeners();
  }

  void onReading(String ch, int ts, double g) {
    final l = latest[ch];
    if (l == null || ts >= l[0]) latest[ch] = [ts, g];
    final ev = (det[ch] ??= Det()).feed(ts, g);
    final matches = items.where((i) => i['ch'] == ch && i['archived'] != true);
    if (ev != null && matches.isNotEmpty) {
      final it = matches.first;
      events.insert(0, {
        'item': it['id'], 'ts': ev['ts'],
        'before': ev['before'] - it['tare'], 'after': ev['after'] - it['tare'],
        'delta': ev['delta'], 'gap': ev['gap'],
        'type': ev['delta'] < 0 ? 'consumption' : 'restock',
      });
      if (events.length > 3000) events.removeRange(3000, events.length);
      saveAll();
      refreshFc();
    }
    notifyListeners();
  }

  void refreshFc() {
    for (final i in items) {
      final l = latest[i['ch']];
      fc[i['id']] = (l == null || i['archived'] == true)
          ? null : forecast(i, events, l[1].toDouble() - i['tare']);
    }
  }

  void addItem(List<String> v) {
    if (v[0].isEmpty || v[1].isEmpty) return;
    items.add({
      'id': DateTime.now().millisecondsSinceEpoch, 'name': v[0], 'ch': v[1],
      'tare': double.tryParse(v[2]) ?? 0.0, 'full': double.tryParse(v[3]) ?? 25000.0,
      'thr': double.tryParse(v[4]) ?? 0.0, 'lead': double.tryParse(v[5]) ?? 0.0,
      'created': DateTime.now().millisecondsSinceEpoch, 'archived': false,
    });
    saveAll(); refreshFc(); notifyListeners();
  }

  void archive(Map<String, dynamic> i) { i['archived'] = true; saveAll(); notifyListeners(); }
}

