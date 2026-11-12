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
