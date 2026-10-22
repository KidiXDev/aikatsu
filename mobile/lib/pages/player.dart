import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../api.dart';
import '../playback_stats.dart';
import '../theme.dart';
import '../widgets.dart';
import 'anime.dart';

enum _Phase { resolving, playing, error, ended }

/// desktop/qml/pages/PlayerPage.qml on media_kit (also libmpv): the same
/// quality fallback, resume, skip OP/ED, autoplay countdown and Anime4K.
/// Opens immediately; series details can land after playback has started.
/// An episode counts as watched at 90 %.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.data, required this.index});

  final AnimeData data;
  final int index;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  // Desktop uses 300 MiB; phones have less memory to spare. libass draws each file's own subtitle styles, like the
  // desktop; it can't see Android's fonts, so the app font covers subtitles that don't embed theirs.
  final _player = Player(
    configuration: const PlayerConfiguration(
      bufferSize: 150 << 20,
      libass: true,
      libassAndroidFont: 'assets/fonts/GoogleSansFlex.ttf',
      libassAndroidFontName: 'Google Sans Flex',
    ),
  );
  VideoController? _video; // after the emulator check in _setup
  bool _emulator = false;
  final _scaffold = GlobalKey<ScaffoldState>();
  final _subs = <StreamSubscription<Object?>>[];
  late final AppLifecycleListener _lifecycle;
  static const _audio = MethodChannel('io.github.kidixdev.aikatsu/audio'); // "noisy": headphones unplugged
  static const _pip = MethodChannel('io.github.kidixdev.aikatsu/pip'); // picture-in-picture on leaving the app
  bool _inPip = false;
  String _pipSent = '';

  late int _index = widget.index;
  late final String _source = Api.sourceName(d.anime['source']);
  String get _sourceName => _isLocal ? 'Downloaded' : _source;

  _Phase _phase = _Phase.resolving;
  String _status = 'Starting the player…'; // what the loading screen waits on
  bool _slow = false; // status unchanged for a while
  bool _started = false; // first frame of this episode is on screen
  bool _loaded = false; // the file from the latest open is in (ignores the old file's events)
  bool _opening = false; // inside media_kit's open(), which stops the old file first
  bool _resumed = false; // this load seeks to the saved position
  bool _hadMeta = false;
  String _errorText = '';
  String _lastError = ''; // mpv's last error log line, e.g. "HTTP error 403 Forbidden"
  List<String> _qualities = []; // offered for this episode, highest first
  List<String> _tried = []; // qualities already attempted for this episode
  int _reconnects = 0;
  String _quality = ''; // label actually requested from the source
  String _preferredQuality = Api.setting('quality');
  double _startAt = -1; // seek here on load without the resume prompt
  double _lastPos = 0; // last real position; mpv drops it on errors
  Map<String, dynamic> _skip = {};
  double _resumeAt = 0;
  bool _resumePrompt = false;
  bool _completedMarked = false, _skippedOp = false, _skippedEd = false;
  int _countdownLeft = 0;
  int _request = 0; // bumped per lookup; stale answers are dropped
  String _anime4k = Api.setting('anime4k');
  bool _downloadingShaders = false;
  final List<dynamic> _anime4kModes = Api.get('anime4kModes');
  final bool _autoplay = Api.setting('autoplay') == 'true';
  final bool _autoSkip = Api.setting('autoSkip') == 'true';
  double _subScale = double.tryParse(Api.setting('subtitleScale')) ?? 1;
  double _subDelay = 0; // per episode: each file is timed on its own
  bool _timing = false; // the subtitle timing bar is open
  bool _controlsVisible = true;
  bool _showStats = false;
  final bool _developerMode = Api.setting('developerMode') == 'true';
  double? _dragValue; // seek bar position while dragging
  (IconData, String)? _osd;
  Timer? _hideTimer, _slowTimer, _resumeHide, _countdown, _osdTimer, _saveTimer;

  AnimeData get d => widget.data;
  Map<String, dynamic> get _ep => d.episodes[_index];

  /// This episode is downloaded: it plays from the file, no source lookups.
  String? get _localFile => d.localFiles[_ep['url']];
  bool get _isLocal => _localFile != null;
  Map<String, dynamic> get _meta => d.meta ?? const {};
  bool get _hasNext => _index + 1 < d.episodes.length;
  bool get _hasPrev => _index > 0;
  double get _position => _player.state.position.inMilliseconds / 1000;
  double get _duration => _player.state.duration.inMilliseconds / 1000;
  List<int>? _segment(String key) => (_skip[key] as List?)?.map(toInt).toList();
  bool _inSegment(String key) {
    final s = _segment(key);
    return s != null && _position >= s[0] && _position < s[1] - 1;
  }

  bool get _inOp => _inSegment('op');
  bool get _inEd => _inSegment('ed');
  bool get _showControls => _controlsVisible || !_player.state.playing || _phase != _Phase.playing || !_started;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _hadMeta = d.metaLoaded;
    d.addListener(_dataChanged);
    final s = _player.stream;
    _subs.addAll([
      s.position.listen(_onPosition),
      s.duration.listen(_onDuration),
      s.completed.listen((done) {
        if (done) _onEof();
      }),
      s.error.listen((e) {
        _lastError = e;
        _checkFailed();
      }),
      // mpv's errors (media_kit's default log level) in logcat, like the desktop's console.
      s.log.listen((l) {
        debugPrint('mpv ${l.level} [${l.prefix}] ${l.text}');
        // mpv keeps playing audio and subtitles over no picture, and media_kit only reports error-level lines.
        if (l.prefix == 'cplayer' && l.text.startsWith('Could not initialize video chain') && _phase == _Phase.playing) {
          _stopFile();
          _fail(l.text);
        }
      }),
      s.buffering.listen(_refresh),
      s.playing.listen(_refresh),
      s.tracks.listen(_refresh),
      s.track.listen(_refresh),
      s.rate.listen(_refresh),
      s.width.listen(_refresh),
      s.height.listen(_refresh),
      Api.pushed.listen((e) {
        if (e.$1 != 'anime4k' || !mounted) return;
        _downloadingShaders = true;
        _showOsd(Icons.auto_awesome_rounded, 'Downloading Anime4K… ${(e.$2['progress'] * 100).round()}%');
      }),
    ]);
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_phase == _Phase.playing && _player.state.playing && _duration > 0) _save();
    });
    _lifecycle = AppLifecycleListener(onHide: _pause);
    _audio.setMethodCallHandler((call) async {
      if (call.method == 'noisy') _pause();
    });
    _pip.setMethodCallHandler((call) async {
      if (call.method == 'changed' && mounted) setState(() => _inPip = call.arguments == true);
    });
    _setup();
  }

  /// Android shrinks the player into a window on leaving the app only while an episode plays.
  void _updatePip() {
    final s = _player.state;
    final args = {'enabled': _phase == _Phase.playing && _started && s.playing, 'width': s.width ?? 0, 'height': s.height ?? 0};
    if ('$args' == _pipSent) return;
    _pipSent = '$args';
    _pip.invokeMethod('set', args).ignore();
  }

  /// Leaving the app or losing the headphones; Android may kill the app once it's in the background.
  void _pause() {
    _player.pause();
    if (_phase == _Phase.playing) _save();
  }

  Future<void> _setup() async {
    // Emulators' EGL rejects mpv's GL context (EGL_BAD_ATTRIBUTE), so there mpv draws
    // through the decoder instead: video shows, Anime4K can't. Same check media_kit uses.
    final emulator = await const MethodChannel('com.alexmercerind/media_kit_video')
        .invokeMethod<bool>('Utils.IsEmulator')
        .catchError((_) => false);
    if (!mounted) return;
    setState(() {
      _emulator = emulator == true;
      _video = VideoController(
        _player,
        configuration: emulator == true
            ? const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec')
            : const VideoControllerConfiguration(),
      );
    });
    final mpv = _player.platform as NativePlayer;
    await mpv.setProperty('demuxer-readahead-secs', '20');
    await mpv.setProperty('audio-display', 'no');
    await mpv.setProperty('sub-scale', '$_subScale');
    if (!mounted) return; // left before the player was ready
    await mpv.observeProperty('idle-active', (_) async => _checkFailed());
    if (mounted) _start(_index);
  }

  /// media_kit keeps files open at the end, so mpv sitting idle while a file
  /// should be playing means the load or the stream failed (the desktop gets
  /// this as end-file with reason "error"). Checked a moment after each idle
  /// change or error log, by state rather than by transition, since open()
  /// passes through idle too.
  Future<void> _checkFailed() async {
    final req = _request;
    bool stale() => !mounted || req != _request || _phase != _Phase.playing || _opening;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (stale()) return;
    final idle = await (_player.platform as NativePlayer).getProperty('idle-active');
    if (!stale() && idle == 'yes') _fail(_lastError.isEmpty ? 'Playback failed' : _lastError);
  }

  @override
  void dispose() {
    if (_phase == _Phase.playing) _save();
    Api.call('syncNow').ignore();
    _request++;
    for (final t in [_hideTimer, _slowTimer, _resumeHide, _countdown, _osdTimer, _saveTimer]) {
      t?.cancel();
    }
    for (final s in _subs) {
      s.cancel();
    }
    d.removeListener(_dataChanged);
    _lifecycle.dispose();
    _audio.setMethodCallHandler(null);
    _pip.setMethodCallHandler(null);
    _pip.invokeMethod('set', {'enabled': false, 'width': 0, 'height': 0}).ignore();
    _player.dispose();
    Api.get('stopStreams');
    // Not while the tree is being torn down: listeners rebuild other pages.
    Future.microtask(() => Api.historyRevision.value++);
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _refresh([Object? _]) {
    if (mounted) setState(() {});
  }

  void _dataChanged() {
    if (d.metaLoaded && !_hadMeta) {
      _hadMeta = true;
      _fetchSkip();
    }
    _refresh();
  }

  void _setStatus(String status) {
    _status = status;
    _slow = false;
    _slowTimer?.cancel();
    _slowTimer = Timer(const Duration(seconds: 12), () => setState(() => _slow = true));
  }

  void _onDuration(Duration duration) {
    if (duration > Duration.zero && !_loaded && _phase == _Phase.playing) {
      setState(() {
        _loaded = true;
        _setStatus('Buffering…');
      });
    }
  }

  void _onPosition(Duration position) {
    final sec = position.inMilliseconds / 1000;
    if (!_started && _loaded && sec > 0 && !_player.state.buffering) {
      _started = true;
      if (_resumed) {
        _resumePrompt = true;
        _resumeHide = Timer(const Duration(seconds: 8), () => setState(() => _resumePrompt = false));
      }
    }
    if (sec > 0 && _started) _lastPos = sec;
    if (_autoSkip) {
      if (_inOp && !_skippedOp) {
        _skippedOp = true;
        _seek(_segment('op')![1]);
      } else if (_inEd && !_skippedEd && _hasNext) {
        _skippedEd = true;
        _seek(_segment('ed')![1]);
      }
    }
    _refresh();
  }

  void _onEof() {
    if (_phase != _Phase.playing || !_loaded) return;
    _save(completed: true);
    Api.historyRevision.value++;
    setState(() {
      if (_autoplay && _hasNext) {
        _countdownLeft = 5;
        _countdown = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _countdownLeft--);
          if (_countdownLeft <= 0) _start(_index + 1);
        });
      } else {
        _phase = _Phase.ended;
      }
    });
  }

  void _save({bool completed = false}) {
    // Until details land the series key can still change; the next tick saves.
    final duration = _duration;
    if (duration <= 0 || !d.metaLoaded) return;
    final done = completed || _completedMarked || _position / duration >= 0.9;
    if (done && !_completedMarked && _hasNext && d.anime['source'] != 'local' && _localFile == null) {
      // Warm the page cache so the next episode starts fast.
      Api.call('qualities', {'source': d.anime['source'], 'url': d.episodes[_index + 1]['url']}).ignore();
    }
    _completedMarked = done;
    // The position is gone at the end of the file.
    Api.get('saveProgress', d.progressRow(_ep, playbackTime: completed ? duration : _position, duration: duration, completed: done));
  }

  void _fetchSkip() {
    final num = _ep['num'], mal = toInt(_meta['mal_id']);
    if (mal == 0) return;
    Api.call('skipTimes', {'malId': mal, 'episode': num}).then((s) {
      if (mounted && _ep['num'] == num) setState(() => _skip = s);
    }, onError: (_) {});
  }

  void _stopFile() {
    _loaded = false;
    _player.stop();
  }

  void _start(int i) {
    if (i < 0 || i >= d.episodes.length) {
      setState(() {
        _errorText = 'No episode at position $i';
        _phase = _Phase.error;
      });
      return;
    }
    if (_phase == _Phase.playing) _save();
    final req = ++_request;
    _stopFile();
    _countdown?.cancel();
    setState(() {
      _index = i;
      _phase = _Phase.resolving;
      _setStatus(_isLocal ? 'Opening the downloaded episode…' : 'Looking up episode ${_ep['num']} on $_sourceName…');
      _started = false;
      _skip = {};
      _completedMarked = _skippedOp = _skippedEd = false;
      _resumePrompt = false;
      _countdownLeft = 0;
      _startAt = -1;
      _lastPos = 0;
      _qualities = [];
      _tried = [];
      _quality = '';
      _reconnects = 0;
      _subDelay = 0;
    });
    (_player.platform as NativePlayer).setProperty('sub-delay', '0').ignore();
    final saved =(Api.get('seriesProgress', {'key': d.seriesKey, 'url': d.anime['url']}) as List).firstWhere(
      (p) => p['episode_number'] == _ep['num'],
      orElse: () => null,
    );
    _resumeAt = saved != null && saved['completed'] != true && toInt(saved['playback_time']) > 30
        ? toInt(saved['playback_time']).toDouble()
        : 0;
    _fetchSkip();
    if (_localFile case final file?) {
      _load(req, {'url': file});
      return;
    }
    Api.call('qualities', {'source': d.anime['source'], 'url': _ep['url']}).then(
      (list) {
        if (req != _request || !mounted) return;
        _qualities = List<String>.from(list);
        _resolve(_pickQuality(_preferredQuality));
      },
      onError: (_) {
        if (req == _request && mounted) _resolve(_preferredQuality);
      },
    );
  }

  String _pickQuality(String q) => _qualities.isEmpty ? q : (Api.get('pickQuality', {'list': _qualities, 'want': q}) as String? ?? q);

  /// YouTube-style: the choice is saved for later episodes; switching
  /// mid-episode reloads the stream at the same position.
  void _setQuality(String q) {
    _preferredQuality = q;
    Api.setSetting('quality', q);
    final target = _pickQuality(q);
    if (_phase == _Phase.ended || (target == _quality && _phase != _Phase.error)) return _refresh();
    if (_phase == _Phase.playing && _started) {
      _save();
      _startAt = _lastPos;
      _resumePrompt = false;
    }
    _resolve(target);
  }

  void _resolve(String q) {
    final req = ++_request;
    setState(() {
      _quality = q;
      _tried = [..._tried, q];
      _phase = _Phase.resolving;
      _setStatus(_started ? 'Switching to $q…' : 'Finding a working server…');
    });
    Api.call('resolve', {'source': d.anime['source'], 'url': _ep['url'], 'quality': q}).then(
      (s) {
        if (req == _request && mounted) _load(req, s);
      },
      onError: (e) {
        if (req == _request && mounted) _fail('$e');
      },
    );
  }

  Future<void> _load(int req, Map<String, dynamic> s) async {
    final mpv = _player.platform as NativePlayer;
    if (_startAt >= 0) _startAt = max(_startAt, _lastPos); // the old stream kept playing while resolving
    final start = _startAt >= 0 ? _startAt : _resumeAt;
    _resumed = _startAt < 0 && _resumeAt > 0;
    _startAt = -1;
    // A newer request, or leaving the player, supersedes this load (and disposes mpv).
    bool stale() => req != _request || !mounted;
    await mpv.setProperty('demuxer-lavf-o', s['hls'] == true ? 'allowed_extensions=ALL' : '');
    if (stale()) return;
    await mpv.setProperty('force-media-title', '${d.title} - Episode ${_ep['num']}');
    if (stale()) return;
    _applyShaders();
    _loaded = false;
    _lastError = '';
    setState(() {
      _phase = _Phase.playing;
      _setStatus('Loading video…');
    });
    final referer = '${s['referer'] ?? ''}';
    _opening = true;
    try {
      await _player.open(
        Media(
          s['url'],
          httpHeaders: referer.isEmpty ? null : {'Referer': referer},
          start: start > 0 ? Duration(milliseconds: (start * 1000).round()) : null,
        ),
      );
    } catch (e) {
      if (!stale()) _fail('$e'); // else mpv was disposed under us
    } finally {
      _opening = false;
    }
    _poke();
  }

  /// Before the first frame, try each other quality once; mid-episode,
  /// reconnect at the same spot up to twice. Then the error card.
  void _fail(String err) {
    final next = _isLocal
        ? ''
        : _started
        ? (_reconnects < 2 ? _quality : '')
        : _qualities.firstWhere((q) => !_tried.contains(q), orElse: () => '');
    if (next.isEmpty) {
      setState(() {
        _errorText = err.isEmpty ? 'Playback failed' : err;
        _phase = _Phase.error;
      });
      return;
    }
    debugPrint('playback failed, retrying: $err');
    final failed = _quality;
    if (_started) {
      _reconnects++;
      _startAt = _lastPos;
    }
    _resolve(next);
    _setStatus(_started ? 'Connection dropped, reconnecting…' : "${failed.isEmpty ? 'That stream' : failed} didn't work, trying $next…");
  }

  /// From the error card: same or another quality, keeping the position.
  void _retry(String q) {
    if (_isLocal || (!_started && _qualities.isEmpty)) return _start(_index); // the quality lookup itself failed
    _tried = [];
    _reconnects = 0;
    if (_started) _startAt = _lastPos;
    _resolve(q.isEmpty ? _quality : q);
    _setStatus('Retrying…');
  }

  String _modeName(String mode) => mode == 'off' ? 'Sharpening off' : _anime4kModes.firstWhere((m) => m['key'] == mode)['name'];

  /// The first use downloads the shaders. A reply for a mode switched away from meanwhile is
  /// dropped; a failure turns sharpening off for this session and keeps the saved choice.
  void _applyShaders() {
    final mpv = _player.platform as NativePlayer;
    final mode = _anime4k;
    if (mode.isEmpty || mode == 'off') {
      mpv.command(['change-list', 'glsl-shaders', 'clr', '']);
      return;
    }
    Api.call('shaders', {'mode': mode}).then((r) {
      if (!mounted || mode != _anime4k) return;
      mpv.command(['change-list', 'glsl-shaders', 'set', r['list']]);
      if (_downloadingShaders) _showOsd(Icons.auto_awesome_rounded, _modeName(mode));
      _downloadingShaders = false;
    }, onError: (e) {
      if (!mounted || mode != _anime4k) return;
      _downloadingShaders = false;
      setState(() => _anime4k = 'off');
      mpv.command(['change-list', 'glsl-shaders', 'clr', '']);
      toast("Couldn't turn on sharpening: ${Api.describe(e)}");
    });
  }

  void _setAnime4k(String mode) {
    _anime4k = mode;
    Api.setSetting('anime4k', mode);
    _applyShaders();
    _showOsd(Icons.auto_awesome_rounded, _modeName(mode));
  }

  void _seek(num sec) => _player.seek(Duration(milliseconds: (sec * 1000).round()));

  void _seekBy(int sec) {
    _seek(max(0, _position + sec));
    _showOsd(sec < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, '${sec < 0 ? '−' : '+'}${sec.abs()}s');
  }

  void _togglePause() {
    _player.playOrPause();
    _showOsd(_player.state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded, '');
  }

  void _skipSegment() {
    if (_inOp) {
      _seek(_segment('op')![1]);
    } else if (_inEd) {
      _seek(_segment('ed')![1]);
    }
  }

  void _showOsd(IconData icon, String label) {
    _osdTimer?.cancel();
    setState(() => _osd = (icon, label));
    _osdTimer = Timer(const Duration(milliseconds: 800), () => setState(() => _osd = null));
  }

  void _poke() {
    _hideTimer?.cancel();
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _hideTimer = Timer(const Duration(milliseconds: 3000), _hideControls);
  }

  void _hideControls() => setState(() => _controlsVisible = _timing = false);

  /// Bottom sheet menus keep the controls up while they're open.
  Future<T?> _menu<T>(String header, List<(String, T, bool)> items) async {
    _hideTimer?.cancel();
    final v = await pickFrom<T>(context, header, items);
    _poke();
    return v;
  }

  Future<void> _qualityMenu() async {
    final auto = _preferredQuality == 'best' && _quality.isNotEmpty && _quality != 'best' ? 'Auto ($_quality)' : 'Auto';
    final q = await _menu('Quality', [
      (auto, 'best', _preferredQuality == 'best'),
      for (final q in _qualities) (q, q, _preferredQuality != 'best' && _quality == q),
    ]);
    if (q != null) _setQuality(q);
  }

  Future<void> _speedMenu() async {
    final rate = _player.state.rate;
    final v = await _menu('Speed', [
      for (final v in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]) (v == 1 ? 'Normal' : '$v×', v, rate == v),
    ]);
    if (v == null) return;
    _player.setRate(v);
    _showOsd(Icons.speed_rounded, '$v×');
  }

  Future<void> _trackMenu() async {
    String label(String id, String? title, String? lang) =>
        text([title, lang, 'Track $id']) + (lang != null && lang.isNotEmpty && text([title]).isNotEmpty ? ' ($lang)' : '');
    final real = RegExp(r'^\d+$'); // skips media_kit's "auto" and "no" entries
    final tracks = _player.state.tracks, current = _player.state.track;
    final choice = await _menu<Object>('Audio & subtitles', [
      for (final t in tracks.audio.where((t) => real.hasMatch(t.id))) ('♪  ${label(t.id, t.title, t.language)}', t, current.audio == t),
      for (final t in tracks.subtitle.where((t) => real.hasMatch(t.id))) (label(t.id, t.title, t.language), t, current.subtitle == t),
      ('Subtitles off', SubtitleTrack.no(), current.subtitle.id == 'no'),
      if (real.hasMatch(current.subtitle.id)) ...[
        ('Subtitle size · ${_scaleName(_subScale)}', 'size', false),
        ('Subtitle timing · ${_delayName()}', 'timing', false),
      ],
    ]);
    if (choice is AudioTrack) _player.setAudioTrack(choice);
    if (choice is SubtitleTrack) _player.setSubtitleTrack(choice);
    if (choice == 'size') _sizeMenu();
    if (choice == 'timing') {
      setState(() => _timing = true);
      _poke();
    }
  }

  String _scaleName(double v) => v == 1 ? 'Normal' : '${(v * 100).round()}%';

  // Positive is later, as mpv counts it.
  String _delayName() => '${_subDelay < 0 ? '−' : '+'}${_subDelay.abs().toStringAsFixed(1)} s';

  Future<void> _sizeMenu() async {
    final v = await _menu('Subtitle size', [
      for (final v in [0.75, 1.0, 1.25, 1.5, 2.0]) (_scaleName(v), v, _subScale == v),
    ]);
    if (v == null) return;
    setState(() => _subScale = v);
    (_player.platform as NativePlayer).setProperty('sub-scale', '$v').ignore();
    Api.setSetting('subtitleScale', v);
    _showOsd(Icons.format_size_rounded, _scaleName(v));
  }

  void _nudgeSubs(double sec) {
    setState(() => _subDelay = ((_subDelay + sec) * 10).round() / 10);
    (_player.platform as NativePlayer).setProperty('sub-delay', '$_subDelay').ignore();
    _poke();
  }

  Future<void> _anime4kMenu() async {
    final mode = await _menu('Sharpen video', [
      ('Off', 'off', _anime4k.isEmpty || _anime4k == 'off'),
      for (final m in _anime4kModes) ('${m['name']}  ·  ${m['description']}', m['key'] as String, _anime4k == m['key']),
    ]);
    if (mode != null) _setAnime4k(mode);
  }

  @override
  Widget build(BuildContext context) {
    final playing = _phase == _Phase.playing;
    final card = _phase == _Phase.error || _phase == _Phase.ended;
    _updatePip(); // every state it depends on rebuilds the page
    return Scaffold(
      key: _scaffold,
      backgroundColor: Colors.black,
      endDrawer: Builder(builder: (_) => _episodesDrawer()), // built only while open
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_video case final video?) Video(controller: video, controls: NoVideoControls),
          // mediacodec_embed can't draw subtitles, so the emulator gets them as text.
          if (_video case final video? when _emulator)
            SubtitleView(
              controller: video,
              configuration: SubtitleViewConfiguration(
                style: TextStyle(
                  height: 1.4,
                  fontSize: 32 * _subScale,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 3), Shadow(blurRadius: 6)],
                ),
              ),
            ),
          // The picture-in-picture window shows only the video.
          if (!_inPip) ...[
            // Series art behind the loading screen and the end/error card.
            if (!_started || card) _backdrop(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _controlsVisible && _started ? _hideControls() : _poke(),
              onDoubleTapDown: (e) {
                if (!_started || !playing) return;
                final third = e.localPosition.dx / context.size!.width;
                third < 0.35 ? _seekBy(-10) : (third > 0.65 ? _seekBy(10) : _togglePause());
              },
              onDoubleTap: () {},
            ),
            if (!_started && !card) _loadingScreen(),
            if (_started && (_phase == _Phase.resolving || (playing && _player.state.buffering)))
              const Center(child: CircularProgressIndicator(color: Colors.white)),
            if (_osd case (final icon, final label))
              Align(
                alignment: _showControls ? const Alignment(0, 0.4) : Alignment.center, // clear of the play button and resume prompt
                child: _pill([Icon(icon, color: Colors.white, size: 32), if (label.isNotEmpty) _white(label)]),
              ),
            if (_showControls) ..._controls(),
            if (_timing && _showControls && _started)
              Positioned(
                left: 0,
                right: 0,
                bottom: 110,
                child: Center(
                  child: _pill([
                    IconButton(color: Colors.white, icon: const Icon(Icons.remove_rounded), onPressed: () => _nudgeSubs(-0.1)),
                    _white('Subtitles ${_delayName()}'),
                    IconButton(color: Colors.white, icon: const Icon(Icons.add_rounded), onPressed: () => _nudgeSubs(0.1)),
                  ]),
                ),
              ),
            if (_developerMode && _showStats)
              Positioned(
                top: _showControls ? 72 : 16,
                left: 16,
                bottom: _showControls ? 110 : 16,
                child: SafeArea(
                  child: SingleChildScrollView(
                    child: PlaybackStats(readProperty: (_player.platform as NativePlayer).getProperty),
                  ),
                ),
              ),
            if (_started && playing && (_inOp || _inEd))
              Positioned(
                right: 24,
                bottom: _showControls ? 110 : 24,
                child: FilledButton.icon(
                  icon: const Icon(Icons.fast_forward_rounded),
                  label: Text(_inOp ? 'Skip intro' : 'Skip outro'),
                  onPressed: _skipSegment,
                ),
              ),
            if (_resumePrompt && _started)
              Positioned(
                top: 72,
                left: 0,
                right: 0,
                child: Center(
                  child: _pill([
                    const Icon(Icons.history_rounded, color: Colors.white),
                    _white('Resumed at ${formatTime(_resumeAt)}'),
                    TextButton(
                      onPressed: () {
                        _seek(0);
                        setState(() => _resumePrompt = false);
                      },
                      child: const Text('Start over'),
                    ),
                  ]),
                ),
              ),
            if (_countdownLeft > 0) Positioned(right: 24, bottom: 110, child: _upNext()),
            if (card) Center(child: _endCard()),
          ],
        ],
      ),
    );
  }

  Widget _white(String s, {TextStyle? style}) => Text(
    s,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: (style ?? const TextStyle()).copyWith(color: Colors.white),
  );

  Widget _pill(List<Widget> children) => DecoratedBox(
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(24)),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: children),
    ),
  );

  Widget _backdrop() => Stack(
    fit: StackFit.expand,
    children: [
      Opacity(opacity: 0.55, child: BlurredArt(text([_meta['banner'], _meta['cover'], d.anime['image']]), sigma: 30)),
      const ColoredBox(color: Colors.black45),
    ],
  );

  Widget _loadingScreen() {
    final t = Theme.of(context).textTheme;
    final title = d.episodeTitle(_ep);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            _white(d.title, style: t.headlineSmall),
            _white('Episode ${_ep['num']}${title.isNotEmpty && !title.startsWith('Episode') ? '  ·  $title' : ''}', style: t.titleMedium),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 12,
              children: [
                const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                Flexible(child: _white(_status)),
              ],
            ),
            if (_slow)
              Text(
                '$_sourceName is slow right now. Keep waiting or try another source.',
                textAlign: TextAlign.center,
                style: t.bodySmall?.copyWith(color: Colors.white70),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _controls() {
    final t = Theme.of(context).textTheme;
    final duration = _duration;
    final position = _dragValue != null ? _dragValue! * duration : _position;
    final buffered = duration > 0 ? (_player.state.buffer.inMilliseconds / 1000 / duration).clamp(0.0, 1.0) : 0.0;
    final epTitle = d.episodeTitle(_ep);
    final bottom = _started && (_phase == _Phase.playing || _phase == _Phase.resolving);
    const shade = [Colors.black87, Colors.transparent];
    return [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: shade),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 24),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: Opacity(
                      opacity: _started ? 1 : 0, // the loading screen already shows these
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _white(d.title, style: t.titleMedium),
                          _white(
                            'Episode ${_ep['num']}${epTitle.isNotEmpty && !epTitle.startsWith('Episode') ? '  ·  $epTitle' : ''}',
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  _white('$_sourceName${_quality.isNotEmpty && _quality != 'best' ? '  ·  $_quality' : ''}', style: t.labelLarge),
                ],
              ),
            ),
          ),
        ),
      ),
      if (bottom)
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 32,
            children: [
              IconButton(
                iconSize: 36,
                color: Colors.white,
                icon: const Icon(Icons.skip_previous_rounded),
                onPressed: _hasPrev ? () => _start(_index - 1) : null,
              ),
              IconButton.filled(
                iconSize: 48,
                icon: Icon(_player.state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                onPressed: _togglePause,
              ),
              IconButton(
                iconSize: 36,
                color: Colors.white,
                icon: const Icon(Icons.skip_next_rounded),
                onPressed: _hasNext ? () => _start(_index + 1) : null,
              ),
            ],
          ),
        ),
      if (bottom)
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: shade),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 8, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        _white('${formatTime(position)} / ${formatTime(duration)}', style: t.labelMedium),
                        Expanded(
                          child: Slider(
                            value: (_dragValue ?? (duration > 0 ? _position / duration : 0)).clamp(0.0, 1.0),
                            secondaryTrackValue: buffered,
                            onChangeStart: duration > 0 ? (v) => _hideTimer?.cancel() : null,
                            onChanged: duration > 0 ? (v) => setState(() => _dragValue = v) : null,
                            onChangeEnd: (v) {
                              _seek(v * duration);
                              setState(() => _dragValue = null);
                              _poke();
                            },
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (!_isLocal)
                          TextButton.icon(
                            style: TextButton.styleFrom(foregroundColor: Colors.white),
                            icon: const Icon(Icons.settings_rounded),
                            label: Text(_quality.isNotEmpty && _quality != 'best' ? _quality : 'Auto'),
                            onPressed: _qualityMenu,
                          ),
                        if (_developerMode)
                          IconButton(
                            tooltip: 'Playback information',
                            color: _showStats ? Theme.of(context).colorScheme.primary : Colors.white,
                            icon: const Icon(Icons.info_outline_rounded),
                            onPressed: () => setState(() => _showStats = !_showStats),
                          ),
                        TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
                          icon: const Icon(Icons.speed_rounded),
                          label: Text('${_player.state.rate}×'),
                          onPressed: _speedMenu,
                        ),
                        IconButton(color: Colors.white, icon: const Icon(Icons.subtitles_rounded), onPressed: _trackMenu),
                        IconButton(color: Colors.white, icon: const Icon(Icons.auto_awesome_rounded), onPressed: _anime4kMenu),
                        if (d.episodes.length > 1)
                          IconButton(
                            color: Colors.white,
                            icon: const Icon(Icons.playlist_play_rounded),
                            onPressed: () => _scaffold.currentState?.openEndDrawer(),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _upNext() {
    final t = Theme.of(context);
    final next = _hasNext ? d.episodes[_index + 1] as Map<String, dynamic> : null;
    final title = next == null ? '' : text([d.info[next['num']]?['title']]);
    return SizedBox(
      width: 300,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              Text('UP NEXT IN $_countdownLeft', style: t.textTheme.labelLarge?.copyWith(color: t.colorScheme.primary)),
              if (next != null)
                Text('Episode ${next['num']}${title.isNotEmpty ? '  ·  $title' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
              LinearProgressIndicator(value: (5 - _countdownLeft) / 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      _countdown?.cancel();
                      setState(() {
                        _countdownLeft = 0;
                        _phase = _Phase.ended;
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                  FilledButton(onPressed: () => _start(_index + 1), child: const Text('Play now')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _endCard() {
    final t = Theme.of(context);
    final failed = _phase == _Phase.error;
    final others = failed ? _qualities.where((q) => q != _quality).take(4).toList() : <String>[];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Card(
        margin: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              Text(failed ? '(×﹏×)' : '(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧', style: t.textTheme.headlineMedium?.copyWith(color: t.colorScheme.primary)),
              Text(
                failed
                    ? "Couldn't play episode ${_ep['num']}"
                    : _hasNext
                    ? 'Episode ${_ep['num']} finished'
                    : "You've reached the last episode!",
                textAlign: TextAlign.center,
                style: t.textTheme.titleLarge,
              ),
              Text(
                failed
                    ? Api.describe(_errorText) + (_tried.length > 1 ? ' Tried ${_tried.join(', ')} on $_sourceName.' : '')
                    : _hasNext
                    ? 'Ready for the next one?'
                    : 'Thanks for watching.',
                textAlign: TextAlign.center,
              ),
              if (failed && _errorText.isNotEmpty)
                SelectableText(
                  _errorText,
                  textAlign: TextAlign.center,
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline),
                ),
              if (others.isNotEmpty)
                Wrap(
                  spacing: 8,
                  children: [for (final q in others) FilledButton.tonal(onPressed: () => _retry(q), child: Text('Try $q'))],
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Back')),
                  if (failed)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                      onPressed: () => _retry(''),
                    ),
                  if (_phase == _Phase.ended)
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Replay'),
                      onPressed: () {
                        _resumeAt = 0;
                        _start(_index);
                      },
                    ),
                  if (_hasNext)
                    FilledButton.icon(
                      icon: const Icon(Icons.skip_next_rounded),
                      label: const Text('Next episode'),
                      onPressed: () => _start(_index + 1),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _episodesDrawer() => Drawer(
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Episodes', style: Theme.of(context).textTheme.titleLarge),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              // Opens near the current episode (tiles are ~72 px tall).
              controller: ScrollController(initialScrollOffset: max(0, _index - 2) * 72.0),
              itemCount: d.episodes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final ep = d.episodes[i] as Map<String, dynamic>;
                return EpisodeTile(
                  num: ep['num'],
                  title: d.episodeTitle(ep),
                  record: d.progress[ep['num']],
                  current: i == _index,
                  onTap: () {
                    Navigator.pop(context);
                    _start(i);
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
