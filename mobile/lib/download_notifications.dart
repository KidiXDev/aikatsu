import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'pages/downloads.dart';

/// Download progress in the notification shade, like any download app.
///
/// While anything downloads, the progress notification belongs to a foreground
/// service: that keeps Android from killing the app in the background, and the
/// core's downloads run inside it. Swiping the app away still ends both
/// (`stopWithTask` in AndroidManifest.xml), since only the open app can keep the
/// notification current.
abstract final class DownloadNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  static const _progressId = 1; // the service's notification; finished episodes use 1000 + job id
  static final _active = <int, Map<String, dynamic>>{}; // job id → job, while queued..downloading
  static bool _serviceRunning = false, _askedPermission = false;
  static DateTime _lastShown = DateTime(0);

  /// Bumped when a download notification is tapped, so the app can open Downloads.
  static final tapped = ValueNotifier(0);

  static Future<void> init() async {
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_download')),
      onDidReceiveNotificationResponse: (_) => tapped.value++,
    );
    Api.pushed.listen((event) {
      if (event.$1 == 'download') _onJob(event.$2);
    });
  }

  static NotificationDetails _details({bool ongoing = false, int? progress, bool indeterminate = false}) => NotificationDetails(
    android: AndroidNotificationDetails(
      'downloads',
      'Downloads',
      channelDescription: 'Episode download progress',
      icon: 'ic_stat_download',
      color: const Color(0xffb22466),
      importance: Importance.low, // in the shade, no sound or pop-up
      priority: Priority.low,
      category: AndroidNotificationCategory.progress,
      onlyAlertOnce: true,
      showWhen: false,
      ongoing: ongoing,
      autoCancel: !ongoing,
      showProgress: progress != null || indeterminate,
      maxProgress: 1000,
      progress: progress ?? 0,
      indeterminate: indeterminate,
    ),
  );

  static String _name(Map<String, dynamic> j) => '${j['title']} · Episode ${j['episode']}';

  static void _onJob(Map<String, dynamic> job) {
    final id = job['id'] as int, state = job['state'] as String;
    final before = _active[id]?['state'];
    if (activeDownloadStates.contains(state)) {
      _active[id] = job;
      _refresh(force: before != state); // progress ticks are throttled, state changes aren't
      return;
    }
    _active.remove(id);
    if (before != null && (state == 'done' || state == 'failed')) {
      _plugin.show(
        id: 1000 + id,
        title: state == 'done' ? 'Downloaded' : 'Download failed',
        body: state == 'done' ? _name(job) : '${_name(job)}\n${downloadStatus(job)}',
        notificationDetails: _details(),
      );
    }
    _refresh(force: true);
  }

  /// One notification for everything in flight: the episode downloading now,
  /// how many others wait, and the combined progress of what has a known size.
  static Future<void> _refresh({bool force = false}) async {
    if (_active.isEmpty) {
      if (_serviceRunning) {
        _serviceRunning = false;
        await _android?.stopForegroundService();
      }
      return;
    }
    // Android drops notification updates that come faster than this.
    final now = DateTime.now();
    if (!force && now.difference(_lastShown) < const Duration(seconds: 1)) return;
    _lastShown = now;

    final jobs = _active.values.toList();
    final current = jobs.firstWhere((j) => j['state'] == 'downloading', orElse: () => jobs.first);
    final sized = jobs.where((j) => j['state'] == 'downloading' && toInt(j['total']) > 0);
    final total = sized.fold(0, (sum, j) => sum + toInt(j['total']));
    final done = sized.fold(0, (sum, j) => sum + toInt(j['bytes']));
    final title = jobs.length == 1 ? _name(current) : 'Downloading ${jobs.length} episodes';
    final body = jobs.length == 1 ? downloadStatus(current) : '${_name(current)} and ${jobs.length - 1} more';
    final details = _details(ongoing: true, progress: total > 0 ? done * 1000 ~/ total : null, indeterminate: total == 0);

    if (_serviceRunning) {
      await _plugin.show(id: _progressId, title: title, body: body, notificationDetails: details);
      return;
    }
    _serviceRunning = true;
    if (!_askedPermission) {
      _askedPermission = true;
      await _android?.requestNotificationsPermission(); // Android 13+; downloads run either way
    }
    await _android?.startForegroundService(
      id: _progressId,
      title: title,
      body: body,
      notificationDetails: details.android,
      startType: AndroidServiceStartType.startNotSticky, // a restart without the app couldn't update it
      foregroundServiceTypes: {AndroidServiceForegroundType.foregroundServiceTypeDataSync},
    );
  }
}
