import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const Color kBackground = Color(0xFF090F15);
const Color kSurface = Color(0xFF101B24);
const Color kSurfaceRaised = Color(0xFF15232E);
const Color kAccent = Color(0xFF099999);
const Color kAccentBright = Color(0xFF19BCB9);
const Color kInk = Color(0xFFF1F7FA);
const Color kMuted = Color(0xFF96A7B5);
const Color kBorder = Color(0xFF273844);
const Color kWarn = Color(0xFFF2B96B);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ClosePilotApp());
}

class AppRule {
  final String id;
  final String label;
  final List<String> names;
  final bool enabled;
  final bool removable;

  const AppRule({
    required this.id,
    required this.label,
    required this.names,
    required this.enabled,
    this.removable = false,
  });

  AppRule copyWith({bool? enabled}) => AppRule(
        id: id,
        label: label,
        names: names,
        enabled: enabled ?? this.enabled,
        removable: removable,
      );

  factory AppRule.fromJson(Map<String, dynamic> j) => AppRule(
        id: '${j['id'] ?? ''}',
        label: '${j['label'] ?? ''}',
        names: (j['names'] as List<dynamic>? ?? [])
            .map((e) => '$e')
            .toList(),
        enabled: j['enabled'] == true,
        removable: j['removable'] == true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'names': names,
        'enabled': enabled,
        'removable': removable,
      };
}

class MonitorConfig {
  final bool monitorEnabled;
  final bool autoStart;
  final int graceSeconds;
  final int pollSeconds;
  final List<AppRule> apps;

  const MonitorConfig({
    required this.monitorEnabled,
    required this.autoStart,
    required this.graceSeconds,
    required this.pollSeconds,
    required this.apps,
  });

  factory MonitorConfig.initial() => const MonitorConfig(
        monitorEnabled: true,
        autoStart: true,
        graceSeconds: 20,
        pollSeconds: 3,
        apps: [
          AppRule(
              id: 'chrome',
              label: 'Google Chrome',
              names: ['chrome'],
              enabled: true),
          AppRule(
              id: 'claude',
              label: 'Claude',
              names: ['claude'],
              enabled: true),
          AppRule(
              id: 'chatgpt',
              label: 'ChatGPT',
              names: ['ChatGPT'],
              enabled: true),
          AppRule(
              id: 'steam',
              label: 'Steam',
              names: ['steam', 'steamwebhelper'],
              enabled: false),
          AppRule(
              id: 'teams',
              label: 'Microsoft Teams',
              names: ['ms-teams'],
              enabled: false),
          AppRule(
              id: 'edge',
              label: 'Microsoft Edge',
              names: ['msedge'],
              enabled: false),
        ],
      );

  factory MonitorConfig.fromJson(Map<String, dynamic> j) => MonitorConfig(
        monitorEnabled: j['monitorEnabled'] != false,
        autoStart: j['autoStart'] != false,
        graceSeconds: ((j['graceSeconds'] as num?)?.toInt() ?? 20)
            .clamp(5, 120).toInt(),
        pollSeconds:
            ((j['pollSeconds'] as num?)?.toInt() ?? 3).clamp(2, 15).toInt(),
        apps: (j['apps'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AppRule.fromJson)
            .toList(),
      );

  MonitorConfig copyWith({
    bool? monitorEnabled,
    bool? autoStart,
    int? graceSeconds,
    List<AppRule>? apps,
  }) =>
      MonitorConfig(
        monitorEnabled: monitorEnabled ?? this.monitorEnabled,
        autoStart: autoStart ?? this.autoStart,
        graceSeconds: graceSeconds ?? this.graceSeconds,
        pollSeconds: pollSeconds,
        apps: apps ?? this.apps,
      );

  Map<String, dynamic> toJson() => {
        'monitorEnabled': monitorEnabled,
        'autoStart': autoStart,
        'graceSeconds': graceSeconds,
        'pollSeconds': pollSeconds,
        'apps': apps.map((e) => e.toJson()).toList(),
      };
}

class RuleStatus {
  final int count;
  final double memoryMb;
  final bool hasWindow;
  final String mode;
  final int? remainingSeconds;

  const RuleStatus({
    this.count = 0,
    this.memoryMb = 0,
    this.hasWindow = false,
    this.mode = 'not-running',
    this.remainingSeconds,
  });

  factory RuleStatus.fromJson(Map<String, dynamic> j) => RuleStatus(
        count: (j['count'] as num?)?.toInt() ?? 0,
        memoryMb: (j['memoryMb'] as num?)?.toDouble() ?? 0,
        hasWindow: j['hasWindow'] == true,
        mode: '${j['mode'] ?? 'not-running'}',
        remainingSeconds: (j['remainingSeconds'] as num?)?.toInt(),
      );
}

class CleanerEvent {
  final DateTime timestamp;
  final String kind;
  final String appId;
  final String message;
  final int pid;
  final double observedMb;

  CleanerEvent({
    required this.timestamp,
    required this.kind,
    required this.appId,
    required this.message,
    required this.pid,
    required this.observedMb,
  });

  factory CleanerEvent.fromJson(Map<String, dynamic> j) => CleanerEvent(
        timestamp: DateTime.tryParse('${j['at']}') ?? DateTime(2000),
        kind: '${j['kind'] ?? 'info'}',
        appId: '${j['app'] ?? ''}',
        message: '${j['message'] ?? ''}',
        pid: (j['pid'] as num?)?.toInt() ?? 0,
        observedMb: (j['observedMb'] as num?)?.toDouble() ?? 0,
      );
}

class ClosePilotController extends ChangeNotifier {
  MonitorConfig config = MonitorConfig.initial();
  Map<String, RuleStatus> statuses = {};
  List<CleanerEvent> events = [];
  bool loading = true;
  bool online = false;
  String? error;
  DateTime? updatedAt;
  Timer? _timer;
  bool _refreshing = false;
  late final Directory home;

  Future<void> _trace(String message) async {
    try {
      await File('${home.path}\\ui-diagnostics.log').writeAsString(
        '${DateTime.now().toIso8601String()} | $message\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<void> initialize() async {
    if (!Platform.isWindows) {
      error = 'ClosePilot runs on Windows 10/11 only.';
      loading = false;
      notifyListeners();
      return;
    }
    try {
      final base = Platform.environment['LOCALAPPDATA'];
      if (base == null || base.isEmpty) {
        throw StateError('LOCALAPPDATA is missing.');
      }
      home = Directory('$base\\ClosePilot');
      await home.create(recursive: true);
      await _trace('Initialization started');
      await _installAssets();
      await _trace('Embedded PowerShell assets installed');
      final file = File('${home.path}\\config.json');
      if (await file.exists()) {
        try {
          final data = jsonDecode(_stripBom(await file.readAsString()));
          config = MonitorConfig.fromJson(data as Map<String, dynamic>);
        } catch (e) {
          await file.copy('${file.path}.invalid.${DateTime.now().millisecondsSinceEpoch}');
          config = MonitorConfig.initial();
          await _saveConfig();
          await _trace('Invalid configuration reset: $e');
        }
      } else {
        await _saveConfig();
      }
      await _trace('Configuration ready');
      final migrationFlag = File('${home.path}\\migrated-v1.flag');
      if (!await migrationFlag.exists()) {
        try {
          await _setup('migrate-legacy');
          await migrationFlag.writeAsString(DateTime.now().toIso8601String());
          await _trace('Legacy cleanup migrated');
        } catch (e) {
          await _trace('Legacy migration warning (non-fatal): $e');
        }
      }
      if (config.autoStart) {
        try {
          await _setup('enable-startup');
        } catch (e) {
          await _trace('Startup shortcut warning (non-fatal): $e');
        }
      }
      await startAgent();
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
    } catch (e, stack) {
      error = 'Initialization failed: $e';
      try { await _trace('$error\n$stack'); } catch (_) {}
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String _stripBom(String s) => s.replaceFirst('\uFEFF', '').trim();

  Future<void> _installAssets() async {
    for (final name in ['ClosePilot-Agent.ps1', 'ClosePilot-Setup.ps1']) {
      final source = await rootBundle.loadString('assets/$name');
      final target = File('${home.path}\\$name');
      await target.writeAsString(source, flush: true);
    }
  }

  Future<void> _setup(String action) async {
    final r = await Process.run('powershell.exe', [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      '${home.path}\\ClosePilot-Setup.ps1',
      '-Action',
      action,
    ]);
    if (r.exitCode != 0) {
      throw StateError('Windows setup: ${r.stderr}');
    }
  }

  Future<void> _saveConfig() async {
    await File('${home.path}\\config.json')
        .writeAsString(jsonEncode(config.toJson()), flush: true);
    notifyListeners();
  }

  Future<void> startAgent() async {
    try {
      final script = File('${home.path}\\ClosePilot-Agent.ps1');
      if (!await script.exists()) {
        throw StateError('Agent script is missing. Try reopening ClosePilot.');
      }
      final conf = File('${home.path}\\config.json');
      if (!await conf.exists()) await _saveConfig();
      final stopFlag = File('${home.path}\\stop.request');
      if (await stopFlag.exists()) await stopFlag.delete();
      await _trace('Launching background monitor');
      final child = await Process.start(
        'powershell.exe',
        ['-NoLogo','-NoProfile','-NonInteractive','-WindowStyle','Hidden',
         '-ExecutionPolicy','Bypass','-File',script.path],
        mode: ProcessStartMode.detachedWithStdio,
        workingDirectory: home.path);
      child.stdout.transform(utf8.decoder).listen(
        (chunk) { unawaited(_trace('AGENT STDOUT: $chunk')); },
        onError: (Object e) { unawaited(_trace('AGENT STDOUT stream error: $e')); },
      );
      child.stderr.transform(utf8.decoder).listen(
        (chunk) { unawaited(_trace('AGENT STDERR: $chunk')); },
        onError: (Object e) { unawaited(_trace('AGENT STDERR stream error: $e')); },
      );
      await _trace('PowerShell launched with stderr capture, PID ${child.pid}');
      for (var attempt = 0; attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await refresh();
        if (online) {
          error = null;
          await _trace('Heartbeat confirmed: monitoring is online');
          notifyListeners();
          return;
        }
      }
      String detail = 'No agent heartbeat within 10 seconds';
      final entry = File('${home.path}\\agent-entry.log');
      if (!await entry.exists()) {
        detail = 'PowerShell did not enter the agent script. See ui-diagnostics.log';
      }
      final uiDiagnostic = File('${home.path}\\ui-diagnostics.log');
      if (await uiDiagnostic.exists()) {
        final lines = await uiDiagnostic.readAsLines();
        final stderr = lines.where((line) => line.contains('AGENT STDERR:')).toList();
        if (stderr.isNotEmpty) detail = stderr.last;
      }
      final fatal = File('${home.path}\\agent-fatal.log');
      if (await fatal.exists()) {
        final lines = await fatal.readAsLines();
        if (lines.isNotEmpty) detail = lines.last;
      }
      error = 'Agent offline: $detail';
      await _trace(error!);
      notifyListeners();
    } catch (e) {
      error = 'Unable to launch monitor: $e';
      await _trace(error!);
      notifyListeners();
    }
  }

  Future<void> stopAgent() async {
    await File('${home.path}\\stop.request').writeAsString('stop');
    await Future<void>.delayed(const Duration(seconds: 4));
    await refresh();
  }

  Future<void> restartAgent() async {
    await stopAgent();
    await startAgent();
    await Future<void>.delayed(const Duration(seconds: 2));
    await refresh();
  }

  Future<void> setMonitorEnabled(bool value) async {
    config = config.copyWith(monitorEnabled: value);
    await _saveConfig();
  }

  Future<void> setGraceSeconds(int seconds) async {
    config = config.copyWith(graceSeconds: seconds);
    await _saveConfig();
  }

  Future<void> setAutoStart(bool value) async {
    await _setup(value ? 'enable-startup' : 'disable-startup');
    config = config.copyWith(autoStart: value);
    await _saveConfig();
  }

  Future<void> setRuleEnabled(String id, bool value) async {
    config = config.copyWith(
        apps: config.apps
            .map((a) => a.id == id ? a.copyWith(enabled: value) : a)
            .toList());
    await _saveConfig();
  }

  String? validateNewRule(String label, String processNames) {
    if (label.trim().isEmpty) return 'Enter an application name.';
    final names = processNames.split(',').map((s) =>
        s.trim().replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '')).where((s) => s.isNotEmpty).toList();
    if (names.isEmpty) return 'Enter at least one process name.';
    final allowed = RegExp(r'^[a-zA-Z0-9_-]+$');
    if (names.any((n) => !allowed.hasMatch(n))) {
      return 'Only process names (without paths) are allowed.';
    }
    const unsafe = {
      'system', 'idle', 'svchost', 'wininit', 'winlogon', 'csrss',
      'services', 'lsass', 'smss', 'explorer', 'dwm', 'sihost',
      'taskhostw', 'fontdrvhost', 'registry', 'spoolsv', 'conhost',
      'powershell', 'pwsh', 'cmd', 'msmpeng', 'securityhealthservice',
      'searchhost', 'shellexperiencehost', 'startmenuexperiencehost',
      'runtimebroker', 'audiodg', 'systemsettings', 'applicationframehost',
    };
    if (names.any((n) => unsafe.contains(n.toLowerCase()))) {
      return 'Windows/system processes are not allowed.';
    }
    final existing = config.apps
        .expand((a) => a.names)
        .map((e) => e.toLowerCase())
        .toSet();
    if (names.any((n) => existing.contains(n.toLowerCase()))) {
      return 'A process is already monitored in another application.';
    }
    return null;
  }

  Future<void> addRule(String label, String processNames) async {
    final err = validateNewRule(label, processNames);
    if (err != null) throw ArgumentError(err);
    final names = processNames.split(',').map((s) =>
        s.trim().replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '')).where((s) => s.isNotEmpty).toList();
    final id = '${names.first.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}';
    config = config.copyWith(apps: [
      ...config.apps,
      AppRule(id: id, label: label.trim(), names: names, enabled: true,
          removable: true),
    ]);
    await _saveConfig();
  }

  Future<void> deleteRule(String id) async {
    config = config.copyWith(
        apps: config.apps.where((a) => a.id != id || !a.removable).toList());
    await _saveConfig();
  }

  Future<void> clearHistory() async {
    final file = File('${home.path}\\events.jsonl');
    if (await file.exists()) await file.writeAsString('');
    events = [];
    notifyListeners();
  }

  Future<void> openDataDirectory() async {
    await Process.start('explorer.exe', [home.path], mode: ProcessStartMode.detached);
  }

  Future<void> refresh() async {
    if (_refreshing || !Platform.isWindows) return;
    _refreshing = true;
    try {
      final statusFile = File('${home.path}\\status.json');
      if (await statusFile.exists()) {
        final raw = jsonDecode(_stripBom(await statusFile.readAsString()))
            as Map<String, dynamic>;
        updatedAt = DateTime.tryParse('${raw['updatedAt']}');
        online = updatedAt != null &&
            DateTime.now().difference(updatedAt!).inSeconds.abs() < 12;
        statuses = (raw['apps'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, RuleStatus.fromJson(v as Map<String, dynamic>)),
        );
      } else {
        online = false;
      }
      final log = File('${home.path}\\events.jsonl');
      if (await log.exists()) {
        final lines = await log.readAsLines();
        final tail = lines.length > 250 ? lines.sublist(lines.length - 250) : lines;
        final parsed = <CleanerEvent>[];
        for (final line in tail) {
          try {
            parsed.add(CleanerEvent.fromJson(
                jsonDecode(_stripBom(line)) as Map<String, dynamic>));
          } catch (_) {
            // Ignore a partially written line during concurrent agent logging.
          }
        }
        events = parsed.reversed.toList();
      }
    } catch (e) {
      error = 'Could not refresh monitor status: $e';
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  RuleStatus statusFor(String id) => statuses[id] ?? const RuleStatus();

  int get stoppedCount => events.where((e) => e.kind == 'stopped').length;
  int get processCount => statuses.values.fold(0, (sum, x) => sum + x.count);
  int get runningApps => statuses.values.where((s) => s.count > 0).length;
  double get observedMb => statuses.values.fold<double>(0.0, (sum, x) => sum + x.memoryMb);

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class ClosePilotApp extends StatefulWidget {
  const ClosePilotApp({super.key});
  @override
  State<ClosePilotApp> createState() => _ClosePilotAppState();
}

class _ClosePilotAppState extends State<ClosePilotApp> {
  final controller = ClosePilotController();
  int selectedPage = 0;
  double? gracePreview;

  @override
  void initState() {
    super.initState();
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? const Color(0xFF6B2E39) : kSurfaceRaised,
      content: Text(message, style: const TextStyle(color: kInk)),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _addApp() async {
    final label = TextEditingController();
    final names = TextEditingController();
    String? validation;
    final result = await showDialog<List<String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
              builder: (ctx, update) => AlertDialog(
                backgroundColor: kSurface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: const BorderSide(color: kBorder)),
                title: const Text('Add an application'),
                content: SizedBox(
                  width: 440,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                      'ClosePilot will only terminate these processes after a visible window is opened and then closed.',
                      style: TextStyle(color: kMuted, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: label,
                      decoration: const InputDecoration(
                        labelText: 'Application name',
                        hintText: 'e.g. Notepad',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: names,
                      decoration: const InputDecoration(
                        labelText: 'Process name (without .exe)',
                        hintText: 'e.g. notepad',
                        helperText: 'See Task Manager > Details. Separate multiple names with commas.',
                        helperMaxLines: 2,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (validation != null) ...[
                      const SizedBox(height: 12),
                      Text(validation!, style: const TextStyle(color: Color(0xFFFF949D))),
                    ],
                  ]),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () {
                        final issue = controller.validateNewRule(label.text, names.text);
                        if (issue != null) {
                          update(() => validation = issue);
                        } else {
                          Navigator.pop(ctx, [label.text, names.text]);
                        }
                      },
                      child: const Text('Add app')),
                ],
              ),
            ));
    label.dispose();
    names.dispose();
    if (result != null) {
      try {
        await controller.addRule(result[0], result[1]);
        _toast('${result[0]} added to monitoring');
      } catch (e) {
        _toast('$e', error: true);
      }
    }
  }

  Future<void> _deleteRule(AppRule rule) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text('Remove ${rule.label}?'),
              content: const Text('Only the monitoring rule will be removed. The installed application is not affected.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
              ],
            ));
    if (confirm == true) await controller.deleteRule(rule.id);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClosePilot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: kBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccent,
          brightness: Brightness.dark,
          surface: kSurface,
        ),
        filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
          backgroundColor: kAccent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 17),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        )),
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: kBackground,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kAccent),
          ),
        ),
      ),
      home: Scaffold(
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 930;
            if (controller.loading) {
              return const Center(
                  child: CircularProgressIndicator(color: kAccent));
            }
            return Row(children: [
              if (wide) _sidebar(),
              Expanded(
                child: Column(children: [
                  if (!wide) _compactNavigation(),
                  Expanded(
                    child: switch (selectedPage) {
                      0 => _dashboard(wide),
                      1 => _history(),
                      _ => _settings(),
                    },
                  ),
                ]),
              ),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _sidebar() => Container(
        width: 250,
        decoration: const BoxDecoration(
          color: Color(0xFF0C171F),
          border: Border(right: BorderSide(color: kBorder)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 32, 18, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 44),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kAccent, Color(0xFF066A70)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.shield_outlined, color: Colors.white, size: 25),
              ),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ClosePilot', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                Text('SYSTEM UTILITY', style: TextStyle(color: kMuted, fontSize: 9, letterSpacing: 2)),
              ]),
            ]),
          ),
          _navigationTile(Icons.space_dashboard_outlined, 'Overview', 0),
          const SizedBox(height: 9),
          _navigationTile(Icons.history_rounded, 'Activity log', 1),
          const SizedBox(height: 9),
          _navigationTile(Icons.tune_rounded, 'Settings', 2),
          const Spacer(),
          _onlineCard(),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.only(left: 12),
            child: Text('CLOSEPILOT   •   V1.0',
                style: TextStyle(color: kMuted, fontSize: 10, letterSpacing: 1.1)),
          ),
        ]),
      );

  Widget _compactNavigation() => Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder))),
        child: Row(children: [
          const Icon(Icons.shield_outlined, color: kAccentBright),
          const SizedBox(width: 7),
          const Text('ClosePilot', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const Spacer(),
          ...[
            Icons.dashboard_outlined,
            Icons.history_outlined,
            Icons.settings_outlined,
          ].asMap().entries.map((e) => IconButton(
                tooltip: ['Overview', 'Activity', 'Settings'][e.key],
                color: selectedPage == e.key ? kAccentBright : kMuted,
                onPressed: () => setState(() => selectedPage = e.key),
                icon: Icon(e.value),
              )),
        ]),
      );

  Widget _navigationTile(IconData icon, String title, int page) {
    final active = selectedPage == page;
    return Material(
      color: active ? kAccent.withValues(alpha: .13) : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => setState(() => selectedPage = page),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 16),
          child: Row(children: [
            Icon(icon, size: 21, color: active ? kAccentBright : kMuted),
            const SizedBox(width: 14),
            Text(title,
                style: TextStyle(
                    color: active ? kInk : kMuted,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
            const Spacer(),
            if (active) Container(width: 6, height: 6, decoration: const BoxDecoration(color: kAccentBright, shape: BoxShape.circle)),
          ]),
        ),
      ),
    );
  }

  Widget _onlineCard() => Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle, size: 9, color: controller.online ? kAccentBright : kWarn),
            const SizedBox(width: 9),
            Text(controller.online ? 'Agent is running' : 'Agent is offline',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Text(controller.online
              ? 'Monitoring runs independently of this window.'
              : 'Cleanup is NOT running. Open Settings to view diagnostics.',
              style: const TextStyle(fontSize: 11, color: kMuted, height: 1.5)),
        ]),
      );

  Widget _dashboard(bool wide) => ListView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 37 : 20, vertical: 32),
        children: [
          _header('System overview', 'Control what stays running after you close an app.',
              action: OutlinedButton.icon(
                  onPressed: () => controller.refresh(),
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Refresh'))),
          const SizedBox(height: 27),
          _hero(),
          if (!controller.online) ...[
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF34231C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kWarn.withValues(alpha: .55)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, color: kWarn),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  controller.error ?? 'Background monitor is offline. Cleanup cannot run.',
                  style: const TextStyle(fontSize: 12, color: kInk),
                )),
                TextButton(
                  onPressed: () => controller.openDataDirectory(),
                  child: const Text('Diagnostics folder'),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          LayoutBuilder(builder: (ctx, box) {
            final columns = box.maxWidth > 720 ? 3 : (box.maxWidth > 460 ? 2 : 1);
            final spacing = 14.0;
            final width = (box.maxWidth - (columns - 1) * spacing) / columns;
            final tiles = [
              _metric(Icons.layers_outlined, 'Active processes', '${controller.processCount}',
                  'Across watched applications'),
              _metric(Icons.memory_outlined, 'Observed memory', _formatMemory(controller.observedMb),
                  'Working sets, not freed RAM'),
              _metric(Icons.check_circle_outline, 'Recent stops', '${controller.stoppedCount}',
                  'From recent activity history'),
            ];
            return Wrap(spacing: spacing, runSpacing: spacing, children: [
              for (final tile in tiles) SizedBox(width: width, child: tile),
            ]);
          }),
          const SizedBox(height: 33),
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Protected applications', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(height: 5),
              Text('Apps are only cleaned after their last visible window closes.',
                  style: TextStyle(color: kMuted, fontSize: 12)),
            ])),
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: _addApp, icon: const Icon(Icons.add_rounded, size: 19), label: const Text('Add app')),
          ]),
          const SizedBox(height: 18),
          for (final rule in controller.config.apps) ...[
            _appRow(rule),
            const SizedBox(height: 11),
          ],
          const SizedBox(height: 13),
          _notice(),
        ],
      );

  Widget _header(String title, String subtitle, {Widget? action}) =>
      Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16, runSpacing: 14, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w800, letterSpacing: -1)),
          const SizedBox(height: 5),
          Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 13)),
        ]),
        if (action != null) action,
      ]);

  Widget _hero() {
    final configured = controller.config.monitorEnabled;
    final active = configured && controller.online;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF153B43), Color(0xFF0D242D), Color(0xFF101D28)]),
        border: Border.all(color: const Color(0xFF21636A)),
        boxShadow: [BoxShadow(color: kAccent.withValues(alpha: .08), blurRadius: 36)],
      ),
      padding: const EdgeInsets.all(25),
      child: LayoutBuilder(builder: (context, limits) {
        final narrow = limits.maxWidth < 470;
        final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(active ? Icons.verified_user_outlined : Icons.pause_circle_outline,
                size: 19, color: kAccentBright),
            const SizedBox(width: 9),
            Text(!controller.online ? 'MONITOR OFFLINE' :
                active ? 'AUTOMATIC CLEANUP ACTIVE' : 'AUTOMATIC CLEANUP PAUSED',
                style: const TextStyle(color: kAccentBright, letterSpacing: 1.1,
                    fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 13),
          Text(!controller.online ? 'Monitoring is not running.' :
              active ? 'Your apps. Your rules.' : 'Everything is on hold.',
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -.7)),
          const SizedBox(height: 7),
          const Text('Close a window. ClosePilot handles leftover background processes.',
              style: TextStyle(color: Color(0xFFC0D4D9), fontSize: 13, height: 1.5)),
        ]);
        final control = FilledButton.icon(
          onPressed: () async {
            if (!controller.online) {
              await controller.startAgent();
            } else {
              await controller.setMonitorEnabled(!configured);
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: active ? const Color(0xFF25434A) : kAccent,
          ),
          icon: Icon(active ? Icons.pause_rounded : Icons.play_arrow_rounded),
          label: Text(!controller.online ? 'Start monitor' :
              active ? 'Pause cleanup' : 'Resume cleanup'),
        );
        if (narrow) return Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [text, const SizedBox(height: 20), control]);
        return Row(children: [Expanded(child: text), const SizedBox(width: 18), control]);
      }),
    );
  }

  Widget _metric(IconData icon, String label, String value, String helper) =>
      Container(
        height: 135,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: kBorder),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: kAccentBright, size: 20),
            const SizedBox(width: 9),
            Expanded(child: Text(label, style: const TextStyle(color: kMuted, fontSize: 12))),
          ]),
          const SizedBox(height: 9),
          Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(helper, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kMuted, fontSize: 10)),
        ]),
      );

  IconData _appIcon(String id) {
    if (id == 'chrome') return Icons.language_rounded;
    if (id == 'claude') return Icons.auto_awesome_outlined;
    if (id == 'chatgpt') return Icons.hub_outlined;
    if (id == 'steam') return Icons.sports_esports_outlined;
    if (id == 'teams') return Icons.groups_outlined;
    if (id == 'edge') return Icons.explore_outlined;
    return Icons.apps_outlined;
  }

  String _formatMemory(double mb) => mb >= 1024
      ? '${(mb / 1024).toStringAsFixed(2)} GB'
      : '${mb.toStringAsFixed(0)} MB';

  (String, Color) _modeLabel(AppRule rule, RuleStatus status) {
    if (!rule.enabled) return ('Not monitored', kMuted);
    if (!controller.config.monitorEnabled) return ('Paused', kWarn);
    if (status.count == 0) return ('Not running', kMuted);
    if (status.mode == 'window-open') return ('Window open', kAccentBright);
    if (status.mode == 'closing') return ('Closing in ${status.remainingSeconds ?? 0}s', kWarn);
    if (status.mode == 'background-only') return ('Background · not armed', kMuted);
    if (status.mode == 'cleaned') return ('Cleanup completed', kAccentBright);
    return ('Monitoring', kMuted);
  }

  Widget _appRow(AppRule rule) {
    final status = controller.statusFor(rule.id);
    final mode = _modeLabel(rule, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: rule.enabled ? kBorder : const Color(0xFF1C2B35)),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: rule.enabled ? kAccent.withValues(alpha: .13) : const Color(0xFF1A2731),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(_appIcon(rule.id), size: 24, color: rule.enabled ? kAccentBright : kMuted),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rule.label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(rule.names.join(' / '), maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: kMuted)),
        ])),
        const SizedBox(width: 9),
        if (MediaQuery.sizeOf(context).width >= 750) ...[
          SizedBox(width: 158, child: Row(children: [
            Icon(Icons.circle, size: 7, color: mode.$2),
            const SizedBox(width: 7),
            Expanded(child: Text(mode.$1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: mode.$2, fontSize: 11))),
          ])),
          const SizedBox(width: 12),
          SizedBox(width: 95,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${status.count} processes',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(_formatMemory(status.memoryMb),
                  style: const TextStyle(color: kMuted, fontSize: 10)),
            ])),
        ],
        const SizedBox(width: 10),
        Switch(value: rule.enabled,
            activeThumbColor: Colors.white,
            activeTrackColor: kAccent,
            onChanged: (value) => controller.setRuleEnabled(rule.id, value)),
        if (rule.removable)
          IconButton(
            onPressed: () => _deleteRule(rule),
            tooltip: 'Remove monitoring rule',
            icon: const Icon(Icons.more_vert_rounded, size: 20, color: kMuted),
          ),
      ]),
    );
  }

  Widget _notice() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D242C),
          border: Border.all(color: const Color(0xFF37414C)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline_rounded, color: kWarn, size: 19),
          SizedBox(width: 11),
          Expanded(child: Text(
            'Safety first: ClosePilot does not stop an application that has never shown a visible window during monitoring. Keep Steam and Teams off while downloading games or making calls. Force-closing processes can interrupt active background tasks.',
            style: TextStyle(color: Color(0xFFC2C9D1), fontSize: 12, height: 1.55),
          )),
        ]),
      );

  Widget _history() => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          _header('Activity log', 'A local, inspectable history of all cleanup events.',
              action: TextButton.icon(
                  onPressed: () => controller.clearHistory(),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear history'))),
          const SizedBox(height: 24),
          if (controller.events.isEmpty)
            _emptyPanel(Icons.history_toggle_off_rounded,
                'No events yet', 'Open a monitored app, close its last window, and check here.'),
          for (final event in controller.events) ...[
            _eventTile(event),
            const SizedBox(height: 9),
          ],
        ],
      );

  Widget _eventTile(CleanerEvent event) {
    final stopped = event.kind == 'stopped';
    final failed = event.kind == 'error';
    final tint = stopped ? kAccentBright : failed ? const Color(0xFFFF9398) : kMuted;
    final time = event.timestamp.toLocal();
    final dateText = '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(15),
          border: Border.all(color: kBorder)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: tint.withValues(alpha: .11), borderRadius: BorderRadius.circular(11)),
          child: Icon(stopped ? Icons.check_circle_outline : failed ? Icons.error_outline : Icons.info_outline,
              color: tint, size: 19),
        ),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(event.message, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          if (stopped) ...[
            const SizedBox(height: 4),
            Text('Observed before stop: ${_formatMemory(event.observedMb)} · not a measured RAM saving',
                style: const TextStyle(color: kMuted, fontSize: 10)),
          ],
        ])),
        const SizedBox(width: 10),
        Text(dateText, style: const TextStyle(color: kMuted, fontSize: 11)),
      ]),
    );
  }

  Widget _emptyPanel(IconData icon, String heading, String message) => Container(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 30),
        decoration: BoxDecoration(color: kSurface,
            borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
        child: Column(children: [
          Icon(icon, size: 40, color: kAccentBright),
          const SizedBox(height: 16),
          Text(heading, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(message, textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted, fontSize: 12)),
        ]),
      );

  Widget _settings() => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          _header('Preferences', 'Set the rules that fit your workflow.'),
          const SizedBox(height: 24),
          _settingsCard(children: [
            _settingsOption(Icons.power_settings_new_rounded, 'Start with Windows',
                'Launch the invisible monitor after you sign in.',
                Switch(value: controller.config.autoStart,
                    activeThumbColor: Colors.white,
                    activeTrackColor: kAccent,
                    onChanged: (v) async {
                      try {
                        await controller.setAutoStart(v);
                        _toast(v ? 'Starts automatically with Windows' : 'Automatic startup disabled');
                      } catch (e) {
                        _toast('Failed to update startup: $e', error: true);
                      }
                    })),
            const Divider(color: kBorder),
            _settingsOption(Icons.timer_outlined, 'Close delay',
                'Wait after the last window closes, allowing quick reopening.',
                Text('${(gracePreview ?? controller.config.graceSeconds.toDouble()).round()} seconds',
                    style: const TextStyle(color: kAccentBright, fontWeight: FontWeight.w700))),
            Slider(
              value: gracePreview ?? controller.config.graceSeconds.toDouble(),
              min: 5, max: 120, divisions: 23,
              activeColor: kAccentBright,
              label: '${(gracePreview ?? controller.config.graceSeconds.toDouble()).round()}s',
              onChanged: (v) => setState(() => gracePreview = v),
              onChangeEnd: (v) async {
                await controller.setGraceSeconds(v.round());
                if (mounted) setState(() => gracePreview = null);
              },
            ),
          ]),
          const SizedBox(height: 19),
          _settingsCard(children: [
            _settingsOption(Icons.folder_open_outlined, 'Local data',
                'Configuration, monitor status and JSON activity history.',
                OutlinedButton(
                    onPressed: () => controller.openDataDirectory(),
                    child: const Text('Open folder'))),
            const Divider(color: kBorder),
            _settingsOption(Icons.restart_alt_rounded, 'Restart monitor',
                'Reload the background engine without restarting Windows.',
                OutlinedButton(
                    onPressed: () async {
                      await controller.restartAgent();
                      _toast('Monitor restart requested');
                    },
                    child: const Text('Restart'))),
            const Divider(color: kBorder),
            _settingsOption(Icons.stop_circle_outlined, 'Stop monitor completely',
                'The UI stays open, but the background agent exits until restarted.',
                OutlinedButton(
                    onPressed: () async {
                      await controller.stopAgent();
                      _toast('Monitor stop requested');
                    },
                    child: const Text('Stop agent'))),
            const Divider(color: kBorder),
            _settingsOption(Icons.play_circle_outline, 'Start monitor',
                'Run the background agent if it has been stopped.',
                FilledButton(
                    onPressed: () async {
                      await controller.startAgent();
                      _toast('Monitor start requested');
                    },
                    child: const Text('Start agent'))),
          ]),
          const SizedBox(height: 20),
          _notice(),
          if (controller.error != null) ...[
            const SizedBox(height: 16),
            Text('Diagnostic: ${controller.error}', style: const TextStyle(color: kWarn)),
          ],
        ],
      );

  Widget _settingsCard({required List<Widget> children}) => Container(
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: kBorder),
        ),
        child: Column(children: children),
      );

  Widget _settingsOption(IconData icon, String title, String description, Widget trailing) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Icon(icon, color: kAccentBright, size: 23),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 5),
            Text(description, style: const TextStyle(color: kMuted, fontSize: 11, height: 1.45)),
          ])),
          const SizedBox(width: 13),
          trailing,
        ]),
      );
}
