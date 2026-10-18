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

  test('text picks the first non-empty string', () {
    expect(text([null, '', 'b', 'c']), 'b');
    expect(text([null, 3]), '');
  });
}
