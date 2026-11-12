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
      final root = Directory('${Platform.environment['LOCALAPPDATA']}\\ClosePilot');
      print('AGENT DEBUG: root=${root.path}; online=${controller.online}; error=${controller.error}');
      if (await root.exists()) {
        final files = await root.list().toList();
        print('AGENT DEBUG: files=${files.map((f) => f.path.split('\\').last).toList()}');
        for (final name in ['agent-entry.log', 'agent-fatal.log', 'ui-diagnostics.log', 'events.jsonl', 'status.json']) {
          final f = File('${root.path}\\$name');
          if (await f.exists()) {
            final lines = await f.readAsLines();
            print('AGENT DEBUG $name: ${lines.skip(lines.length > 30 ? lines.length - 30 : 0).join(' | ')}');
          }
        }
      }
      expect(controller.error, isNull,
          reason: 'Startup failed. Review %LOCALAPPDATA%\\ClosePilot\\ui-diagnostics.log');
      expect(controller.online, isTrue,
          reason: 'Agent heartbeat missing. The app cannot claim that monitoring is active.');
      final statusFile = File('${Platform.environment['LOCALAPPDATA']}\\ClosePilot\\status.json');
      expect(await statusFile.exists(), isTrue);
      final raw = await statusFile.readAsString();
      expect(raw, contains('updatedAt'));
    } finally {
      await controller.stopAgent();
      controller.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
