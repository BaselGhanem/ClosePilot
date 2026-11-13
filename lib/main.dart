import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'update_service.dart';
import 'translations.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

const Color kBackground = Color(0xFF090F15);
const Color kSurface = Color(0xFF101B24);
const Color kSurfaceRaised = Color(0xFF15232E);
const Color kAccent = Color(0xFF099999);
const Color kAccentBright = Color(0xFF19BCB9);
const Color kInk = Color(0xFFF1F7FA);
const Color kMuted = Color(0xFF96A7B5);
const Color kBorder = Color(0xFF273844);
const Color kWarn = Color(0xFFF2B96B);

bool closePilotWindowHooksReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitle('ClosePilot | Basel Edition');
      await windowManager.setPreventClose(true);
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
          windowButtonVisibility: false);
      closePilotWindowHooksReady = true;
    } catch (_) {
      closePilotWindowHooksReady = false;
    }
  }
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
        names: (j['names'] as List<dynamic>? ?? []).map((e) => '$e').toList(),
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

enum WindowLayout {
  compact(Size(490, 575)),
  portrait(Size(545, 850)),
  standard(Size(1060, 745)),
  wide(Size(1440, 860));

  const WindowLayout(this.size);
  final Size size;
}

class MonitorConfig {
  final String language;
  final WindowLayout windowLayout;
  final bool monitorEnabled;
  final bool autoStart;
  final bool minimizeToTray;
  final int estimatedSecondsPerCleanup;
  final int graceSeconds;
  final int pollSeconds;
  final List<AppRule> apps;

  const MonitorConfig({
    required this.monitorEnabled,
    required this.autoStart,
    required this.minimizeToTray,
    required this.estimatedSecondsPerCleanup,
    required this.graceSeconds,
    required this.pollSeconds,
    required this.apps,
    this.language = 'en',
    this.windowLayout = WindowLayout.standard,
  });

  factory MonitorConfig.initial() => const MonitorConfig(
        monitorEnabled: true,
        autoStart: true,
        minimizeToTray: true,
        estimatedSecondsPerCleanup: 20,
        graceSeconds: 20,
        pollSeconds: 3,
        apps: [
          AppRule(
            id: 'chrome',
            label: 'Google Chrome',
            names: ['chrome'],
            enabled: true,
          ),
          AppRule(
              id: 'claude', label: 'Claude', names: ['claude'], enabled: true),
          AppRule(
            id: 'chatgpt',
            label: 'ChatGPT',
            names: ['ChatGPT'],
            enabled: true,
          ),
          AppRule(
            id: 'steam',
            label: 'Steam',
            names: ['steam', 'steamwebhelper'],
            enabled: false,
          ),
          AppRule(
            id: 'teams',
            label: 'Microsoft Teams',
            names: ['ms-teams'],
            enabled: false,
          ),
          AppRule(
            id: 'edge',
            label: 'Microsoft Edge',
            names: ['msedge'],
            enabled: false,
          ),
        ],
      );

  factory MonitorConfig.fromJson(Map<String, dynamic> j) => MonitorConfig(
        language: j['language'] == 'ar' ? 'ar' : 'en',
        windowLayout: WindowLayout.values.firstWhere(
          (layout) => layout.name == j['windowLayout'],
          orElse: () => WindowLayout.standard,
        ),
        monitorEnabled: j['monitorEnabled'] != false,
        autoStart: j['autoStart'] != false,
        minimizeToTray: j['minimizeToTray'] != false,
        estimatedSecondsPerCleanup:
            ((j['estimatedSecondsPerCleanup'] as num?)?.toInt() ?? 20)
                .clamp(5, 120)
                .toInt(),
        graceSeconds:
            ((j['graceSeconds'] as num?)?.toInt() ?? 20).clamp(5, 120).toInt(),
        pollSeconds:
            ((j['pollSeconds'] as num?)?.toInt() ?? 3).clamp(2, 15).toInt(),
        apps: (j['apps'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(AppRule.fromJson)
            .toList(),
      );

  MonitorConfig copyWith({
    String? language,
    WindowLayout? windowLayout,
    bool? monitorEnabled,
    bool? autoStart,
    bool? minimizeToTray,
    int? estimatedSecondsPerCleanup,
    int? graceSeconds,
    List<AppRule>? apps,
  }) =>
      MonitorConfig(
        language: language ?? this.language,
        windowLayout: windowLayout ?? this.windowLayout,
        monitorEnabled: monitorEnabled ?? this.monitorEnabled,
        autoStart: autoStart ?? this.autoStart,
        minimizeToTray: minimizeToTray ?? this.minimizeToTray,
        estimatedSecondsPerCleanup:
            estimatedSecondsPerCleanup ?? this.estimatedSecondsPerCleanup,
        graceSeconds: graceSeconds ?? this.graceSeconds,
        pollSeconds: pollSeconds,
        apps: apps ?? this.apps,
      );

  Map<String, dynamic> toJson() => {
        'language': language,
        'windowLayout': windowLayout.name,
        'monitorEnabled': monitorEnabled,
        'autoStart': autoStart,
        'minimizeToTray': minimizeToTray,
        'estimatedSecondsPerCleanup': estimatedSecondsPerCleanup,
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
  int automaticCleanupSessions = 0;
  int manualAppClosures = 0;
  int allStoppedProcesses = 0;
  Map<DateTime, int> cleanupByDay = {};
  String? error;
  DateTime? updatedAt;
  Timer? _timer;
  bool _refreshing = false;
  bool ready = false;
  Map<String, dynamic> performance = {};
  List<(String, String)> openApps = [];
  String? statusError;
  Future<void> _configWrite = Future<void>.value();
  late final Directory home;

  Future<void> _trace(String message) async {
    try {
      await File('${home.path}\\ui-diagnostics.log').writeAsString(
        '${DateTime.now().toIso8601String()} | $message\n',
        mode: FileMode.append,
        flush: true,
      );
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
          await file.copy(
            '${file.path}.invalid.${DateTime.now().millisecondsSinceEpoch}',
          );
          config = MonitorConfig.initial();
          await _saveConfig();
          await _trace('Invalid configuration reset: $e');
        }
      } else {
        await _saveConfig();
      }
      ready = true;
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
      try {
        await _trace('$error\n$stack');
      } catch (_) {}
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String _stripBom(String s) => s.replaceFirst('\uFEFF', '').trim();

  Future<void> _installAssets() async {
    for (final name in [
      'ClosePilot-Agent.ps1',
      'ClosePilot-Setup.ps1',
      'ClosePilot-Action.ps1',
      'ClosePilot-Updater.ps1',
    ]) {
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

  Future<void> _saveConfig([MonitorConfig Function(MonitorConfig)? change]) {
    final write = _configWrite.then((_) async {
      final next = change == null ? config : change(config);
      final file = File('${home.path}\\config.json');
      final temporary = File('${file.path}.$pid.tmp');
      try {
        await temporary.writeAsString(jsonEncode(next.toJson()), flush: true);
        await temporary.rename(file.path);
      } on FileSystemException {
        if (await temporary.exists()) await temporary.delete();
        rethrow;
      }
      config = next;
      notifyListeners();
    });
    _configWrite = write.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return write;
  }

  Future<void> setLanguage(String language) =>
      _saveConfig((current) => current.copyWith(language: language));

  Future<void> setWindowLayout(WindowLayout layout) =>
      _saveConfig((current) => current.copyWith(windowLayout: layout));

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
      await _trace('Launching background monitor through PowerShell bootstrap');
      await _setup('start-agent');
      await _trace('PowerShell bootstrap completed');
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
        detail =
            'PowerShell did not enter the agent script. See ui-diagnostics.log';
      }
      final uiDiagnostic = File('${home.path}\\ui-diagnostics.log');
      if (await uiDiagnostic.exists()) {
        final lines = await uiDiagnostic.readAsLines();
        final stderr =
            lines.where((line) => line.contains('AGENT STDERR:')).toList();
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
    await _setup('stop-agent');
    await refresh();
  }

  Future<void> restartAgent() async {
    await stopAgent();
    await startAgent();
    await Future<void>.delayed(const Duration(seconds: 2));
    await refresh();
  }

  Future<void> setMonitorEnabled(bool value) async {
    await _saveConfig((current) => current.copyWith(monitorEnabled: value));
  }

  Future<void> setGraceSeconds(int seconds) async {
    await _saveConfig((current) => current.copyWith(graceSeconds: seconds));
  }

  Future<void> setMinimizeToTray(bool value) async {
    await _saveConfig((current) => current.copyWith(minimizeToTray: value));
  }

  Future<void> setEstimatedSecondsPerCleanup(int value) async {
    await _saveConfig(
      (current) => current.copyWith(
        estimatedSecondsPerCleanup: value.clamp(5, 120).toInt(),
      ),
    );
  }

  Future<void> setAutoStart(bool value) async {
    await _setup(value ? 'enable-startup' : 'disable-startup');
    await _saveConfig((current) => current.copyWith(autoStart: value));
  }

  Future<void> setRuleEnabled(String id, bool value) async {
    await _saveConfig(
      (current) => current.copyWith(
        apps: current.apps
            .map((a) => a.id == id ? a.copyWith(enabled: value) : a)
            .toList(),
      ),
    );
  }

  String? validateNewRule(
    String label,
    String processNames, {
    MonitorConfig? current,
  }) {
    if (label.trim().isEmpty) return 'Enter an application name.';
    final names = processNames
        .split(RegExp('[,،]'))
        .map(
          (s) => s
              .trim()
              .replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '')
              .trim(),
        )
        .where((s) => s.isNotEmpty)
        .toList();
    if (names.isEmpty) return 'Enter at least one process name.';
    final allowed = RegExp(r'^[^\\/:*?"<>|,\x00-\x1F]+$');
    if (names.any((n) => !allowed.hasMatch(n))) {
      return 'Only process names (without paths) are allowed.';
    }
    const unsafe = {
      'system',
      'idle',
      'svchost',
      'wininit',
      'winlogon',
      'csrss',
      'services',
      'lsass',
      'smss',
      'explorer',
      'dwm',
      'sihost',
      'taskhostw',
      'fontdrvhost',
      'registry',
      'spoolsv',
      'conhost',
      'powershell',
      'pwsh',
      'cmd',
      'msmpeng',
      'securityhealthservice',
      'searchhost',
      'shellexperiencehost',
      'startmenuexperiencehost',
      'runtimebroker',
      'audiodg',
      'systemsettings',
      'applicationframehost',
      'taskmgr',
      'closepilot',
    };
    if (names.any((n) => unsafe.contains(n.toLowerCase()))) {
      return 'Windows/system processes are not allowed.';
    }
    final existing = (current ?? config)
        .apps
        .expand((a) => a.names)
        .map((e) => e.toLowerCase())
        .toSet();
    if (names.any((n) => existing.contains(n.toLowerCase()))) {
      return 'A process is already monitored in another application.';
    }
    return null;
  }

  Future<void> addRule(String label, String processNames) async {
    await _saveConfig((current) {
      final err = validateNewRule(label, processNames, current: current);
      if (err != null) throw ArgumentError(err);
      final names = <String, String>{};
      for (final part in processNames.split(RegExp('[,،]'))) {
        final name = part
            .trim()
            .replaceFirst(RegExp(r'\.exe$', caseSensitive: false), '')
            .trim();
        if (name.isNotEmpty) names[name.toLowerCase()] = name;
      }
      final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
      return current.copyWith(
        apps: [
          ...current.apps,
          AppRule(
            id: id,
            label: label.trim(),
            names: names.values.toList(),
            enabled: true,
            removable: true,
          ),
        ],
      );
    });
  }

  Future<void> deleteRule(String id) => _saveConfig(
        (current) => current.copyWith(
          apps: current.apps
              .where((app) => app.id != id || !app.removable)
              .toList(),
        ),
      );

  Future<void> clearHistory() async {
    final file = File('${home.path}\\events.jsonl');
    if (await file.exists()) await file.writeAsString('');
    events = [];
    automaticCleanupSessions = 0;
    manualAppClosures = 0;
    allStoppedProcesses = 0;
    cleanupByDay = {};
    notifyListeners();
  }

  Future<void> openDataDirectory() async {
    await Process.start(
        'explorer.exe',
        [
          home.path,
        ],
        mode: ProcessStartMode.detached);
  }

  Future<Map<String, dynamic>?> _readStatus(File file) async {
    for (var attempt = 0;; attempt++) {
      try {
        return jsonDecode(_stripBom(await file.readAsString()))
            as Map<String, dynamic>;
      } on FileSystemException catch (error) {
        final code = error.osError?.errorCode;
        if (code == 2 || code == 3) return null;
        if ((code != 32 && code != 33) || attempt == 5) rethrow;
      } on FormatException {
        if (attempt == 5) rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 35 * (attempt + 1)));
    }
  }

  Future<void> refresh() async {
    if (_refreshing || !Platform.isWindows) return;
    _refreshing = true;
    try {
      final statusFile = File('${home.path}\\status.json');
      final raw = await _readStatus(statusFile);
      statusError = null;
      if (raw != null) {
        openApps = (raw['openApps'] as Map<String, dynamic>? ?? {})
            .entries
            .where((app) => app.value is String)
            .map((app) => (app.key, app.value as String))
            .toList();
        updatedAt = DateTime.tryParse('${raw['updatedAt']}');
        online = updatedAt != null &&
            DateTime.now().difference(updatedAt!).inSeconds.abs() < 12;
        performance =
            online ? (raw['performance'] as Map<String, dynamic>? ?? {}) : {};
        statuses = (raw['apps'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, RuleStatus.fromJson(v as Map<String, dynamic>)),
        );
      } else {
        online = false;
        performance = {};
        openApps = [];
      }
      final log = File('${home.path}\\events.jsonl');
      if (await log.exists()) {
        final lines = await log.readAsLines();
        final tail =
            lines.length > 250 ? lines.sublist(lines.length - 250) : lines;
        final parsed = <CleanerEvent>[];
        var sessions = 0;
        var manualApps = 0;
        var stoppedProcesses = 0;
        final days = <DateTime, int>{};
        for (final line in lines) {
          try {
            final event = CleanerEvent.fromJson(
              jsonDecode(_stripBom(line)) as Map<String, dynamic>,
            );
            if (event.kind == 'auto-cleanup') {
              sessions++;
              final date = event.timestamp.toLocal();
              final day = DateTime(date.year, date.month, date.day);
              days[day] = (days[day] ?? 0) + 1;
            }
            if (event.kind == 'manual-close-all') manualApps++;
            if (event.kind == 'stopped') stoppedProcesses++;
          } catch (_) {
            // Ignore an unfinished log line while the monitor is appending.
          }
        }
        for (final line in tail) {
          try {
            parsed.add(
              CleanerEvent.fromJson(
                jsonDecode(_stripBom(line)) as Map<String, dynamic>,
              ),
            );
          } catch (_) {}
        }
        automaticCleanupSessions = sessions;
        manualAppClosures = manualApps;
        allStoppedProcesses = stoppedProcesses;
        cleanupByDay = days;
        events = parsed.reversed.toList();
      }
    } catch (e) {
      if (e is FileSystemException &&
          const [32, 33].contains(e.osError?.errorCode)) {
        online = updatedAt != null &&
            DateTime.now().difference(updatedAt!).inSeconds.abs() < 12;
      } else {
        statusError = 'Could not refresh monitor status: $e';
      }
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  int get estimatedSecondsSaved =>
      automaticCleanupSessions * config.estimatedSecondsPerCleanup;
  String get estimatedTimeSaved {
    final seconds = estimatedSecondsSaved;
    if (seconds < 60) return '$seconds sec';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(1)} min';
    return '${(seconds / 3600).toStringAsFixed(1)} hr';
  }

  Future<Map<String, dynamic>> forceCloseSelected(
    Set<String> selectedIds,
  ) async {
    if (!Platform.isWindows) throw StateError('Close All requires Windows.');
    if (selectedIds.isEmpty) throw StateError('No application selected.');
    final allowedIds = config.apps.map((a) => a.id).toSet();
    if (!allowedIds.containsAll(selectedIds))
      throw StateError('Invalid application selection.');
    await _configWrite;
    final idsJson = jsonEncode(selectedIds.toList());
    final idsBase64 = base64Encode(utf8.encode(idsJson));
    final script = File('${home.path}\\ClosePilot-Action.ps1');
    if (!await script.exists())
      throw StateError(
        'Close All helper script is missing. Restart ClosePilot.',
      );
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
      '-Action',
      'close-all',
      '-IdsBase64',
      idsBase64,
    ]);
    if (result.exitCode != 0) {
      throw StateError('Close All failed: ${result.stderr}');
    }
    final output = _stripBom(result.stdout as String);
    final data = jsonDecode(output) as Map<String, dynamic>;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await refresh();
    return data;
  }

  RuleStatus statusFor(String id) => statuses[id] ?? const RuleStatus();

  int get stoppedCount => events.where((e) => e.kind == 'stopped').length;
  int get processCount => statuses.values.fold(0, (sum, x) => sum + x.count);
  int get runningApps => statuses.values.where((s) => s.count > 0).length;
  double get observedMb =>
      statuses.values.fold<double>(0.0, (sum, x) => sum + x.memoryMb);

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

class _ClosePilotAppState extends State<ClosePilotApp>
    with WindowListener, TrayListener {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  bool get _arabic => controller.config.language == 'ar';
  String _tr(String english) =>
      _arabic ? (arabicText[english] ?? english) : english;
  bool _showBoot = true;
  bool _resizing = false;
  bool _trayReady = false;
  bool _backgroundBusy = false;
  bool _checkingUpdates = false;
  bool _downloadingUpdate = false;
  double _updateProgress = 0;
  final UpdateService _updateService = const UpdateService();
  double? estimatePreview;

  final controller = ClosePilotController();
  int selectedPage = 0;
  double? gracePreview;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _showBoot = false);
    });
    unawaited(_initializeAndCheckUpdates());
    if (Platform.isWindows && closePilotWindowHooksReady) {
      windowManager.addListener(this);
      trayManager.addListener(this);
      unawaited(_setupSystemTray());
    }
  }

  Future<void> _initializeAndCheckUpdates() async {
    await controller.initialize();
    if (!mounted) return;
    if (closePilotWindowHooksReady) {
      try {
        await windowManager.setMinimumSize(const Size(405, 430));
        await _resize(controller.config.windowLayout);
      } catch (e) {
        _toast('${_tr('Could not resize window')}: $e', error: true);
      }
    }
    if (_trayReady) {
      try {
        await _refreshTrayMenu();
      } catch (e) {
        _toast('${_tr('System tray unavailable')}: $e', error: true);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted) await _checkForUpdates(silentIfCurrent: true);
  }

  Future<void> _checkForUpdates({bool silentIfCurrent = false}) async {
    if (_checkingUpdates || _downloadingUpdate || !mounted) return;
    setState(() => _checkingUpdates = true);
    try {
      final release = await _updateService.checkForUpdate();
      if (!mounted) return;
      if (release == null) {
        if (!silentIfCurrent) {
          _toast('${_tr('ClosePilot is up to date')} · v$kClosePilotVersion');
        }
        return;
      }
      final approved = await showDialog<bool>(
        context: _navigator.currentContext!,
        builder: (ctx) => AlertDialog(
          scrollable: true,
          backgroundColor: kSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: kBorder),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.system_update_alt_rounded,
                color: kAccentBright,
                size: 28,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  '${_tr('Update available')} v${release.version}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 475,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_tr('Installed')} v$kClosePilotVersion · ${_tr('Available')} v${release.version}',
                  style: const TextStyle(color: kAccentBright, fontSize: 12),
                ),
                const SizedBox(height: 14),
                Text(
                  _tr('What is new'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 170),
                  child: SingleChildScrollView(
                    child: Text(
                      release.notes.isEmpty
                          ? _tr('Maintenance and improvements.')
                          : release.notes.length > 2800
                              ? '${release.notes.substring(0, 2800)}…'
                              : release.notes,
                      style: const TextStyle(
                        color: kMuted,
                        height: 1.5,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _tr(
                    'Download only after approval. ZIP integrity is verified with SHA-256. ClosePilot will close briefly, install the update, and reopen. Settings and activity history are preserved.',
                  ),
                  style: TextStyle(color: kMuted, fontSize: 11, height: 1.6),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_tr('Not now')),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.download_rounded),
              label: Text(_tr('Update Now')),
            ),
          ],
        ),
      );
      if (approved == true && mounted) {
        await _installRelease(release);
      }
    } catch (e) {
      if (!silentIfCurrent && mounted) {
        _toast('${_tr('Update check failed')}: $e', error: true);
      }
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  Future<void> _installRelease(ClosePilotRelease release) async {
    if (_downloadingUpdate || _backgroundBusy) return;
    setState(() {
      _downloadingUpdate = true;
      _backgroundBusy = true;
      _updateProgress = 0;
    });
    try {
      final archive = await _updateService.downloadVerified(
        release,
        onProgress: (progress) {
          if (mounted) setState(() => _updateProgress = progress);
        },
      );
      if (!mounted) return;
      await _updateService.prepareInstallation(release, archive);
      if (mounted) {
        _toast('${_tr('Update verified')} · v${release.version}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (closePilotWindowHooksReady) {
        try {
          await windowManager.setPreventClose(false);
          await trayManager.destroy();
        } catch (_) {}
      }
      // Only this UI exits. The separate background monitor remains active.
      exit(0);
    } catch (e) {
      if (mounted) _toast('${_tr('Update not installed')}: $e', error: true);
    } finally {
      if (mounted)
        setState(() {
          _downloadingUpdate = false;
          _backgroundBusy = false;
        });
    }
  }

  Future<void> _setupSystemTray() async {
    try {
      final base = Platform.environment['LOCALAPPDATA'];
      if (base == null || base.isEmpty) return;
      final folder = Directory('$base\\ClosePilot');
      await folder.create(recursive: true);
      final bytes = await rootBundle.load('assets/closepilot.ico');
      final iconPath = File('${folder.path}\\closepilot-tray-v131.ico');
      await iconPath.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await trayManager.setIcon(iconPath.path);
      await trayManager.setToolTip('ClosePilot • Basel Edition');
      await _refreshTrayMenu();
      if (!mounted) return;
      setState(() => _trayReady = true);
    } catch (e) {
      if (closePilotWindowHooksReady) {
        try {
          await windowManager.setPreventClose(false);
        } catch (_) {}
      }
      if (mounted) _toast('${_tr('System tray unavailable')}: $e', error: true);
    }
  }

  Future<void> _refreshTrayMenu() => trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'open', label: _tr('Open ClosePilot')),
            MenuItem(key: 'background', label: _tr('Run in background')),
            MenuItem.separator(),
            MenuItem(key: 'exit_ui', label: _tr('Close window and tray')),
            MenuItem(
              key: 'exit_all',
              label: _tr('Exit ClosePilot and stop monitoring'),
            ),
          ],
        ),
      );

  Future<void> _resize(WindowLayout layout) async {
    if (!closePilotWindowHooksReady) return;
    await windowManager.restore();
    if (await windowManager.isMaximized()) await windowManager.unmaximize();
    await windowManager.setSize(layout.size);
    await windowManager.center();
  }

  Future<void> _exitAll() async {
    if (!controller.ready || controller.loading || _backgroundBusy) return;
    setState(() => _backgroundBusy = true);
    try {
      await controller.stopAgent();
      await _exitInterface();
    } catch (e) {
      await _showFromTray();
      _toast('${_tr('Could not stop monitor')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  Future<void> _showFromTray() async {
    if (!closePilotWindowHooksReady) return;
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  Future<void> _runInBackground() async {
    if (_backgroundBusy) return;
    if (!_trayReady || !closePilotWindowHooksReady) {
      _toast(
        _tr('System tray is unavailable. The monitor already runs separately.'),
        error: true,
      );
      return;
    }
    if (!controller.online) {
      _toast(
        _tr('The background monitor is offline. Start it first.'),
        error: true,
      );
      return;
    }
    setState(() => _backgroundBusy = true);
    try {
      await windowManager.hide();
    } catch (e) {
      _toast('${_tr('Could not hide ClosePilot')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  Future<void> _exitInterface() async {
    if (!closePilotWindowHooksReady) return;
    await windowManager.setPreventClose(false);
    try {
      await trayManager.destroy();
    } catch (_) {}
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    if (_trayReady && controller.config.minimizeToTray) {
      unawaited(windowManager.hide());
    } else {
      unawaited(_exitInterface());
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_showFromTray());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem item) {
    if (item.key == 'open') unawaited(_showFromTray());
    if (item.key == 'background') unawaited(_runInBackground());
    if (item.key == 'exit_all') unawaited(_exitAll());
    if (item.key == 'exit_ui') unawaited(_exitInterface());
  }

  @override
  void dispose() {
    if (Platform.isWindows && closePilotWindowHooksReady) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    controller.dispose();
    super.dispose();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    _messenger.currentState?.showSnackBar(
      SnackBar(
        backgroundColor: error ? const Color(0xFF6B2E39) : kSurfaceRaised,
        content: Text(message, style: const TextStyle(color: kInk)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _confirmCloseAll() async {
    if (!controller.ready || controller.loading || _backgroundBusy) return;
    if (controller.config.apps.isEmpty) {
      _toast(_tr('Add an application first.'));
      return;
    }
    final selected = controller.config.apps.map((a) => a.id).toSet();
    final confirmed = await showDialog<Set<String>>(
      context: _navigator.currentContext!,
      builder: (context) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          backgroundColor: kSurface,
          scrollable: true,
          title: Text(_tr('CLOSE ALL · Force termination')),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _tr(
                    'This closes selected applications EVEN WHEN OPEN. Unsaved work, downloads or calls may be lost.',
                  ),
                  style: TextStyle(
                    color: Color(0xFFFFA0A5),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => update(() {
                    if (selected.length == controller.config.apps.length) {
                      selected.clear();
                    } else {
                      selected.addAll(controller.config.apps.map((a) => a.id));
                    }
                  }),
                  icon: const Icon(Icons.select_all_rounded),
                  label: Text(
                    selected.length == controller.config.apps.length
                        ? _tr('Deselect all')
                        : _tr('Select all tracked apps'),
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 210),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final app in controller.config.apps)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          activeColor: kAccent,
                          value: selected.contains(app.id),
                          title: Text(
                            app.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            app.enabled
                                ? '${_tr('Watched')} · ${controller.statusFor(app.id).count} ${_tr('processes')}'
                                : _tr('Usually excluded · select explicitly'),
                            style: const TextStyle(color: kMuted, fontSize: 10),
                          ),
                          onChanged: (v) => update(() {
                            if (v == true) {
                              selected.add(app.id);
                            } else {
                              selected.remove(app.id);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(_tr('Cancel')),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF933747),
              ),
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialog, Set<String>.from(selected)),
              icon: const Icon(Icons.power_settings_new_rounded),
              label: Text('${_tr('Force close apps')} (${selected.length})'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == null || confirmed.isEmpty || !mounted) return;
    setState(() => _backgroundBusy = true);
    try {
      final result = await controller.forceCloseSelected(confirmed);
      final stopped = (result['closedProcesses'] as num?)?.toInt() ?? 0;
      final apps = (result['closedApps'] as num?)?.toInt() ?? 0;
      final failed = (result['failedProcesses'] as num?)?.toInt() ?? 0;
      _toast(
        stopped == 0 && failed == 0
            ? _tr('No selected apps were running.')
            : '${_tr('Closed processes')} $stopped · ${_tr('Apps')} $apps'
                '${failed > 0 ? " · ${_tr('Failed processes')} $failed" : ""}',
        error: failed > 0,
      );
    } catch (e) {
      _toast('${_tr('Close All failed')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _backgroundBusy = false);
    }
  }

  Future<void> _addApp() async {
    await controller.refresh();
    if (!mounted) return;
    final picked = await showDialog<(String, String)>(
      context: _navigator.currentContext!,
      builder: (dialog) => AlertDialog(
        title: Text(_tr('Add an application')),
        content: SizedBox(
            width: 440,
            height: 270,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final apps = controller.openApps
                    .where((app) =>
                        controller.validateNewRule(app.$2, app.$1) == null)
                    .toList();
                if (apps.isEmpty)
                  return Center(
                      child: Text(
                    _tr('No eligible apps with open windows. Open an app and wait a moment.'),
                    textAlign: TextAlign.center,
                  ));
                return ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final app = apps[index];
                    return ListTile(
                      leading:
                          const Icon(Icons.apps_rounded, color: kAccentBright),
                      title: Text(app.$2,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${app.$1}.exe'),
                      trailing: const Icon(Icons.add_circle_outline_rounded),
                      onTap: () => Navigator.pop(dialog, app),
                    );
                  },
                );
              },
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(_tr('Cancel'))),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await controller.addRule(picked.$2, picked.$1);
      _toast('${_tr('Added to monitoring')} · ${picked.$2}');
    } catch (e) {
      _toast('$e', error: true);
    }
  }

  Future<void> _deleteRule(AppRule rule) async {
    final confirm = await showDialog<bool>(
      context: _navigator.currentContext!,
      builder: (ctx) => AlertDialog(
        title: Text('${_tr('Remove app')} · ${rule.label}?'),
        content: Text(
          _tr(
            'Only the monitoring rule will be removed. The installed application is not affected.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_tr('Remove')),
          ),
        ],
      ),
    );
    if (confirm == true) await controller.deleteRule(rule.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => MaterialApp(
        navigatorKey: _navigator,
        scaffoldMessengerKey: _messenger,
        locale: Locale(controller.config.language),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        title: 'ClosePilot',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          fontFamily: _arabic ? 'Almarai' : 'Segoe UI',
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
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
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 930;
              return Column(
                children: [
                  if (closePilotWindowHooksReady) _titleBar(),
                  Expanded(
                    child: Row(
                      children: [
                        if (wide) _sidebar(),
                        Expanded(
                          child: Column(
                            children: [
                              if (!wide) _compactNavigation(),
                              Expanded(
                                child: _showBoot
                                    ? _bootPanel()
                                    : switch (selectedPage) {
                                        0 => _dashboard(wide),
                                        1 => _history(),
                                        _ => _settings(),
                                      },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _chooseLayout(WindowLayout layout) async {
    if (_resizing) return;
    setState(() => _resizing = true);
    try {
      await _resize(layout);
      await controller.setWindowLayout(layout);
    } catch (e) {
      _toast('${_tr('Could not resize window')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _resizing = false);
    }
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  Widget _titleBar() => Container(
        height: 40,
        color: const Color(0xFF0C171F),
        child: Row(textDirection: TextDirection.ltr, children: [
          Expanded(
              child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startDragging(),
            onDoubleTap: _toggleMaximize,
            child: const SizedBox.expand(),
          )),
          for (final (layout, icon, label) in const [
            (WindowLayout.compact, Icons.crop_square_rounded, 'Compact'),
            (WindowLayout.portrait, Icons.crop_portrait_rounded, 'Portrait'),
            (WindowLayout.standard, Icons.web_asset_rounded, 'Standard'),
            (WindowLayout.wide, Icons.crop_landscape_rounded, 'Wide'),
          ])
            _titleButton(
                icon,
                _tr(label),
                controller.ready && !controller.loading && !_resizing
                    ? () => _chooseLayout(layout)
                    : null,
                selected: controller.config.windowLayout == layout),
          const SizedBox(width: 4),
          _titleButton(Icons.remove_rounded, _tr('Minimize window'),
              windowManager.minimize),
          _titleButton(Icons.filter_none_rounded, _tr('Maximize or restore'),
              _toggleMaximize),
          _titleButton(
              Icons.close_rounded, _tr('Close window'), windowManager.close),
        ]),
      );

  Widget _titleButton(IconData icon, String label, VoidCallback? action,
          {bool selected = false}) =>
      IconButton(
        tooltip: label,
        onPressed: action,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 17),
        style: IconButton.styleFrom(
          foregroundColor: selected ? kAccentBright : kMuted,
          backgroundColor: selected ? kAccent.withValues(alpha: .16) : null,
        ),
      );

  Widget _bootPanel() => Center(
        child: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.terminal_rounded,
                    size: 34, color: kAccentBright),
                const SizedBox(height: 14),
                Text(_tr('Basel Ghanem'),
                    style: const TextStyle(
                        fontSize: 25, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                const Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('> SELECT metrics FROM windows;',
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        color: kAccentBright,
                        fontSize: 13,
                      )),
                ),
                const SizedBox(height: 14),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 800),
                  builder: (context, progress, _) => LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    color: kAccentBright,
                    backgroundColor: kSurfaceRaised,
                  ),
                ),
              ],
            )),
      );

  Widget _sidebar() => Container(
        width: 250,
        decoration: const BoxDecoration(
          color: Color(0xFF0C171F),
          border: Border(right: BorderSide(color: kBorder)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 32, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, bottom: 44),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kAccent, Color(0xFF066A70)],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Text(
                      'BG',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ClosePilot',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -.6,
                        ),
                      ),
                      Text(
                        _tr('BASEL EDITION'),
                        style: TextStyle(
                          color: kAccentBright,
                          fontSize: 9,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _navigationTile(Icons.space_dashboard_outlined, _tr('Overview'), 0),
            const SizedBox(height: 9),
            _navigationTile(Icons.history_rounded, _tr('Activity log'), 1),
            const SizedBox(height: 9),
            _navigationTile(Icons.tune_rounded, _tr('Settings'), 2),
            const Spacer(),
            _onlineCard(),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text(
                'BY BASEL  •  V$kClosePilotVersion',
                style:
                    TextStyle(color: kMuted, fontSize: 10, letterSpacing: 1.1),
              ),
            ),
          ],
        ),
      );

  Widget _compactNavigation() => Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: kBorder)),
        ),
        child: Row(
          children: [
            const Icon(Icons.blur_on_rounded, color: kAccentBright),
            const SizedBox(width: 7),
            Text(
              _tr('ClosePilot / Basel'),
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const Spacer(),
            ...[
              Icons.dashboard_outlined,
              Icons.history_outlined,
              Icons.settings_outlined,
            ].asMap().entries.map(
                  (e) => IconButton(
                    tooltip: [
                      _tr('Overview'),
                      _tr('Activity'),
                      _tr('Settings')
                    ][e.key],
                    color: selectedPage == e.key ? kAccentBright : kMuted,
                    onPressed: () => setState(() => selectedPage = e.key),
                    icon: Icon(e.value),
                  ),
                ),
          ],
        ),
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
          child: Row(
            children: [
              Icon(icon, size: 21, color: active ? kAccentBright : kMuted),
              const SizedBox(width: 14),
              Text(
                title,
                style: TextStyle(
                  color: active ? kInk : kMuted,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (active)
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: kAccentBright,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 9,
                  color: controller.online ? kAccentBright : kWarn,
                ),
                const SizedBox(width: 9),
                Text(
                  controller.loading
                      ? _tr('Connecting to monitor...')
                      : controller.online
                          ? _tr('Agent is running')
                          : _tr('Agent is offline'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              controller.loading
                  ? _tr('Getting your background engine ready.')
                  : controller.online
                      ? _tr('Monitoring runs independently of this window.')
                      : _tr(
                          'Cleanup is NOT running. Open Settings to view diagnostics.',
                        ),
              style: const TextStyle(fontSize: 11, color: kMuted, height: 1.5),
            ),
          ],
        ),
      );

  Widget _dashboard(bool wide) => ListView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 37 : 20, vertical: 32),
        children: [
          _header(
            _tr('Welcome back, Basel'),
            _tr('Your personal Windows performance control center.'),
            action: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _trayReady && controller.online ? _runInBackground : null,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
                  label: Text(_tr('Run in background')),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF8E3647),
                  ),
                  onPressed:
                      !controller.ready || controller.loading || _backgroundBusy
                          ? null
                          : _confirmCloseAll,
                  icon: const Icon(Icons.power_settings_new_rounded, size: 17),
                  label: Text(_tr('CLOSE ALL')),
                ),
                IconButton.outlined(
                  onPressed: () => controller.refresh(),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: _tr('Refresh'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 27),
          _hero(),
          const SizedBox(height: 20),
          _performancePanel(),
          if (!controller.online && !controller.loading) ...[
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFF34231C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kWarn.withValues(alpha: .55)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: kWarn),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      controller.error ??
                          _tr('Background monitor is offline. Cleanup cannot run.'),
                      style: const TextStyle(fontSize: 12, color: kInk),
                    ),
                  ),
                  TextButton(
                    onPressed: () => controller.openDataDirectory(),
                    child: Text(_tr('Diagnostics folder')),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (ctx, box) {
              final columns =
                  box.maxWidth > 850 ? 4 : (box.maxWidth > 460 ? 2 : 1);
              final spacing = 14.0;
              final width = (box.maxWidth - (columns - 1) * spacing) / columns;
              final tiles = [
                _metric(
                  Icons.layers_outlined,
                  _tr('Active processes'),
                  '${controller.processCount}',
                  _tr('Across watched applications'),
                ),
                _metric(
                  Icons.memory_outlined,
                  _tr('Observed memory'),
                  _formatMemory(controller.observedMb),
                  _tr('Working sets, not freed RAM'),
                ),
                _metric(
                  Icons.auto_awesome_outlined,
                  _tr('Auto cleanups'),
                  '${controller.automaticCleanupSessions}',
                  _tr('Completed automatic sessions'),
                ),
                _metric(
                  Icons.hourglass_top_rounded,
                  _tr('Est. time saved'),
                  controller.estimatedTimeSaved,
                  '${_tr('Estimated seconds per cleanup')} · ${controller.config.estimatedSecondsPerCleanup}',
                ),
              ];
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final tile in tiles) SizedBox(width: width, child: tile),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _savingsPanel(),
          const SizedBox(height: 33),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tr('Protected applications'),
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    SizedBox(height: 5),
                    Text(
                      _tr(
                        'Apps are only cleaned after their last visible window closes.',
                      ),
                      style: TextStyle(color: kMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed:
                    !controller.ready || controller.loading ? null : _addApp,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: Text(_tr('Add app')),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (final rule in controller.config.apps) ...[
            _appRow(rule, wide),
            const SizedBox(height: 11),
          ],
          const SizedBox(height: 13),
          _notice(),
        ],
      );

  Widget _header(String title, String subtitle, {Widget? action}) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 14,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 5),
              Text(subtitle,
                  style: const TextStyle(color: kMuted, fontSize: 13)),
            ],
          ),
          if (action != null) action,
        ],
      );

  Widget _hero() {
    final configured = controller.config.monitorEnabled;
    final active = configured && controller.online;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF153B43), Color(0xFF0D242D), Color(0xFF101D28)],
        ),
        border: Border.all(color: const Color(0xFF21636A)),
        boxShadow: [
          BoxShadow(color: kAccent.withValues(alpha: .08), blurRadius: 36),
        ],
      ),
      padding: const EdgeInsets.all(25),
      child: LayoutBuilder(
        builder: (context, limits) {
          final narrow = limits.maxWidth < 470;
          final text = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    active
                        ? Icons.verified_user_outlined
                        : Icons.pause_circle_outline,
                    size: 19,
                    color: kAccentBright,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    controller.loading
                        ? _tr('CONNECTING TO MONITOR')
                        : !controller.online
                            ? _tr('MONITOR OFFLINE')
                            : active
                                ? _tr('AUTOMATIC CLEANUP ACTIVE')
                                : _tr('AUTOMATIC CLEANUP PAUSED'),
                    style: const TextStyle(
                      color: kAccentBright,
                      letterSpacing: 1.1,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              Text(
                controller.loading
                    ? _tr('Preparing your control center...')
                    : !controller.online
                        ? _tr('Monitoring is not running.')
                        : active
                            ? _tr('Your desktop, in control.')
                            : _tr('Everything is on hold.'),
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.7,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _tr(
                  'Basel Edition • Let the monitor handle leftover background processes.',
                ),
                style: TextStyle(
                  color: Color(0xFFC0D4D9),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
            ],
          );
          final control = FilledButton.icon(
            onPressed: controller.loading
                ? null
                : () async {
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
            label: Text(
              !controller.online
                  ? _tr('Start monitor')
                  : active
                      ? _tr('Pause cleanup')
                      : _tr('Resume cleanup'),
            ),
          );
          if (narrow)
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [text, const SizedBox(height: 20), control],
            );
          return Row(
            children: [
              Expanded(child: text),
              const SizedBox(width: 18),
              control,
            ],
          );
        },
      ),
    );
  }

  Widget _savingsPanel() {
    final today = DateTime.now();
    final midnight = DateTime(today.year, today.month, today.day);
    final days = List<DateTime>.generate(
      7,
      (i) => midnight.subtract(Duration(days: 6 - i)),
    );
    final counts =
        days.map((day) => controller.cleanupByDay[day] ?? 0).toList();
    final peak = counts.fold<int>(1, (a, b) => a > b ? a : b);
    const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102E36), Color(0xFF101C26)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF2E545C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tr('Your time, reclaimed'),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 5),
                  Text(
                    _tr('Automatic cleanup sessions · last 7 days'),
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Text(
                '${controller.automaticCleanupSessions} ${_tr('automated')} · ${controller.manualAppClosures} ${_tr('manual')}',
                style: const TextStyle(
                  color: kAccentBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 104,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${counts[i]}',
                          style: const TextStyle(fontSize: 10, color: kMuted),
                        ),
                        const SizedBox(height: 6),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                          width: 28,
                          height: 7 + 52 * counts[i] / peak,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: counts[i] == 0
                                  ? [
                                      const Color(0xFF25424A),
                                      const Color(0xFF25424A),
                                    ]
                                  : [
                                      kAccentBright,
                                      kAccent.withValues(alpha: .46),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          _tr(dayLabels[days[i].weekday - 1]),
                          style: TextStyle(
                            color: i == 6 ? kAccentBright : kMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${_tr('Estimated seconds per cleanup')} · ${controller.config.estimatedSecondsPerCleanup}',
            style: const TextStyle(fontSize: 11, color: kMuted, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _performancePanel() {
    final data = controller.performance;
    final cpu = data['cpuPercent'] as num?;
    final speed = data['cpuMHz'] as num?;
    final ram = data['ramAvailableMb'] as num?;
    final total = data['ramTotalMb'] as num?;
    final disk = data['diskActivePercent'] as num?;
    final network = data['networkBytesPerSecond'] as num?;
    final gpu = data['gpuPercent'] as num?;
    String pct(num? value) => value == null ? '—' : '${value.round()}%';
    final tiles = [
      _metric(
        Icons.memory_outlined,
        _tr('Available RAM'),
        ram == null ? '—' : _formatMemory(ram.toDouble()),
        total == null || ram == null
            ? _tr('Waiting for Windows metrics')
            : '${_tr('Used')} ${_formatMemory((total - ram).clamp(0, total).toDouble())} / ${_formatMemory(total.toDouble())}',
      ),
      _metric(
        Icons.speed_outlined,
        _tr('CPU speed'),
        speed == null ? '—' : '${(speed / 1000).toStringAsFixed(2)} GHz',
        '${_tr('Used')} ${pct(cpu)} · ${_tr('Available')} ${pct(cpu == null ? null : 100 - cpu)}',
      ),
      _metric(
        Icons.storage_outlined,
        _tr('Disk activity'),
        pct(disk),
        _tr('Active time of busiest disk'),
      ),
      _metric(
        Icons.lan_outlined,
        _tr('Network'),
        network == null
            ? '—'
            : '${(network * 8 / 1000000).toStringAsFixed(2)} Mbps',
        _tr('Receive + send on busiest adapter'),
      ),
      if (gpu != null)
        _metric(
          Icons.developer_board_outlined,
          _tr('GPU activity'),
          pct(gpu),
          _tr('Busiest GPU engine'),
        ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 940
            ? tiles.length
            : (box.maxWidth >= 535 ? 3 : (box.maxWidth >= 335 ? 2 : 1));
        final width = (box.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }

  Widget _metric(IconData icon, String label, String value, String helper) =>
      Container(
        constraints: const BoxConstraints(minHeight: 140),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF172B32), Color(0xFF101C26)],
          ),
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: const Color(0xFF31525B)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: kAccentBright, size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(color: kMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              value,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              helper,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kMuted, fontSize: 10),
            ),
          ],
        ),
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
    if (!rule.enabled) return (_tr('Not monitored'), kMuted);
    if (!controller.config.monitorEnabled) return (_tr('Paused'), kWarn);
    if (status.count == 0) return (_tr('Not running'), kMuted);
    if (status.mode == 'window-open')
      return (_tr('Window open'), kAccentBright);
    if (status.mode == 'closing')
      return (
        '${_tr('Closing in')} ${status.remainingSeconds ?? 0} ${_tr('seconds')}',
        kWarn,
      );
    if (status.mode == 'background-only')
      return (_tr('Background · not armed'), kMuted);
    if (status.mode == 'cleaned')
      return (_tr('Cleanup completed'), kAccentBright);
    return (_tr('Monitoring'), kMuted);
  }

  Widget _appRow(AppRule rule, bool wide) {
    final status = controller.statusFor(rule.id);
    final mode = _modeLabel(rule, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: rule.enabled ? kBorder : const Color(0xFF1C2B35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: rule.enabled
                  ? kAccent.withValues(alpha: .13)
                  : const Color(0xFF1A2731),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _appIcon(rule.id),
              size: 24,
              color: rule.enabled ? kAccentBright : kMuted,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  rule.names.join(' / '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: kMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 9),
          if (wide) ...[
            SizedBox(
              width: 158,
              child: Row(
                children: [
                  Icon(Icons.circle, size: 7, color: mode.$2),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      mode.$1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: mode.$2, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 95,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${status.count} ${_tr('processes')}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatMemory(status.memoryMb),
                    style: const TextStyle(color: kMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 10),
          Switch(
            value: rule.enabled,
            activeThumbColor: Colors.white,
            activeTrackColor: kAccent,
            onChanged: (value) => controller.setRuleEnabled(rule.id, value),
          ),
          if (rule.removable)
            IconButton(
              onPressed: () => _deleteRule(rule),
              tooltip: _tr('Remove monitoring rule'),
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 20,
                color: kMuted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _notice() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1D242C),
          border: Border.all(color: const Color(0xFF37414C)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: kWarn, size: 19),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                _tr(
                  'Automatic mode only cleans an app after its last visible window closes. Close All is a separate immediate force-close command with explicit app selection and confirmation. Unsaved data, downloads and calls can be lost.',
                ),
                style: TextStyle(
                  color: Color(0xFFC2C9D1),
                  fontSize: 12,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _history() => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          _header(
            _tr('Activity log'),
            _tr('A local, inspectable history of all cleanup events.'),
            action: TextButton.icon(
              onPressed: () => controller.clearHistory(),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(_tr('Clear history')),
            ),
          ),
          const SizedBox(height: 24),
          if (controller.events.isEmpty)
            _emptyPanel(
              Icons.history_toggle_off_rounded,
              _tr('No events yet'),
              _tr('Open a monitored app, close its last window, and check here.'),
            ),
          for (final event in controller.events) ...[
            _eventTile(event),
            const SizedBox(height: 9),
          ],
        ],
      );

  String _arabicEvent(CleanerEvent event) {
    final kind = switch (event.kind) {
      'auto-cleanup' => 'Automatic cleanup completed',
      'manual-close-all' => 'Manual closure completed',
      'stopped' => 'Background process closed',
      'error' => 'Monitor error',
      'info' when event.message.contains('started') => 'Monitor started',
      'info' when event.message.contains('stopped') => 'Monitor stopped',
      _ => 'Monitor event',
    };
    var label = event.appId;
    for (final app in controller.config.apps) {
      if (app.id == event.appId) {
        label = app.label;
        break;
      }
    }
    return [
      _tr(kind),
      if (label.isNotEmpty) label,
      if (event.pid > 0) 'PID ${event.pid}',
      if (event.kind == 'error' || event.kind == 'warning') event.message,
    ].join(' · ');
  }

  Widget _eventTile(CleanerEvent event) {
    final stopped = event.kind == 'stopped' ||
        event.kind == 'auto-cleanup' ||
        event.kind == 'manual-close-all';
    final failed = event.kind == 'error';
    final tint = stopped
        ? kAccentBright
        : failed
            ? const Color(0xFFFF9398)
            : kMuted;
    final time = event.timestamp.toLocal();
    final dateText =
        '${time.day.toString().padLeft(2, '0')}/${time.month.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: tint.withValues(alpha: .11),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              stopped
                  ? Icons.check_circle_outline
                  : failed
                      ? Icons.error_outline
                      : Icons.info_outline,
              color: tint,
              size: 19,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _arabic ? _arabicEvent(event) : event.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (event.kind == 'stopped') ...[
                  const SizedBox(height: 4),
                  Text(
                    '${_tr('Observed memory before cleanup')} · ${_formatMemory(event.observedMb)}',
                    style: const TextStyle(color: kMuted, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(dateText, style: const TextStyle(color: kMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _emptyPanel(IconData icon, String heading, String message) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 30),
        decoration: BoxDecoration(
          color: kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBorder),
        ),
        child: Column(
          children: [
            Icon(icon, size: 40, color: kAccentBright),
            const SizedBox(height: 16),
            Text(
              heading,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kMuted, fontSize: 12),
            ),
          ],
        ),
      );

  Widget _settings() => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          _header(
              _tr('Preferences'), _tr('Set the rules that fit your workflow.')),
          const SizedBox(height: 20),
          _settingsCard(
            children: [
              _settingsOption(
                Icons.translate_rounded,
                _tr('Language'),
                _tr('Saved on this PC.'),
                DropdownButton<String>(
                  value: controller.config.language,
                  onChanged: !controller.ready || controller.loading
                      ? null
                      : (language) async {
                          if (language == null) return;
                          try {
                            await controller.setLanguage(language);
                            if (_trayReady) await _refreshTrayMenu();
                          } catch (e) {
                            _toast('$e', error: true);
                          }
                        },
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(
                      value: 'ar',
                      child: Text(
                        'العربية',
                        style: TextStyle(fontFamily: 'Almarai'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _settingsCard(
            children: [
              _settingsOption(
                Icons.system_update_alt_rounded,
                _tr('Software updates'),
                '${_tr('Current version')} v$kClosePilotVersion · ${_tr('Checks on launch only, or when you click.')}',
                FilledButton.icon(
                  onPressed: _checkingUpdates || _downloadingUpdate
                      ? null
                      : () => _checkForUpdates(),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: Text(_tr('Check for Updates')),
                ),
              ),
              if (_checkingUpdates)
                const LinearProgressIndicator(
                    color: kAccentBright, minHeight: 2),
              if (_downloadingUpdate) ...[
                LinearProgressIndicator(
                  value: _updateProgress,
                  color: kAccentBright,
                  minHeight: 4,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_tr('Downloading verified update')} ${(_updateProgress * 100).round()}%',
                  style: const TextStyle(color: kMuted, fontSize: 11),
                ),
              ],
            ],
          ),
          const SizedBox(height: 19),
          _settingsCard(
            children: [
              _settingsOption(
                Icons.power_settings_new_rounded,
                _tr('Start with Windows'),
                _tr('Launch the invisible monitor after you sign in.'),
                Switch(
                  value: controller.config.autoStart,
                  activeThumbColor: Colors.white,
                  activeTrackColor: kAccent,
                  onChanged: (v) async {
                    try {
                      await controller.setAutoStart(v);
                      _toast(
                        v
                            ? _tr('Starts automatically with Windows')
                            : _tr('Automatic startup disabled'),
                      );
                    } catch (e) {
                      _toast('${_tr('Could not update startup')}: $e',
                          error: true);
                    }
                  },
                ),
              ),
              const Divider(color: kBorder),
              _settingsOption(
                Icons.layers_clear_outlined,
                _tr('Minimize to system tray'),
                _tr(
                  'Close the window without stopping the control center. Reopen from the tray icon.',
                ),
                Switch(
                  value: controller.config.minimizeToTray,
                  activeThumbColor: Colors.white,
                  activeTrackColor: kAccent,
                  onChanged: _trayReady
                      ? (v) => controller.setMinimizeToTray(v)
                      : null,
                ),
              ),
              const Divider(color: kBorder),
              _settingsOption(
                Icons.hourglass_top_rounded,
                _tr('Time saving assumption'),
                _tr(
                  'Used ONLY for estimated time savings, not actual measured time.',
                ),
                Text(
                  '${(estimatePreview ?? controller.config.estimatedSecondsPerCleanup.toDouble()).round()}s / cleanup',
                  style: const TextStyle(
                    color: kAccentBright,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Slider(
                min: 5,
                max: 60,
                divisions: 11,
                value: estimatePreview ??
                    controller.config.estimatedSecondsPerCleanup
                        .toDouble()
                        .clamp(5, 60)
                        .toDouble(),
                activeColor: kAccentBright,
                label:
                    '${(estimatePreview ?? controller.config.estimatedSecondsPerCleanup.toDouble()).round()}s',
                onChanged: (v) => setState(() => estimatePreview = v),
                onChangeEnd: (v) async {
                  await controller.setEstimatedSecondsPerCleanup(v.round());
                  if (mounted) setState(() => estimatePreview = null);
                },
              ),
              const Divider(color: kBorder),
              _settingsOption(
                Icons.timer_outlined,
                _tr('Close delay'),
                _tr('Wait after the last window closes, allowing quick reopening.'),
                Text(
                  '${(gracePreview ?? controller.config.graceSeconds.toDouble()).round()} seconds',
                  style: const TextStyle(
                    color: kAccentBright,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Slider(
                value:
                    gracePreview ?? controller.config.graceSeconds.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                activeColor: kAccentBright,
                label:
                    '${(gracePreview ?? controller.config.graceSeconds.toDouble()).round()}s',
                onChanged: (v) => setState(() => gracePreview = v),
                onChangeEnd: (v) async {
                  await controller.setGraceSeconds(v.round());
                  if (mounted) setState(() => gracePreview = null);
                },
              ),
            ],
          ),
          const SizedBox(height: 19),
          _settingsCard(
            children: [
              _settingsOption(
                Icons.folder_open_outlined,
                _tr('Local data'),
                _tr('Configuration, monitor status and JSON activity history.'),
                OutlinedButton(
                  onPressed: () => controller.openDataDirectory(),
                  child: Text(_tr('Open folder')),
                ),
              ),
              const Divider(color: kBorder),
              _settingsOption(
                Icons.restart_alt_rounded,
                _tr('Restart monitor'),
                _tr('Reload the background engine without restarting Windows.'),
                OutlinedButton(
                  onPressed: () async {
                    await controller.restartAgent();
                    _toast(_tr('Monitor restart requested'));
                  },
                  child: Text(_tr('Restart')),
                ),
              ),
              const Divider(color: kBorder),
              _settingsOption(
                Icons.stop_circle_outlined,
                _tr('Stop monitor completely'),
                _tr(
                  'The UI stays open, but the background agent exits until restarted.',
                ),
                OutlinedButton(
                  onPressed: () async {
                    await controller.stopAgent();
                    _toast(_tr('Monitor stop requested'));
                  },
                  child: Text(_tr('Stop agent')),
                ),
              ),
              const Divider(color: kBorder),
              _settingsOption(
                Icons.play_circle_outline,
                _tr('Start monitor'),
                _tr('Run the background agent if it has been stopped.'),
                FilledButton(
                  onPressed: () async {
                    await controller.startAgent();
                    _toast(_tr('Monitor start requested'));
                  },
                  child: Text(_tr('Start agent')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _notice(),
          if (controller.error != null || controller.statusError != null) ...[
            const SizedBox(height: 16),
            Text(
              '${_tr('Diagnostic')}: ${controller.statusError ?? controller.error}',
              style: const TextStyle(color: kWarn),
            ),
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

  Widget _settingsOption(
    IconData icon,
    String title,
    String description,
    Widget trailing,
  ) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: kAccentBright, size: 23),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                      color: kMuted,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: trailing,
              ),
            ),
          ],
        ),
      );
}
