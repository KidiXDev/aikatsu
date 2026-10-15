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
  });

  test('text picks the first non-empty string', () {
    expect(text([null, '', 'b', 'c']), 'b');
    expect(text([null, 3]), '');
  });
}
