import 'package:aikatsu/api.dart';
import 'package:aikatsu/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatTime', () {
    expect(formatTime(0), '0:00');
    expect(formatTime(309.9), '5:09');
    expect(formatTime(3909), '1:05:09');
    expect(formatTime(-4), '0:00');
    expect(formatTime(double.nan), '0:00');
  });

  test('describe', () {
    expect(Api.describe('operation timed out'), 'The site took too long to answer.');
    expect(Api.describe('HTTP error 403 Forbidden'), 'The site refused the request. Try again in a minute.');
    expect(Api.describe('no playable server found'), 'No working stream was found for this episode.');
    expect(Api.describe(null), 'Something went wrong.');
    expect(Api.describe('Could not initialize video chain.'), "This video's format can't play on this device.");
    expect(Api.describe('archcele is offline: client error (Connect)'), 'archcele is offline. Open Aikatsu there and try again.');
    expect(Api.describe("archcele can't be reached: operation timed out"), "Can't reach archcele. Check its firewall and that you're on the same network.");
  });

  test('airingLabel', () {
    final now = DateTime(2026, 10, 15, 20, 0);
    int at(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
    expect(airingLabel(at(DateTime(2026, 10, 15, 19, 15)), now), '45m ago');
    expect(airingLabel(at(DateTime(2026, 10, 15, 19, 59, 50)), now), '1m ago');
    expect(airingLabel(at(DateTime(2026, 10, 15, 17, 0)), now), '3h ago');
    expect(airingLabel(at(DateTime(2026, 10, 15, 21, 30)), now), '21:30');
    expect(airingLabel(at(DateTime(2026, 10, 16, 8, 5)), now), 'Tomorrow 08:05');
  });

  test('prettyEnum', () {
    expect(prettyEnum('TV'), 'TV');
    expect(prettyEnum('TV_SHORT'), 'TV Short');
    expect(prettyEnum('NOT_YET_RELEASED'), 'Not Yet Released');
    expect(prettyEnum('Finished Airing'), 'Finished Airing');
    expect(prettyEnum(''), '');
  });

  test('airsIn', () {
    final now = DateTime(2026, 10, 15, 20, 0);
    int at(Duration d) => now.add(d).millisecondsSinceEpoch ~/ 1000;
    expect(airsIn(at(const Duration(days: 2, hours: 3, minutes: 9)), now), '2d 3h');
    expect(airsIn(at(const Duration(hours: 3, minutes: 5)), now), '3h 5m');
    expect(airsIn(at(const Duration(seconds: 20)), now), '1m');
    expect(airsIn(at(const Duration(minutes: -1)), now), '');
  });

  test('formatCount', () {
    expect(formatCount(0), '0');
    expect(formatCount(999), '999');
    expect(formatCount(1000), '1,000');
    expect(formatCount(320000), '320,000');
    expect(formatCount(1234567), '1,234,567');
  });

  test('text picks the first non-empty string', () {
    expect(text([null, '', 'b', 'c']), 'b');
    expect(text([null, 3]), '');
  });
}
