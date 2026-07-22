import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

@immutable
class AppVersionInfo {
  const AppVersionInfo({
    required this.appName,
    required this.packageName,
    required this.version,
    required this.buildNumber,
  });

  final String appName;
  final String packageName;
  final String version;
  final String buildNumber;

  String get identity => '$version+$buildNumber';
  String get displayLabel => '$version (build $buildNumber)';
}

class AppVersionService {
  const AppVersionService();

  Future<AppVersionInfo> load() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return AppVersionInfo(
      appName: packageInfo.appName,
      packageName: packageInfo.packageName,
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
    );
  }
}
