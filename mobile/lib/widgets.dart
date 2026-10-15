import 'package:flutter/material.dart';

import 'api.dart';

final messenger = GlobalKey<ScaffoldMessengerState>();

void toast(String message) {
  messenger.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Cover art with a flat placeholder while it loads or when it's missing.
class Cover extends StatelessWidget {
  const Cover(this.url, {super.key, this.radius = 16, this.fit = BoxFit.cover});

  final String url;
  final double radius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final placeholder = ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHigh);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: url.isEmpty
          ? placeholder
          : Image.network(
              url,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => placeholder,
              frameBuilder: (_, child, frame, sync) => sync || frame != null ? child : placeholder,
            ),
    );
  }
}

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.image,
    this.subtitle = '',
    this.badge = '',
    this.progress = -1,
    this.onTap,
    this.onLongPress,
  });

  final String title, image, subtitle, badge;

  /// 0..1, hidden when < 0.
  final double progress;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1 / 1.45,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Cover(image),
                if (badge.isNotEmpty)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        child: Text(badge, style: t.textTheme.labelSmall?.copyWith(color: Colors.white)),
                      ),
                    ),
                  ),
                if (progress >= 0)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: LinearProgressIndicator(value: progress, borderRadius: BorderRadius.circular(4)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
          if (subtitle.isNotEmpty)
            Text(subtitle, maxLines: 1, style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Poster grid that fits as many ~150 px columns as the width allows.
SliverGridDelegate posterGrid() => const SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 160,
  childAspectRatio: 1 / 1.95,
  crossAxisSpacing: 12,
  mainAxisSpacing: 12,
);

class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    super.key,
    required this.num,
    required this.title,
    this.filler = false,
    this.recap = false,
    this.record,
    this.current = false,
    this.onTap,
    this.onLongPress,
  });

  final int num;
  final String title;
  final bool filler, recap, current;

  /// Progress row from the history database, if any.
  final Map<String, dynamic>? record;
  final VoidCallback? onTap, onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme;
    final completed = record?['completed'] == true;
    final duration = toInt(record?['duration']);
    final fraction = duration > 0 ? toInt(record?['playback_time']) / duration : 0.0;
    return Material(
      color: current ? c.secondaryContainer : c.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: completed ? c.primary : c.surfaceContainerHighest,
                foregroundColor: completed ? c.onPrimary : c.onSurface,
                child: completed ? const Icon(Icons.check_rounded) : Text('$num'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title.isEmpty ? 'Episode $num' : title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.titleSmall,
                          ),
                        ),
                        if (filler || recap) ...[
                          const SizedBox(width: 6),
                          Text(recap ? 'RECAP' : 'FILLER', style: t.textTheme.labelSmall?.copyWith(color: c.tertiary)),
                        ],
                      ],
                    ),
                    Text(
                      completed ? 'Watched' : (current ? 'Up next' : 'Episode $num'),
                      style: t.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                    ),
                    if (!completed && fraction > 0) ...[
                      const SizedBox(height: 4),
                      LinearProgressIndicator(value: fraction, borderRadius: BorderRadius.circular(4)),
                    ],
                  ],
                ),
              ),
              if (!completed && fraction > 0) ...[
                const SizedBox(width: 8),
                Text('${(fraction * 100).round()}%', style: t.textTheme.labelSmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.face,
    required this.title,
    required this.message,
    this.details = '',
    this.error = false,
    this.action,
  });

  final String face, title, message, details;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(face, style: t.textTheme.displaySmall?.copyWith(color: error ? t.colorScheme.error : t.colorScheme.primary)),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              details,
              textAlign: TextAlign.center,
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Bottom sheet listing choices with a check on the current one.
Future<T?> pickFrom<T>(BuildContext context, String header, List<(String label, T value, bool checked)> items) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(header, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final (label, value, checked) in items)
            ListTile(
              title: Text(label),
              trailing: checked ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    ),
  );
}
