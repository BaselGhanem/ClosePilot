import 'package:close_pilot/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Strict semantic version ordering', () {
    expect(UpdateService.compareVersions('v1.2.0', '1.1.0'), greaterThan(0));
    expect(UpdateService.compareVersions('v1.2.0', '1.2.0'), 0);
    expect(UpdateService.compareVersions('1.2.10', '1.2.9'), greaterThan(0));
    expect(UpdateService.compareVersions('v2.0.0', '1.99.99'), greaterThan(0));
    expect(UpdateService.compareVersions('1.0.0', 'v1.0.1'), lessThan(0));
  });

  test('Reject unsupported or unexpected release tags', () {
    expect(() => UpdateService.compareVersions('nightly', '1.0.0'), throwsFormatException);
    expect(() => UpdateService.compareVersions('v1.2.0-beta', '1.0.0'), throwsFormatException);
    expect(() => UpdateService.compareVersions('1.2', '1.0.0'), throwsFormatException);
  });

  test('Updater reads releases from the SAME public GitHub repository', () {
    expect(kReleaseRepository, 'BaselGhanem/ClosePilot');
    expect(kClosePilotVersion, '1.3.3');
  });
}
