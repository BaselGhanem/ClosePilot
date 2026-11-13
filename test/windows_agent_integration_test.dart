import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Flutter controller launches Windows background monitor and receives heartbeat', () async {
    if (!Platform.isWindows) return;

    final controller = ClosePilotController();
    try {
      await controller.initialize();
      final root = Directory(
        '${Platform.environment['LOCALAPPDATA']}\\ClosePilot',
      );
      print(
        'AGENT DEBUG: root=${root.path}; online=${controller.online}; error=${controller.error}',
      );
      if (await root.exists()) {
        final files = await root.list().toList();
        print(
          'AGENT DEBUG: files=${files.map((f) => f.path.split('\\').last).toList()}',
        );
        for (final name in [
          'agent-entry.log',
          'agent-fatal.log',
          'ui-diagnostics.log',
          'events.jsonl',
          'status.json',
        ]) {
          final f = File('${root.path}\\$name');
          if (await f.exists()) {
            final lines = await f.readAsLines();
            print(
              'AGENT DEBUG $name: ${lines.skip(lines.length > 30 ? lines.length - 30 : 0).join(' | ')}',
            );
          }
        }
      }
      expect(
        controller.error,
        isNull,
        reason: 'Startup failed. Review %LOCALAPPDATA%\\ClosePilot\\ui-diagnostics.log',
      );
      expect(
        controller.online,
        isTrue,
        reason: 'Agent heartbeat missing. The app cannot claim that monitoring is active.',
      );
      await controller.addRule('ClosePilot test process', 'ping.exe');
      final app = controller.config.apps.last;
      final ping = await Process.start('ping.exe', ['-t', '127.0.0.1']);
      try {
        final result = await controller.forceCloseSelected({app.id});
        expect(result['closedProcesses'], greaterThan(0));
        await ping.exitCode.timeout(const Duration(seconds: 5));
      } finally {
        ping.kill();
        await controller.deleteRule(app.id);
      }

      await controller.setLanguage('ar');
      await controller.setWindowLayout(WindowLayout.portrait);
      final configFile = File('${root.path}\\config.json');
      final restored = MonitorConfig.fromJson(
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>,
      );
      expect(restored.language, 'ar');
      expect(restored.windowLayout, WindowLayout.portrait);

      final timeout = DateTime.now().add(const Duration(seconds: 25));
      while (controller.performance['ramTotalMb'] == null &&
          DateTime.now().isBefore(timeout)) {
        await Future<void>.delayed(const Duration(seconds: 2));
        await controller.refresh();
      }
      expect(controller.performance['ramTotalMb'], greaterThan(0));
      expect(controller.performance['ramAvailableMb'], greaterThan(0));
      final statusFile = File(
        '${Platform.environment['LOCALAPPDATA']}\\ClosePilot\\status.json',
      );
      expect(await statusFile.exists(), isTrue);
      final raw = await statusFile.readAsString();
      expect(raw, contains('updatedAt'));
    } finally {
      await controller.stopAgent();
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
