import 'package:aikatsu/theme.dart';
import 'package:aikatsu/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('poster text stays inside the clip in ${brightness.name} mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(brightness),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 128,
                height: 240,
                child: PosterCard(title: 'A long anime title that wraps', image: '', subtitle: 'Episode 12 / 24'),
              ),
            ),
          ),
        ),
      );

      final card = find.byType(PosterCard);
      final material = find.descendant(of: card, matching: find.byType(Material));
      final widget = tester.widget<Material>(material);
      final clip = widget.borderRadius!.resolve(TextDirection.ltr).toRRect(tester.getRect(material));
      for (final label in ['A long anime title that wraps', 'Episode 12 / 24']) {
        final rect = tester.getRect(find.text(label)).deflate(0.1);
        for (final point in [rect.topLeft, rect.topRight, rect.bottomLeft, rect.bottomRight]) {
          expect(clip.contains(point), isTrue, reason: '$label must fit inside the card clip');
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
