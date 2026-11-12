import 'package:close_pilot/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Safe defaults: interactive apps enabled and downloads/calls disabled', () {
    final config = MonitorConfig.initial();
    expect(config.monitorEnabled, isTrue);
    expect(config.apps.firstWhere((e) => e.id == 'claude').enabled, isTrue);
    expect(config.apps.firstWhere((e) => e.id == 'chrome').enabled, isTrue);
    expect(config.apps.firstWhere((e) => e.id == 'steam').enabled, isFalse);
    expect(config.apps.firstWhere((e) => e.id == 'teams').enabled, isFalse);
  });

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
    c.dispose();
  });
}
