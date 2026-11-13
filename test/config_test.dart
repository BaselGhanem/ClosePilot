import 'package:close_pilot/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Safe defaults: interactive apps enabled and downloads/calls disabled',
    () {
      final config = MonitorConfig.initial();
      expect(config.monitorEnabled, isTrue);
      expect(config.apps.firstWhere((e) => e.id == 'claude').enabled, isTrue);
      expect(config.apps.firstWhere((e) => e.id == 'chrome').enabled, isTrue);
      expect(config.apps.firstWhere((e) => e.id == 'steam').enabled, isFalse);
      expect(config.apps.firstWhere((e) => e.id == 'teams').enabled, isFalse);
    },
  );

  test('Configuration serialization preserves selected applications', () {
    final config = MonitorConfig.initial().copyWith(graceSeconds: 45);
    final decoded = MonitorConfig.fromJson(config.toJson());
    expect(decoded.graceSeconds, 45);
    expect(decoded.apps.length, config.apps.length);
  });

  test('Unsafe processes and duplicates are rejected', () {
    final c = ClosePilotController();
    expect(c.validateNewRule('System service', 'svchost'), isNotNull);
    expect(c.validateNewRule('Duplicate', 'chrome.exe'), isNotNull);
    expect(c.validateNewRule('Text editor', 'notepad.exe'), isNull);
    expect(
      c.validateNewRule('Custom', 'App With Spaces.exe،Example.App'),
      isNull,
    );
    expect(c.validateNewRule('Invalid', 'app*'), isNotNull);
    expect(c.validateNewRule('Protected', 'ClosePilot.exe'), isNotNull);
    c.dispose();
  });
  test('Basel Edition settings round-trip for tray and estimated time', () {
    final original = MonitorConfig.initial().copyWith(
      minimizeToTray: false,
      estimatedSecondsPerCleanup: 45,
    );
    final restored = MonitorConfig.fromJson(original.toJson());
    expect(restored.minimizeToTray, isFalse);
    expect(restored.estimatedSecondsPerCleanup, 45);
    final legacy = MonitorConfig.initial().toJson()
      ..remove('minimizeToTray')
      ..remove('estimatedSecondsPerCleanup')
      ..remove('language')
      ..remove('windowLayout');
    final upgraded = MonitorConfig.fromJson(legacy);
    expect(upgraded.minimizeToTray, isTrue);
    expect(upgraded.language, 'en');
    expect(upgraded.windowLayout, WindowLayout.standard);
    expect(upgraded.estimatedSecondsPerCleanup, 20);
  });

  test('Time saved is explicitly an estimate per completed app cleanup', () {
    final c = ClosePilotController();
    c.automaticCleanupSessions = 3;
    expect(c.estimatedSecondsSaved, 60);
    expect(c.estimatedTimeSaved, '1.0 min');
    c.config = c.config.copyWith(estimatedSecondsPerCleanup: 40);
    expect(c.estimatedSecondsSaved, 120);
    expect(c.estimatedTimeSaved, '2.0 min');
    c.dispose();
  });
}
