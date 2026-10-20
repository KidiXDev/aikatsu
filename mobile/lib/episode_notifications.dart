import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'api.dart';

/// "Episode N is out" for watching and planned shows, at AniList's airing time.
/// They're alarms scheduled ahead, so they show while the app is closed; the
/// next two weeks are scheduled again on start, sync and watchlist changes.
abstract final class EpisodeNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _firstId = 100000; // below are download notifications
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'episodes',
      'New episodes',
      channelDescription: 'Shows on your watchlist as they air',
      icon: 'ic_stat_episode',
      color: Color(0xffb22466),
    ),
  );
  static bool _askedPermission = false;
  static String _scheduled = '';
  static Future<void> _pending = Future.value();

  /// The series key of a tapped notification, for the app to open.
  static final opened = ValueNotifier<String?>(null);

  static Future<void> init() async {
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) opened.value = launch?.notificationResponse?.payload;
    Api.historyRevision.addListener(_reschedule);
    Api.settingChanged.listen((s) {
      if (s.$1 == 'airingAlerts') _reschedule();
    });
    _reschedule();
  }

  static void _reschedule() {
    _pending = _pending.then((_) => _schedule()).catchError((Object error, StackTrace stack) {
      debugPrint('Episode notifications failed: $error');
    });
  }

  static Future<void> _schedule() async {
    final episodes = Api.setting('airingAlerts') == 'true' ? await Api.call('upcomingEpisodes') as List : const [];
    final scheduled = jsonEncode(episodes);
    if (scheduled == _scheduled) return;
    _scheduled = scheduled;
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id >= _firstId) await _plugin.cancel(id: p.id);
    }
    if (episodes.isNotEmpty && !_askedPermission) {
      _askedPermission = true;
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    }
    for (final (i, e) in episodes.indexed) {
      await _plugin.zonedSchedule(
        id: _firstId + i,
        title: '${e['title']}',
        body: 'Episode ${e['episode']} is out',
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, toInt(e['airing_at']) * 1000),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: '${e['key']}',
      );
    }
  }
}
