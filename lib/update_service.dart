import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// The version of the currently installed binary. Bump with pubspec.yaml.
const String kClosePilotVersion = '1.2.0';
const String kReleaseRepository = 'BaselGhanem/ClosePilot-Releases';

class ClosePilotRelease {
  const ClosePilotRelease({
    required this.version,
    required this.tag,
    required this.notes,
    required this.archiveUrl,
    required this.checksumUrl,
    this.assetDigest,
  });

  final String version;
  final String tag;
  final String notes;
  final Uri archiveUrl;
  final Uri checksumUrl;
  final String? assetDigest;
}

class UpdateService {
  const UpdateService();

  static int compareVersions(String a, String b) {
    final parsedA = _parseVersion(a);
    final parsedB = _parseVersion(b);
    for (var i = 0; i < 3; i++) {
      final comparison = parsedA[i].compareTo(parsedB[i]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  static List<int> _parseVersion(String version) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(version);
    if (match == null) throw FormatException('Unsupported version: $version');
    return [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
  }

  static Uri _verifiedAssetUrl(Object? value) {
    if (value is! String) throw const FormatException('Release URL missing.');
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        !uri.path.startsWith('/$kReleaseRepository/releases/download/')) {
      throw const FormatException('Unexpected release asset URL.');
    }
    return uri;
  }

  Future<ClosePilotRelease?> checkForUpdate() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 7);
    try {
      final url = Uri.https('api.github.com',
          '/repos/$kReleaseRepository/releases/latest');
      final request = await client.getUrl(url).timeout(const Duration(seconds: 10));
      request.headers.set(HttpHeaders.userAgentHeader, 'ClosePilot/$kClosePilotVersion');
      request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final response = await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode == 404) {
        throw StateError('No public ClosePilot release has been published yet.');
      }
      if (response.statusCode != 200) {
        throw HttpException('GitHub returned HTTP ${response.statusCode}', uri: url);
      }
      final payload = await utf8.decoder.bind(response).join()
          .timeout(const Duration(seconds: 12));
      final result = jsonDecode(payload) as Map<String, dynamic>;
      final tag = result['tag_name'];
      if (tag is! String) throw const FormatException('Release tag missing.');
      final newer = compareVersions(tag, kClosePilotVersion);
      if (newer <= 0) return null;

      final assets = (result['assets'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList();
      Map<String, dynamic> locate(String filename) => assets.firstWhere(
            (a) => a['name'] == filename,
            orElse: () => throw FormatException(
                'Release $tag is missing $filename.'),
          );
      final zipAsset = locate('ClosePilot-Windows.zip');
      final checksumAsset = locate('ClosePilot-Windows.zip.sha256');
      String? expectedDigest;
      final digestValue = zipAsset['digest'];
      if (digestValue is String && digestValue.startsWith('sha256:')) {
        expectedDigest = digestValue.substring(7).toLowerCase();
      }

      return ClosePilotRelease(
        version: tag.replaceFirst(RegExp('^v'), ''),
        tag: tag,
        notes: (result['body'] as String? ?? '').trim(),
        archiveUrl: _verifiedAssetUrl(zipAsset['browser_download_url']),
        checksumUrl: _verifiedAssetUrl(checksumAsset['browser_download_url']),
        assetDigest: expectedDigest,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<File> downloadVerified(
    ClosePilotRelease release, {
    required void Function(double) onProgress,
  }) async {
    final appData = Platform.environment['LOCALAPPDATA'];
    if (appData == null || appData.isEmpty) {
      throw StateError('Windows LOCALAPPDATA is unavailable.');
    }
    final target = Directory('$appData\\ClosePilot\\updates');
    await target.create(recursive: true);
    final checksumBytes = await _getBytes(release.checksumUrl, maxBytes: 1024);
    final checksumString = utf8.decode(checksumBytes).trim();
    final match = RegExp(r'^([a-fA-F0-9]{64})(?:\s|$)').firstMatch(checksumString);
    if (match == null) throw const FormatException('Invalid release SHA-256 checksum.');
    final expected = match.group(1)!.toLowerCase();
    if (release.assetDigest != null && release.assetDigest != expected) {
      throw const FormatException('GitHub asset digest differs from checksum file.');
    }
    final archive = File('${target.path}\\ClosePilot-${release.version}.zip');
    final partial = File('${archive.path}.part');
    if (await partial.exists()) await partial.delete();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(release.archiveUrl)
          .timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, 'ClosePilot/$kClosePilotVersion');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw HttpException('Download failed: HTTP ${response.statusCode}');
      }
      final declared = response.contentLength;
      const maximumArchiveBytes = 250 * 1024 * 1024;
      if (declared > maximumArchiveBytes) {
        throw StateError('Update archive exceeds maximum supported size.');
      }
      var received = 0;
      final sink = partial.openWrite();
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 60))) {
          received += chunk.length;
          if (received > maximumArchiveBytes) {
            throw StateError('Update archive exceeds maximum supported size.');
          }
          sink.add(chunk);
          if (declared > 0) onProgress((received / declared).clamp(0.0, 1.0));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      final digest = (await sha256.bind(partial.openRead()).first).toString();
      if (digest != expected) {
        throw const FormatException('SHA-256 mismatch. Update rejected.');
      }
      if (await archive.exists()) await archive.delete();
      await partial.rename(archive.path);
      onProgress(1.0);
      return archive;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  Future<List<int>> _getBytes(Uri uri, {required int maxBytes}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.userAgentHeader, 'ClosePilot/$kClosePilotVersion');
      final response = await request.close().timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw HttpException('Could not fetch checksum: HTTP ${response.statusCode}');
      }
      final chunks = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        if (chunks.length + chunk.length > maxBytes) {
          throw const FormatException('Oversized checksum file.');
        }
        chunks.addAll(chunk);
      }
      return chunks;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> prepareInstallation(ClosePilotRelease release, File archive) async {
    final appData = Platform.environment['LOCALAPPDATA'];
    if (appData == null || appData.isEmpty) throw StateError('LOCALAPPDATA missing.');
    final home = Directory('$appData\\ClosePilot');
    await home.create(recursive: true);
    final executable = File(Platform.resolvedExecutable);
    if (executable.uri.pathSegments.last.toLowerCase() != 'closepilot.exe') {
      throw StateError('Updater requires the packaged ClosePilot.exe application.');
    }
    if (!await archive.exists()) throw StateError('Downloaded update is missing.');
    final request = File('${home.path}\\update-request.json');
    final temp = File('${home.path}\\update-request.tmp');
    final document = <String, dynamic>{
      'pid': pid,
      'installDir': executable.parent.path,
      'archive': archive.path,
      'version': release.version,
      'requestedAt': DateTime.now().toIso8601String(),
    };
    await temp.writeAsString(jsonEncode(document), flush: true);
    if (await request.exists()) await request.delete();
    await temp.rename(request.path);
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      '${home.path}\\ClosePilot-Setup.ps1',
      '-Action',
      'start-updater',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Could not launch updater: ${result.stderr}');
    }
  }
}
