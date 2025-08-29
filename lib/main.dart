// ignore_for_file: constant_identifier_names
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';

import 'package:chewie/chewie.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lottie/lottie.dart';
import 'package:path/path.dart' as p;
import 'package:pdfx/pdfx.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Provider;
import 'package:video_player/video_player.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const storageBucket = 'kenz';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  final url = dotenv.env['SUPABASE_URL'] ?? '';
  final anonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  await Supabase.initialize(url: url, anonKey: anonKey);
  runApp(const ProviderScope(child: KenzApp()));
}

// ─────────────────────────────────────────────────────────────────────────────
// SELF-DESTRUCT WATCHER (bind realtime once)
// ─────────────────────────────────────────────────────────────────────────────
class _SelfDestructWatcher extends ConsumerStatefulWidget {
  const _SelfDestructWatcher({super.key});
  @override
  ConsumerState<_SelfDestructWatcher> createState() => _SelfDestructWatcherState();
}

class _SelfDestructWatcherState extends ConsumerState<_SelfDestructWatcher> {
  @override
  void initState() {
    super.initState();
    // defer to next frame to ensure providers are ready
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selfDestructProvider.notifier).bind();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 0 – ROBOT SELECTION (after intro, before login)
// ─────────────────────────────────────────────────────────────────────────────
class RobotSelectPage extends ConsumerStatefulWidget {
  const RobotSelectPage({super.key});
  @override
  ConsumerState<RobotSelectPage> createState() => _RobotSelectPageState();
}

class _RobotSelectPageState extends ConsumerState<RobotSelectPage> {
  bool _loading = true;
  String? _error;
  List<Robot> _robots = const [];
  final Map<int, String> _imageUrls = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await sb
          .from('kenz_robots')
          .select('id,name')
          .order('name', ascending: true);
      final list = <Robot>[];
      final imgs = <int, String>{};
      for (final r in rows as List) {
        final id = r['id'] as int;
        final name = (r['name'] as String).trim();
        list.add(Robot(id, name));
        final path = '${name}.png';
        final url = sb.storage.from(storageBucket).getPublicUrl(path);
        imgs[id] = url;
      }
      if (!mounted) return;
      setState(() {
        _robots = list;
        _imageUrls.clear();
        _imageUrls.addAll(imgs);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onPick(Robot r) {
    final img = _imageUrls[r.id];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectivityGate(
          child: LoginPage(prefilledName: r.name, robotImageUrl: img),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.asset(
            'assets/BG.png',
            fit: BoxFit.cover,
          ),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(height: 8),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.9,
                ),
                itemCount: _robots.length,
                itemBuilder: (context, i) {
                  final r = _robots[i];
                  final img = _imageUrls[r.id];
                  return _RobotCard(
                    name: r.name,
                    imageUrl: img,
                    onTap: () => _onPick(r),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _RobotCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final VoidCallback onTap;
  const _RobotCard({required this.name, required this.imageUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: imageUrl != null
                  ? Image.network(
                      imageUrl!,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .moveY(begin: -6, end: 6, duration: const Duration(seconds: 2))
                  : Icon(Icons.android, size: 120, color: Colors.white24),
            ),
            const SizedBox(height: 10),
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SELF-DESTRUCT OVERLAY (blocking)
// ─────────────────────────────────────────────────────────────────────────────
class _SelfDestructOverlay extends ConsumerWidget {
  const _SelfDestructOverlay({super.key});

  String _fmt(Duration d) {
    int h = d.inHours;
    int m = d.inMinutes % 60;
    int s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(selfDestructProvider);
    if (!st.active) return const SizedBox.shrink();
    // Allow interaction for the robot/team that triggered level 7,
    // and also allow the login page so that team can log in.
    final currentRobot = ref.watch(robotProvider);
    if (currentRobot == null) {
      // No robot chosen yet (login stage) – do not block so the triggering team can log in.
      return const SizedBox.shrink();
    }
    if (st.triggeringRobotId != null && currentRobot.id == st.triggeringRobotId) {
      // This is the team that reached level 7 – don't show the overlay for them.
      return const SizedBox.shrink();
    }
    final remaining = st.remaining;
    return AbsorbPointer(
      absorbing: true, // block entire app
      child: Stack(
        children: [
          // dark/fiery backdrop
          Container(color: const Color(0xFF0B0F1A).withValues(alpha: 0.96)),
          // explosion lottie centered and scaled
          Center(
            child: Lottie.asset(
              'assets/lottie/explosion.json',
              repeat: true,
              fit: BoxFit.contain,
              width: 200,
            ),
          ),
          // content overlay text + timer
          Positioned.fill(
            child: Container(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SELF-DESTRUCTION STARTED',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: Colors.redAccent.shade200,
                      shadows: [
                        Shadow(color: Colors.redAccent.shade700, blurRadius: 24),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.8)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.white70, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _fmt(remaining),
                          style: const TextStyle(
                            fontSize: 22,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Robot will fully destruct after the countdown.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INTRO GATE – plays intro video on app launch then shows next
// ─────────────────────────────────────────────────────────────────────────────
class IntroGate extends StatefulWidget {
  final Widget next;
  const IntroGate({super.key, required this.next});

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> {
  late final VideoPlayerController _ctrl;
  bool _ready = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.asset('assets/video/intro.mp4');
    _ctrl.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _ctrl.play();
    });
    _ctrl.addListener(() {
      if (!_done && _ctrl.value.isInitialized) {
        final d = _ctrl.value.duration;
        final p = _ctrl.value.position;
        if (d > Duration.zero && p >= d) {
          _done = true;
          if (mounted) setState(() {});
        }
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.next;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _ctrl.value.size.width,
                height: _ctrl.value.size.height,
                child: VideoPlayer(_ctrl),
              ),
            )
          else
            Container(color: const Color(0xFF0B1022)),
        ],
      ),
    );
  }
}

// Latest penalty across all levels for a robot (if any)
Future<Penalty?> fetchLatestPenaltyForRobot(int robotId) async {
  final res = await sb
      .from('kenz_penalties')
      .select('penalty_until')
      .eq('robot_id', robotId)
      .order('penalty_until', ascending: false)
      .limit(1)
      .maybeSingle();
  if (res == null) return null;
  final until = DateTime.parse(res['penalty_until'] as String);
  return Penalty(until);
}

class _WinGeom {
  final double l;
  final double t;
  final double w;
  final double h;
  final double rot;
  final String title;
  const _WinGeom({
    required this.l,
    required this.t,
    required this.w,
    required this.h,
    required this.rot,
    required this.title,
  });
}

final sb = Supabase.instance.client;

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────
class Robot {
  final int id;
  final String name;
  Robot(this.id, this.name);
}

class LevelRow {
  final int id;
  final int robotId;
  final int levelNumber; // 1..7
  final bool unlocked;
  final int attempts; // wrong attempts so far
  final String? password; // per-user per-level password
  LevelRow({
    required this.id,
    required this.robotId,
    required this.levelNumber,
    required this.unlocked,
    required this.attempts,
    required this.password,
  });

  LevelRow copyWith({bool? unlocked, int? attempts}) => LevelRow(
    id: id,
    robotId: robotId,
    levelNumber: levelNumber,
    unlocked: unlocked ?? this.unlocked,
    attempts: attempts ?? this.attempts,
    password: password,
  );
}

class Penalty {
  final DateTime until;
  Penalty(this.until);
  bool get active => DateTime.now().isBefore(until);
  Duration get remaining => until.difference(DateTime.now()).isNegative
      ? Duration.zero
      : until.difference(DateTime.now());
}

class PenaltyOverlayState {
  final bool active;
  final DateTime? until;
  final Offset?
  offset; // screen offset for the floating widget (top-left origin)
  const PenaltyOverlayState({
    required this.active,
    required this.until,
    required this.offset,
  });

  PenaltyOverlayState copyWith({
    bool? active,
    DateTime? until,
    Offset? offset,
  }) => PenaltyOverlayState(
    active: active ?? this.active,
    until: until ?? this.until,
    offset: offset ?? this.offset,
  );
}

class PenaltyOverlayController extends StateNotifier<PenaltyOverlayState> {
  PenaltyOverlayController()
    : super(
        const PenaltyOverlayState(active: false, until: null, offset: null),
      );

  Timer? _tick;

  Future<void> checkForRobot(int robotId) async {
    final p = await fetchLatestPenaltyForRobot(robotId);
    if (p != null && p.active) {
      start(p.until);
    } else {
      stop();
    }
  }

  void start(DateTime until) {
    _tick?.cancel();
    state = state.copyWith(active: true, until: until);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final u = state.until;
      if (u == null) return;
      if (!DateTime.now().isBefore(u)) {
        stop();
      } else {
        // trigger rebuild
        state = state.copyWith();
      }
    });
  }

  void stop() {
    _tick?.cancel();
    _tick = null;
    state = const PenaltyOverlayState(active: false, until: null, offset: null);
  }

  void updateOffset(Offset o) {
    state = state.copyWith(offset: o);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PASSBLOCKS VIEWER (digital lock-style swap puzzle)
// ─────────────────────────────────────────────────────────────────────────────
class PassblocksViewer extends StatefulWidget {
  final String url;
  final String? name;
  const PassblocksViewer({super.key, required this.url, this.name});

  @override
  State<PassblocksViewer> createState() => _PassblocksViewerState();
}

class _PassblocksViewerState extends State<PassblocksViewer> {
  String? _init;
  String? _target;
  late List<String> _current;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(widget.url));
      final resp = await req.close();
      final bytes = await consolidateHttpClientResponseBytes(resp);
      final s = utf8.decode(bytes, allowMalformed: true);
      final Map<String, dynamic> jsonMap = json.decode(s) as Map<String, dynamic>;
      String init = (jsonMap['init'] ?? jsonMap['initial'] ?? '').toString();
      String correct = (jsonMap['correct'] ?? jsonMap['target'] ?? '').toString();
      if (init.isEmpty || correct.isEmpty) {
        setState(() {
          _error = 'Invalid passblocks JSON: missing init/correct';
          _loading = false;
        });
        return;
      }
      // Align lengths dynamically
      final n = init.length < correct.length ? init.length : correct.length;
      init = init.substring(0, n);
      correct = correct.substring(0, n);
      setState(() {
        _init = init;
        _target = correct;
        _current = init.split('');
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load: $e';
        _loading = false;
      });
    } finally {
      client.close(force: true);
    }
  }

  int _correctCount() {
    if (_target == null) return 0;
    int c = 0;
    for (int i = 0; i < _current.length; i++) {
      if (_current[i] == _target![i]) c++;
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final percent = (_target == null || _current.isEmpty)
        ? 0.0
        : (_correctCount() / _current.length) * 100.0;
    final unlocked = percent >= 100.0 - 1e-9;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F1A),
        title: Row(
          children: [
            Icon(unlocked ? Icons.lock_open : Icons.lock_outline, color: unlocked ? const Color(0xFF00E676) : Colors.white70),
            const SizedBox(width: 12),
            Text(widget.name ?? 'passblocks', style: const TextStyle(color: Colors.white)),
            const Spacer(),
            Text('${percent.toStringAsFixed(0)}%', style: TextStyle(color: unlocked ? const Color(0xFF00E676) : Colors.white70)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, c) {
                    final w = c.maxWidth;
                    final size = (w - 40) / (_current.length.clamp(3, 12));
                    final tileSize = size.clamp(36.0, 80.0);
                    return Column(
                      children: [
                        const SizedBox(height: 16),
                        // Blocks
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            runSpacing: 10,
                            spacing: 10,
                            children: List.generate(_current.length, (i) {
                              final ch = _current[i];
                              //final correct = _target != null && ch == _target![i];
                              return _SwapTile(
                                index: i,
                                label: ch,
                                size: tileSize,
                                onSwap: (from) {
                                  setState(() {
                                    final tmp = _current[from];
                                    _current[from] = _current[i];
                                    _current[i] = tmp;
                                  });
                                },
                              );
                            }),
                          ),
                        ),
                        const SizedBox(height: 64),
                        // Percentage indicator
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: unlocked? const Color(0xFF00E676).withValues(alpha: 0.15) :Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: unlocked ? const Color(0xFF00E676) :Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.percent, color: unlocked ? const Color(0xFF00E676) :Colors.white70, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                '${_correctCount()}/${_current.length} correct',
                                style: TextStyle(color: unlocked ? const Color(0xFF00E676) :Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),
    );
  }
}

class _SwapTile extends StatelessWidget {
  final int index;
  final String label;
  final double size;
  final bool correct;
  final void Function(int fromIndex) onSwap;
  const _SwapTile({
    required this.index,
    required this.label,
    required this.size,
    this.correct = false,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = correct
        ? const Color(0xFF00E676).withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.06);
    final br = correct ? const Color(0xFF00E676) : Colors.white24;
    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != index,
      onAcceptWithDetails: (details) => onSwap(details.data),
      builder: (context, cand, rej) {
        final highlight = cand.isNotEmpty;
        return Draggable<int>(
          data: index,
          feedback: Material(
            color: Colors.transparent,
            child: _tile(size, br, bg, dragging: true),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: _tile(size, br, bg)),
          child: _tile(size, highlight ? Colors.cyanAccent : br, bg),
        );
      },
    );
  }

  Widget _tile(double size, Color border, Color bg, {bool dragging = false}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.2),
        boxShadow: dragging
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 18,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}

class _CodeTypingEditor extends StatefulWidget {
  final String text;
  final String filename;
  final Duration charDelay;
  const _CodeTypingEditor({
    required this.text,
    required this.filename,
    this.charDelay = const Duration(milliseconds: 10),
  });

  @override
  State<_CodeTypingEditor> createState() => _CodeTypingEditorState();
}

class _CodeTypingEditorState extends State<_CodeTypingEditor> {
  late final ScrollController _scrollController;
  Timer? _timer;
  int _index = 0;
  bool _cursorOn = true;
  Timer? _cursorTimer;

  // Simple regex-based highlighter for common languages (C-like + Python)
  static final Set<String> _kwCommon = {
    'class','interface','enum','extends','implements','with','mixin','abstract','final','const','var','let','static','public','private','protected','async','await','yield','return','break','continue','throw','try','catch','finally','new','this','super','switch','case','default','if','else','for','while','do','in','of','import','export','package','from','as','typedef','struct','union','goto','match','when'
  };
  static final Set<String> _kwTypes = {
    'int','double','num','String','bool','List','Map','Set','void','dynamic','Object','Any','Null','Never','Future','Stream'
  };
  static final RegExp _reLineComment = RegExp(r'//.*');
  static final RegExp _reBlockComment = RegExp(r'/\*[\s\S]*?\*/');
  // Strings: single or double quoted with escapes
  static final RegExp _reString = RegExp(
    r"'(?:\\.|[^'\\])*'" r'|"(?:\\.|[^"\\])*"',
  );
  static final RegExp _reNumber = RegExp(r'\b\d+(?:\.\d+)?\b');
  static final RegExp _reIdent = RegExp(r'\b[_a-zA-Z][_a-zA-Z0-9]*\b');

  List<TextSpan> _highlight(String src) {
    final spans = <TextSpan>[];
    final base = const TextStyle(
      color: Colors.white,
      fontFamily: 'monospace',
      fontSize: 13.5,
      height: 1.5,
    );
    final sKeyword = const TextStyle(color: Color(0xFF80CBC4)); // teal
    final sType = const TextStyle(color: Color(0xFFB39DDB)); // purple
    final sString = const TextStyle(color: Color(0xFFA5D6A7)); // green
    final sNumber = const TextStyle(color: Color(0xFFFFCC80)); // orange
    final sComment = const TextStyle(color: Colors.white54, fontStyle: FontStyle.italic);

    int i = 0;
    TextSpan styled(String text, TextStyle st) => TextSpan(text: text, style: base.merge(st));

    while (i < src.length) {
      // Order matters: comments, strings, numbers, identifiers
      final mBlock = _reBlockComment.matchAsPrefix(src, i);
      if (mBlock != null) {
        spans.add(styled(mBlock.group(0)!, sComment));
        i = mBlock.end;
        continue;
      }
      // Line comment
      final mLine = _reLineComment.matchAsPrefix(src, i);
      if (mLine != null) {
        spans.add(styled(mLine.group(0)!, sComment));
        i = mLine.end;
        continue;
      }
      // String literal
      final mStr = _reString.matchAsPrefix(src, i);
      if (mStr != null) {
        spans.add(styled(mStr.group(0)!, sString));
        i = mStr.end;
        continue;
      }
      // Number
      final mNum = _reNumber.matchAsPrefix(src, i);
      if (mNum != null) {
        spans.add(styled(mNum.group(0)!, sNumber));
        i = mNum.end;
        continue;
      }
      // Identifier (keyword/type detection)
      final mId = _reIdent.matchAsPrefix(src, i);
      if (mId != null) {
        final t = mId.group(0)!;
        if (_kwCommon.contains(t)) {
          spans.add(styled(t, sKeyword));
        } else if (_kwTypes.contains(t)) {
          spans.add(styled(t, sType));
        } else {
          spans.add(TextSpan(text: t, style: base));
        }
        i = mId.end;
        continue;
      }
      // Fallback: one character
      spans.add(TextSpan(text: src[i], style: base));
      i++;
    }
    return spans;
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _timer = Timer.periodic(widget.charDelay, (t) {
      if (!mounted) return;
      if (_index >= widget.text.length) {
        t.cancel();
      } else {
        setState(() => _index++);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _cursorOn = !_cursorOn);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cursorTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _index.clamp(0, widget.text.length);
    final visibleText = widget.text.substring(0, shown);
    final lines = visibleText.split('\n');
    final lineCount = lines.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Simple IDE-like tab bar
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF0B1022),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0x2213E3FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    Text(widget.filename, style: const TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gutter with line numbers
                  Container(
                    padding: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(lineCount, (i) {
                        return Text(
                          '${i + 1}'.padLeft(2),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.5,
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Code area
                  Expanded(
                    child: RichText(
                      text: TextSpan(children: [
                        ..._highlight(visibleText),
                        TextSpan(
                          text: _cursorOn ? '|' : ' ',
                          style: const TextStyle(
                            color: Color(0xFF00E5FF),
                            fontFamily: 'monospace',
                            fontSize: 13.5,
                            height: 1.5,
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

final penaltyOverlayProvider =
    StateNotifierProvider<PenaltyOverlayController, PenaltyOverlayState>((ref) {
      return PenaltyOverlayController();
    });

class MediaEntry {
  final String path; // storage path inside bucket
  final String mediaType; // image | video | audio | pdf | unknown
  MediaEntry(this.path, this.mediaType);
}

// ─────────────────────────────────────────────────────────────────────────────
// PROVIDERS / STATE
// ─────────────────────────────────────────────────────────────────────────────
final connectivityProvider = StreamProvider<ConnectivityResult>((ref) {
  return Connectivity().onConnectivityChanged;
});

final offlineOverlayProvider = Provider<bool>((ref) {
  final result = ref
      .watch(connectivityProvider)
      .maybeWhen(
        data: (d) => d == ConnectivityResult.none,
        orElse: () => false,
      );
  return result;
});

final robotProvider = StateProvider<Robot?>((ref) => null);

final levelsProvider = FutureProvider.autoDispose<List<LevelRow>>((ref) async {
  final robot = ref.watch(robotProvider);
  if (robot == null) return [];
  final res = await sb
      .from('kenz_levels')
      .select()
      .eq('robot_id', robot.id)
      .order('level_number', ascending: true);
  final list = (res as List)
      .map(
        (e) => LevelRow(
          id: e['id'] as int,
          robotId: e['robot_id'] as int,
          levelNumber: e['level_number'] as int,
          unlocked: (e['unlocked'] as bool?) ?? false,
          attempts: (e['attempts'] as int?) ?? 0,
          password: e['password'] as String?,
        ),
      )
      .toList();
  return list;
});

// ─────────────────────────────────────────────────────────────────────────────
// SELF-DESTRUCT (when any robot reaches level 7)
// ─────────────────────────────────────────────────────────────────────────────
class SelfDestructState {
  final bool active; // once triggered, stays true forever (blocks app)
  final DateTime? startedAt; // when level 7 was first detected
  final int? triggeringRobotId; // robot who reached level 7
  const SelfDestructState({
    required this.active,
    required this.startedAt,
    required this.triggeringRobotId,
  });

  Duration get elapsed => startedAt == null
      ? Duration.zero
      : DateTime.now().difference(startedAt!);
  Duration get total => const Duration(minutes: 17);
  Duration get remaining {
    final r = total - elapsed;
    return r.isNegative ? Duration.zero : r;
  }
}

class SelfDestructController extends StateNotifier<SelfDestructState> {
  SelfDestructController()
      : super(const SelfDestructState(active: false, startedAt: null, triggeringRobotId: null));

  RealtimeChannel? _channel;
  Timer? _tick;
  bool _bound = false;

  Future<void> bind() async {
    if (_bound) return;
    _bound = true;
    await _initialCheck();
    _subscribe();
    _startTicker();
  }

  Future<void> _initialCheck() async {
    try {
      final res = await sb
          .from('kenz_score')
          .select('level_num, created_at, robot_id')
          .gte('level_num', 7)
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();
      if (res != null) {
        final created = res['created_at']?.toString();
        DateTime? started;
        if (created != null && created.isNotEmpty) {
          try {
            started = DateTime.parse(created).toLocal();
          } catch (_) {}
        }
        started ??= DateTime.now();
        final trigId = (res['robot_id'] as num?)?.toInt();
        state = SelfDestructState(active: true, startedAt: started, triggeringRobotId: trigId);
      }
    } catch (_) {
      // ignore errors – fail-safe later via realtime
    }
  }

  void _subscribe() {
    _channel = sb
        .channel('public:kenz_score')
        ..onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'kenz_score',
          callback: (payload) {
            final newRow = payload.newRecord;
            final ln = (newRow['level_num'] as num?)?.toInt() ?? 0;
            if (ln >= 7 && !state.active) {
              DateTime? started;
              final created = newRow['created_at']?.toString();
              if (created != null && created.isNotEmpty) {
                try {
                  started = DateTime.parse(created).toLocal();
                } catch (_) {}
              }
              started ??= DateTime.now();
              final trigId = (newRow['robot_id'] as num?)?.toInt();
              state = SelfDestructState(active: true, startedAt: started, triggeringRobotId: trigId);
            }
          },
        )
        .subscribe();
  }

  void _startTicker() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      // trigger rebuilds while active to update countdown
      if (state.active) {
        state = SelfDestructState(
          active: state.active,
          startedAt: state.startedAt,
          triggeringRobotId: state.triggeringRobotId,
        );
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    if (_channel != null) {
      try {
        sb.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }
    super.dispose();
  }
}

final selfDestructProvider =
    StateNotifierProvider<SelfDestructController, SelfDestructState>((ref) {
  return SelfDestructController();
});

Future<Penalty?> fetchPenalty(int robotId, int levelId) async {
  final res = await sb
      .from('kenz_penalties')
      .select('penalty_until')
      .eq('robot_id', robotId)
      .eq('level_id', levelId)
      .order('penalty_until', ascending: false)
      .limit(1)
      .maybeSingle();
  if (res == null) return null;
  final until = DateTime.parse(res['penalty_until'] as String);
  return Penalty(until);
}

Future<void> setPenalty(int robotId, int levelId, Duration d) async {
  final until = DateTime.now().add(d).toUtc().toIso8601String();
  // upsert
  await sb.from('kenz_penalties').insert({
    'robot_id': robotId,
    'level_id': levelId,
    'penalty_until': until,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class KenzApp extends StatelessWidget {
  const KenzApp({super.key});
  @override
  Widget build(BuildContext context) {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    return MaterialApp(
      title: 'Kenz Robots',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1022),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          onPrimary: Colors.black,
          secondary: Color(0xFF7C4DFF),
          onSecondary: Colors.white,
          surface: Color(0xFF0E1430),
          onSurface: Colors.white,
          error: Color(0xFFFF4081),
          onError: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00E5FF),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white38),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFF00E5FF), width: 1.4),
          ),
          hintStyle: const TextStyle(color: Colors.white70),
        ),
      ),
      builder: (context, child) {
        // Global overlays and watchers
        return Material(
          child: Stack(
            children: [
              if (child != null) child,
              // existing floating penalty overlay (non-blocking)
              const _PenaltyFloatingOverlay(),
              // self-destruct overlay (fully blocks interactions)
              const _SelfDestructOverlay(),
              // watcher to initialize realtime subscription once
              const _SelfDestructWatcher(),
            ],
          ),
        );
      },
      home: const IntroGate(next: ConnectivityGate(child: RobotSelectPage())),
    );
  }
}

// macOS-like floating window with traffic-light controls and glassy chrome
class _MacWindow extends StatelessWidget {
  final String title;
  final double width;
  final double height;
  final Widget child;
  const _MacWindow({
    required this.title,
    required this.width,
    required this.height,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
          gradient: const LinearGradient(
            colors: [Color(0x1413E3FF), Color(0x1000E5FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title bar
            Container(
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                border: const Border(
                  bottom: BorderSide(color: Colors.white24, width: 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  // traffic lights
                  _dot(const Color(0xFFFF5F56)),
                  const SizedBox(width: 6),
                  _dot(const Color(0xFFFFBD2E)),
                  const SizedBox(width: 6),
                  _dot(const Color(0xFF27C93F)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.18),
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 12,
    height: 12,
    decoration: BoxDecoration(
      color: c,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: c.withValues(alpha: 0.6),
          blurRadius: 8,
          spreadRadius: 0.5,
        ),
      ],
    ),
  );
}

class ConnectivityGate extends ConsumerWidget {
  final Widget child;
  const ConnectivityGate({super.key, required this.child});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineOverlayProvider);
    return Material(
      child: Stack(children: [child, if (offline) const OfflineOverlay()]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL FLOATING PENALTY OVERLAY
// ─────────────────────────────────────────────────────────────────────────────
class _PenaltyFloatingOverlay extends ConsumerStatefulWidget {
  const _PenaltyFloatingOverlay();
  @override
  ConsumerState<_PenaltyFloatingOverlay> createState() =>
      _PenaltyFloatingOverlayState();
}

class _PenaltyFloatingOverlayState
    extends ConsumerState<_PenaltyFloatingOverlay> {
  static const Size _panelSize = Size(180, 72);

  @override
  Widget build(BuildContext context) {
    final robot = ref.watch(robotProvider);
    final st = ref.watch(penaltyOverlayProvider);

    // Only show for logged-in users with an active penalty
    if (robot == null || !st.active || st.until == null) {
      return const SizedBox.shrink();
    }

    final media = MediaQuery.of(context);
    final w = media.size.width;
    final h = media.size.height;
    final margin = const EdgeInsets.fromLTRB(
      12,
      72,
      12,
      20,
    ); // keep clear of app bars and edges

    final defaultOffset = Offset(
      w - _panelSize.width - margin.right,
      h - _panelSize.height - margin.bottom,
    );

    // Use stored offset if any
    final currentPos = st.offset ?? defaultOffset;

    Offset clamp(Offset o) {
      final dx = o.dx.clamp(margin.left, w - _panelSize.width - margin.right);
      final dy = o.dy.clamp(margin.top, h - _panelSize.height - margin.bottom);
      return Offset(dx.toDouble(), dy.toDouble());
    }

    final until = st.until!;
    final now = DateTime.now();
    final rem = until.isAfter(now) ? until.difference(now) : Duration.zero;
    final hh = rem.inHours;
    final mm = rem.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = rem.inSeconds.remainder(60).toString().padLeft(2, '0');
    final text = hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';

    return Positioned(
      left: clamp(currentPos).dx,
      top: clamp(currentPos).dy,
      child: _GlassDraggablePanel(
        onDrag: (delta) {
          // Read latest position to avoid stale capture while dragging
          final latest =
              ref.read(penaltyOverlayProvider).offset ?? defaultOffset;
          final next = clamp(latest + delta);
          ref.read(penaltyOverlayProvider.notifier).updateOffset(next);
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.timer_outlined, color: Colors.white, size: 22),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: const Text(
                'Penalty',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassDraggablePanel extends StatelessWidget {
  final Widget child;
  final void Function(Offset delta) onDrag;
  const _GlassDraggablePanel({required this.child, required this.onDrag});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) => onDrag(d.delta),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              constraints: const BoxConstraints(minWidth: 160, minHeight: 56),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class OfflineOverlay extends StatelessWidget {
  const OfflineOverlay({super.key});
  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: true,
      child: Container(
        color: Colors.black.withValues(alpha: 0.75),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: Lottie.asset(
                'assets/lottie/offline.json',
                width: 220,
                repeat: true,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Connection lost',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Please reconnect to continue.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 1 – LOGIN (by robot name + password)
// ─────────────────────────────────────────────────────────────────────────────

class LoginPage extends ConsumerStatefulWidget {
  final String? prefilledName;
  final String? robotImageUrl;
  const LoginPage({super.key, this.prefilledName, this.robotImageUrl});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage>
    with SingleTickerProviderStateMixin {
  final _name = TextEditingController();
  final _pass = TextEditingController();
  final _nameNode = FocusNode();
  final _passNode = FocusNode();

  bool _loading = false;
  bool _obscure = true;

  // Simple, looping controller for background motion
  late final AnimationController _bgCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void initState() {
    super.initState();
    // If a robot name is provided from selection page, prefill and disable editing
    final pre = widget.prefilledName;
    if (pre != null && pre.isNotEmpty) {
      _name.text = pre;
    }
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _name.dispose();
    _pass.dispose();
    _nameNode.dispose();
    _passNode.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await sb
          .from('kenz_robots')
          .select('id,name')
          .eq('name', _name.text.trim())
          .eq('password', _pass.text)
          .limit(1)
          .maybeSingle();

      if (res == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wrong robot name or password')),
          );
        }
        return;
      }

      final robot = Robot(res['id'] as int, res['name'] as String);
      ref.read(robotProvider.notifier).state = robot;
      // Immediately check penalty on login
      await ref.read(penaltyOverlayProvider.notifier).checkForRobot(robot.id);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const ConnectivityGate(child: MapPage()),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: [
          // Back button to return to robot selection
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          // Simple animated background: shifting gradient + drifting soft blobs
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _bgCtrl,
              builder: (context, _) {
                final t = _bgCtrl.value; // 0..1
                final a = t * 2 * pi;

                final begin = Alignment(0.8 * sin(a * 0.8), 0.8 * cos(a * 0.8));
                final end = Alignment(
                  -0.8 * sin(a * 0.6 + 1.0),
                  -0.8 * cos(a * 0.6 + 1.0),
                );

                return Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: begin,
                      end: end,
                      colors: const [Color(0xFF0E1430), Color(0xFF0B1022)],
                    ),
                  ),
                  child: Stack(
                    children: List.generate(3, (i) {
                      // Three slow, drifting soft circles
                      final phase = a + i * 2.1;
                      final align = Alignment(
                        0.85 * sin(phase * (0.5 + i * 0.1)),
                        0.85 * cos(phase * (0.45 + i * 0.08)),
                      );
                      final size = 180.0 + 30.0 * sin(phase);
                      final color = [
                        const Color(0xFF00E5FF),
                        const Color(0xFF7C4DFF),
                        const Color(0xFFFF4081),
                      ][i];

                      return Align(
                        alignment: align,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0.16,
                            child: Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [color, Colors.transparent],
                                  stops: const [0.0, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),
          ),

          // Glass card with form
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.robotImageUrl != null)
                              Animate(
                                onPlay: (c) => c.repeat(reverse: true),
                                effects: [
                                  MoveEffect(
                                    begin: const Offset(0, -6),
                                    end: const Offset(0, 6),
                                    duration: const Duration(seconds: 2),
                                    curve: Curves.easeInOut,
                                  ),
                                ],
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Image.network(
                                    widget.robotImageUrl!,
                                    width: 150,
                                    height: 150,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            if (widget.robotImageUrl == null)
                              Lottie.asset(
                                'assets/lottie/robot_floating.json',
                                width: 150,
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'R•Bots',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 18),
                            TextField(
                              controller: _name,
                              focusNode: _nameNode,
                              textInputAction: TextInputAction.next,
                              onSubmitted: (_) => _passNode.requestFocus(),
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.cyanAccent,
                              enabled: widget.prefilledName == null,
                              readOnly: widget.prefilledName != null,
                              decoration: _glassInputDecoration(
                                label: 'Robot name',
                                icon: Icons.android,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _pass,
                              focusNode: _passNode,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _login(),
                              style: const TextStyle(color: Colors.white),
                              cursorColor: Colors.cyanAccent,
                              decoration:
                                  _glassInputDecoration(
                                    label: 'Password',
                                    icon: Icons.lock_outline,
                                  ).copyWith(
                                    suffixIcon: IconButton(
                                      onPressed: () =>
                                          setState(() => _obscure = !_obscure),
                                      icon: Icon(
                                        _obscure
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _loading ? null : _login,
                                icon: const Icon(Icons.login),
                                label: _loading
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Enter the Arena'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _glassInputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.white70),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.5),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 2 – MAP (Levels 1..7)
// ─────────────────────────────────────────────────────────────────────────────
class MapPage extends ConsumerWidget {
  const MapPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levelsAsync = ref.watch(levelsProvider);
    final robot = ref.watch(robotProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text('Welcome, ${robot?.name ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // Clear user and stop any active penalty overlay before leaving
              ref.read(penaltyOverlayProvider.notifier).stop();
              ref.read(robotProvider.notifier).state = null;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const ConnectivityGate(child: LoginPage()),
                ),
                (r) => false,
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // lively background
          const _ElectricBackground(),
          levelsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
            // Guard against empty levels (e.g., right after logout when robot is null)
            data: (levels) => levels.isEmpty
                ? const SizedBox.shrink()
                : _LevelMap(levels: levels),
          ),
        ],
      ),
    );
  }
}

class _ElectricBackground extends StatefulWidget {
  const _ElectricBackground();
  @override
  State<_ElectricBackground> createState() => _ElectricBackgroundState();
}

class _ElectricBackgroundState extends State<_ElectricBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bgCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 14),
  )..repeat();

  @override
  void dispose() {
    _bgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (context, _) {
        final t = _bgCtrl.value; // 0..1
        final a = t * 2 * pi;

        final begin = Alignment(0.8 * sin(a * 0.8), 0.8 * cos(a * 0.8));
        final end = Alignment(
          -0.8 * sin(a * 0.6 + 1.0),
          -0.8 * cos(a * 0.6 + 1.0),
        );

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: const [Color(0xFF0E1430), Color(0xFF0B1022)],
            ),
          ),
          child: Stack(
            children: List.generate(3, (i) {
              // Three slow, drifting soft neon blobs
              final phase = a + i * 2.1;
              final align = Alignment(
                0.85 * sin(phase * (0.5 + i * 0.1)),
                0.85 * cos(phase * (0.45 + i * 0.08)),
              );
              final size = 220.0 + 40.0 * sin(phase);
              final color = [
                const Color(0xFF00E5FF),
                const Color(0xFF7C4DFF),
                const Color(0xFFFF4081),
              ][i];

              return Align(
                alignment: align,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: 0.14,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [color, Colors.transparent],
                          stops: const [0.0, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _LevelMap extends ConsumerWidget {
  final List<LevelRow> levels;
  const _LevelMap({required this.levels});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final height = c.maxHeight;

        // Create a winding path from bottom to top
        final nodes = List.generate(7, (i) {
          // Start from bottom (index 0) to top (index 6)
          final row = i; // Current row from bottom

          // Vertical position: start from bottom, move up
          final y = height - (80 + (row * (height - 160) / 6));

          // Horizontal position: alternate left-right-center pattern
          double x;
          if (row % 3 == 0) {
            // Left side
            x = width * 0.2;
          } else if (row % 3 == 1) {
            // Right side
            x = width * 0.8;
          } else {
            // Center
            x = width * 0.5;
          }

          switch (row) {
            case 0:
              x -= 10;
              break;
            case 1:
              x += 17;
              break;
            case 2:
              x -= 2;
              break;
            case 3:
              x += 34;
              break;
            case 4:
              x -= 29;
              break;
            case 5:
              x += 15;
              break;
            case 6:
              x += 11;
              break;
          }

          // Add some variation to make it more organic
          final variation = sin(row * pi / 3) * 20;
          x += variation;

          return Offset(x, y);
        });

        return Stack(
          children: [
            // dynamic title
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Lottie.asset('assets/lottie/database.json', height: 160),
              ),
            ),
            // Links
            CustomPaint(
              size: Size.infinite,
              painter: _LinkPainter(nodes),
            ).animate().shimmer(duration: 2400.ms, curve: Curves.easeInOut),
            // Level buttons - starting from bottom
            for (int i = 0; i < 7; i++)
              Positioned(
                left: nodes[i].dx - 34,
                top: nodes[i].dy - 34,
                child: _LevelButton(
                  levelNumber: i + 1,
                  data: levels.firstWhere((e) => e.levelNumber == i + 1),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LinkPainter extends CustomPainter {
  final List<Offset> nodes;
  _LinkPainter(this.nodes);
  @override
  void paint(Canvas canvas, Size size) {
    // Draw glowing circuit-like path connecting nodes
    for (int i = 0; i < nodes.length - 1; i++) {
      final a = nodes[i];
      final b = nodes[i + 1];
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo((a.dx + b.dx) / 2, a.dy - 60, b.dx, b.dy);

      final glow = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);

      final line = Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LevelButton extends ConsumerWidget {
  final int levelNumber;
  final LevelRow data;
  const _LevelButton({required this.levelNumber, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBoss = levelNumber == 7;
    return Hero(
      tag: 'level-$levelNumber',
      child: GestureDetector(
        onTap: () => _onTap(context, ref),
        child: AnimatedContainer(
          duration: 300.ms,
          height: 90,
          width: 90,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Hex/neon chip look using a circle + glow to keep it simple
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: data.unlocked
                        ? [const Color(0xFF00E5FF), const Color(0xFF0E1430)]
                        : [const Color(0xFFFF6F61), const Color(0xFF0E1430)],
                    stops: const [0.0, 1.0],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          (data.unlocked
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFFFF6F61))
                              .withValues(alpha: 0.45),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                  border: Border.all(
                    color: data.unlocked
                        ? const Color(0xFF00E5FF)
                        : const Color(0xFFFF8A80),
                    width: 2,
                  ),
                ),
              ),
              if (!data.unlocked)
                RepaintBoundary(
                  child: SizedBox(
                    width: 58,
                    child: Lottie.asset('assets/lottie/lock.json'),
                  ),
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isBoss ? Icons.memory : Icons.sensors,
                      color: Colors.white,
                      size: 30,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isBoss ? 'CORE' : 'L$levelNumber',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
      ),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    // Enforce lock rules: only pressable if current or already unlocked
    final levels = await ref.read(levelsProvider.future);
    if (!context.mounted) return;
    final robot = ref.read(robotProvider)!;
    // Determine highest solved (unlocked) level
    final maxUnlocked = levels
        .where((e) => e.unlocked)
        .fold<int>(1, (m, e) => max(m, e.levelNumber));
    final isPressable =
        data.levelNumber <= maxUnlocked + 1; // next in chain only
    if (!isPressable) {
      _toast(context, 'Locked. Defeat previous levels first.');
      return;
    }

    // Boss and others require password when levelNumber >= 2 and not yet unlocked
    if (data.levelNumber >= 2 && !data.unlocked) {
      // Check penalty
      final pen = await fetchPenalty(robot.id, data.id);
      if (!context.mounted) return;
      if (pen != null && pen.active) {
        _toast(context, 'Wait ${pen.remaining.inSeconds}s before retry.');
        return;
      }

      final pass = await askPassword(
        context,
        'Enter password for Level ${data.levelNumber}',
      );
      if (pass == null) return;
      final correct = pass == (data.password ?? '');
      if (!correct) {
        // wrong -> increment attempts and set penalty
        final attempts = (data.attempts) + 1;
        await sb
            .from('kenz_levels')
            .update({'attempts': attempts})
            .eq('id', data.id);
        final wait = const Duration(seconds: 30) * pow(2, attempts - 1).toInt();
        await setPenalty(robot.id, data.id, wait);
        if (!context.mounted) return;
        _toast(context, 'Wrong password. Wait ${wait.inSeconds}s');
        // Immediately reflect penalty in the global floating overlay
        await ref.read(penaltyOverlayProvider.notifier).checkForRobot(robot.id);
        ref.invalidate(levelsProvider);
        return;
      }

      // Correct -> unlock this level and clear penalty & attempts
      await sb
          .from('kenz_levels')
          .update({'unlocked': true, 'attempts': 0})
          .eq('id', data.id);
      await sb.from("kenz_score").insert({
        'level_num': data.levelNumber,
        'robot_id': robot.id,
      });
      await setPenalty(robot.id, data.id, Duration.zero); // clear
      ref.invalidate(levelsProvider);
      // If this is the final core memory, show success page
      if (data.levelNumber == 7) {
        if (!context.mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const ConnectivityGate(child: SuccessPage()),
          ),
        );
        return;
      }
    }

    // If player taps level 7 after already unlocked, also show success page
    if (data.levelNumber == 7 && data.unlocked) {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const ConnectivityGate(child: SuccessPage()),
        ),
      );
      return;
    }

    // Open Level page (files)
    // Level 3+ remain locked until each prior unlocked; here we reached allowed path
    // For level 1, unlocked by default in your DB.
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectivityGate(
          child: LevelFilesPage(
            levelNumber: data.levelNumber,
            levelId: data.id,
          ),
        ),
      ),
    );
  }

  Future<String?> askPassword(BuildContext context, String title) {
    // We create the controller here but DO NOT dispose it here.
    // The dialog itself will dispose it in its State.dispose().
    final controller = TextEditingController();

    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Password dialog',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) =>
          FuturisticPasswordDialog(title: title, controller: controller),
    );
  }
}

class FuturisticPasswordDialog extends StatefulWidget {
  final String title;
  final TextEditingController controller;

  const FuturisticPasswordDialog({
    super.key,
    required this.title,
    required this.controller,
  });

  @override
  State<FuturisticPasswordDialog> createState() =>
      _FuturisticPasswordDialogState();
}

class _FuturisticPasswordDialogState extends State<FuturisticPasswordDialog> {
  bool _obscure = true;

  @override
  void dispose() {
    // NOW we dispose the controller – after the reverse animation is done
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 420,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white30),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: widget.controller,
                      obscureText: _obscure,
                      autofocus: true,
                      onSubmitted: (v) => Navigator.of(context).pop(v),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Password',
                        hintStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          color: Colors.white70,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off,
                            color: Colors.white70,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Colors.cyanAccent,
                            width: 1.4,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.of(
                              context,
                            ).pop(widget.controller.text),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                            ),
                            child: const Text('Unlock'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 3 – FILES (per user + per level). Reads from storage and/or kenz_files
// ─────────────────────────────────────────────────────────────────────────────
class LevelFilesPage extends ConsumerStatefulWidget {
  final int levelNumber;
  final int levelId;
  const LevelFilesPage({
    super.key,
    required this.levelNumber,
    required this.levelId,
  });
  @override
  ConsumerState<LevelFilesPage> createState() => _LevelFilesPageState();
}

class _LevelFilesPageState extends ConsumerState<LevelFilesPage> {
  late Future<List<MediaEntry>> _future;
  int _visibleWindows = 0;
  bool _materialsVisible = false;
  final List<Timer> _timers = [];
  final List<_WinGeom> _geoms = [];
  Size? _lastSize;

  String _windowTitleForIndex(int i) {
    switch (i) {
      case 0:
        return 'Hacker';
      case 1:
        return 'Alert';
      case 2:
        return 'Terminal-1';
      case 3:
        return 'Terminal-2';
      case 4:
      default:
        return 'App';
    }
  }

  @override
  void initState() {
    super.initState();
    _future = _load(widget.levelId);
    // When data finishes loading, kick off the window open sequence
    _future.then((_) => _startSequence());
  }

  Future<List<MediaEntry>> _load(int levelId) async {
    // Prefer kenz_files table if present
    try {
      final rows = await sb
          .from('kenz_files')
          .select('path, media_type')
          .eq('level_id', levelId);

      List<MediaEntry> entries = [];
      for (var row in rows) {
        entries.add(
          MediaEntry(
            row['path'] as String,
            (row['media_type'] as String?) ?? 'unknown',
          ),
        );
      }

      return entries;
    } catch (e) {
      debugPrint('No kenz_files table for level $levelId: $e');
      return [];
    }
  }

  void _startSequence() {
    // Reset state
    if (!mounted) return;
    setState(() {
      _visibleWindows = 0;
      _materialsVisible = false;
    });

    // Schedule 5 Lottie windows with fixed delays, then the materials window
    const windowCount = 5;
    var accumulated = 300; // initial delay
    for (var i = 0; i < windowCount; i++) {
      const delta = 500; // fixed 500ms between windows
      accumulated += delta;
      _timers.add(
        Timer(Duration(milliseconds: accumulated), () {
          if (!mounted) return;
          setState(() => _visibleWindows = i + 1);
        }),
      );
    }

    // Show materials after a fixed delay
    accumulated += 800; // fixed 800ms extra
    _timers.add(
      Timer(Duration(milliseconds: accumulated), () {
        if (!mounted) return;
        setState(() => _materialsVisible = true);
      }),
    );
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Level ${widget.levelNumber} · Hack Desktop')),
      body: Stack(
        children: [
          const _ElectricBackground(),

          FutureBuilder<List<MediaEntry>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }
              final items = snap.data ?? <MediaEntry>[];

              // Build stacked windows
              return LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final h = c.maxHeight;
                  final size = Size(w, h);
                  final needsRecalc =
                      _lastSize == null || _lastSize != size || _geoms.isEmpty;
                  if (needsRecalc) {
                    _lastSize = size;
                    _geoms.clear();
                    // Precompute geometry for 5 windows in diverse, larger positions
                    const marginH = 12.0;
                    const marginVTop = 72.0;
                    const marginVBottom = 12.0;
                    final usableW = w - marginH * 2;
                    final usableH = h - marginVTop - marginVBottom;

                    // Normalized layout specs: left%, top%, width%, height% (bigger windows)
                    final layouts = <Map<String, double>>[
                      {
                        'l': 0.01,
                        't': 0.03,
                        'w': 0.58,
                        'h': 0.42,
                      }, // top-left very large
                      {
                        'l': 0.50,
                        't': 0.02,
                        'w': 0.54,
                        'h': 0.44,
                      }, // top-right very large
                      {
                        'l': 0.04,
                        't': 0.50,
                        'w': 0.52,
                        'h': 0.46,
                      }, // bottom-left very large
                      {
                        'l': 0.48,
                        't': 0.52,
                        'w': 0.54,
                        'h': 0.40,
                      }, // bottom-right larger
                      {
                        'l': 0.18,
                        't': 0.22,
                        'w': 0.70,
                        'h': 0.52,
                      }, // center-ish overlay, biggest
                    ];

                    for (var i = 0; i < 5; i++) {
                      final title = _windowTitleForIndex(i);
                      var minW = 340.0, minH = 220.0;
                      switch (title) {
                        case 'Hacker':
                          minW = 360;
                          minH = 240;
                          break;
                        case 'Alert':
                          minW = 320;
                          minH = 220;
                          break;
                        case 'Terminal-1':
                          minW = 380;
                          minH = 260;
                          break;
                        case 'Terminal-2':
                          minW = 340;
                          minH = 240;
                          break;
                        case 'App':
                          minW = 360;
                          minH = 240;
                          break;
                      }

                      final spec = layouts[i];
                      // Screen-relative max clamps to avoid overflow
                      final maxWClamp = (usableW * 0.92);
                      final maxHClamp = (usableH * 0.86);
                      final minWClamp = minW <= maxWClamp ? minW : maxWClamp;
                      final minHClamp = minH <= maxHClamp ? minH : maxHClamp;
                      var ww = (spec['w']! * usableW).clamp(
                        minWClamp,
                        maxWClamp,
                      );
                      var hh = (spec['h']! * usableH).clamp(
                        minHClamp,
                        maxHClamp,
                      );
                      var l = marginH + spec['l']! * usableW;
                      var t = marginVTop + spec['t']! * usableH;

                      // Clamp into viewport with margins
                      l = l.clamp(12.0, w - ww - 12.0);
                      t = t.clamp(72.0, h - hh - 12.0);
                      const rot = 0.0;
                      _geoms.add(
                        _WinGeom(
                          l: l,
                          t: t,
                          w: ww,
                          h: hh,
                          rot: rot,
                          title: title,
                        ),
                      );
                    }
                  }

                  // Lottie window specs (title, asset)
                  final windows = <Map<String, String>>[
                    {'t': 'Hacker', 'a': 'assets/lottie/hacker.json'},
                    {'t': 'Alert', 'a': 'assets/lottie/alert.json'},
                    {'t': 'Terminal-1', 'a': 'assets/lottie/terminal_1.json'},
                    {'t': 'Terminal-2', 'a': 'assets/lottie/terminal_2.json'},
                    {'t': 'App', 'a': 'assets/lottie/app.json'},
                  ];

                  final stackChildren = <Widget>[];

                  // Add Lottie windows, revealed sequentially (using cached geometry; fixed positions/sizes)
                  final count = _visibleWindows.clamp(0, windows.length);
                  for (var i = 0; i < count; i++) {
                    final title = _geoms[i].title;
                    // Size ranges per window type for richer variety
                    final ww = _geoms[i].w;
                    final hh = _geoms[i].h;
                    final l = _geoms[i].l;
                    final t = _geoms[i].t;
                    final rot = _geoms[i].rot; // no rotation (deterministic)
                    stackChildren.add(
                      Positioned(
                        left: l,
                        top: t,
                        child: Transform.rotate(
                          angle: rot,
                          child: _MacWindow(
                            title: title,
                            width: ww,
                            height: hh,
                            child: RepaintBoundary(
                              child: Lottie.asset(
                                windows[i]['a']!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  // Top-most window: materials grid (appears last)
                  final materials = Positioned(
                    left: 12,
                    right: 12,
                    top: 12,
                    bottom: 12,
                    child: _materialsVisible
                        ? _MacWindow(
                            title: 'Materials · Decrypted',
                            width: w - 24,
                            height: h - 24,
                            child: items.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No materials yet for this level',
                                    ),
                                  )
                                : GridView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      8,
                                      12,
                                      16,
                                    ),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 2,
                                          childAspectRatio: 1.05,
                                          crossAxisSpacing: 14,
                                          mainAxisSpacing: 14,
                                        ),
                                    itemCount: items.length,
                                    itemBuilder: (context, i) =>
                                        _MediaCard(entry: items[i]),
                                  ),
                          )
                        : const SizedBox.shrink(),
                  );

                  stackChildren.add(materials);
                  return Stack(children: stackChildren);
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MediaCard extends ConsumerWidget {
  final MediaEntry entry;
  const _MediaCard({required this.entry});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final url = await sb.storage
            .from(storageBucket)
            .createSignedUrl(entry.path, 60 * 30);
        if (!context.mounted) return;
        final mime = entry.mediaType.toLowerCase();
        final top = mime.contains('/') ? mime.split('/')[0] : mime;
        final sub = mime.contains('/') ? mime.split('/')[1] : '';
        final ext = p.extension(entry.path).toLowerCase();

        final isImage = top == 'image' || mime.startsWith('image/');
        final isVideo = top == 'video' || mime.startsWith('video/');
        final isAudio = top == 'audio' || mime.startsWith('audio/');
        final isPdf =
            mime == 'application/pdf' || sub == 'pdf' || ext == '.pdf';
        final isText = top == 'text' || sub == 'plain' || ext == '.txt';
        final isJson = mime == 'application/json' || sub == 'json' || ext == '.json';

        if (isImage) {
          // ignore: use_build_context_synchronously
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => ImageViewer(url: url)));
        } else if (isVideo) {
          // ignore: use_build_context_synchronously
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => VideoViewer(url: url)));
        } else if (isAudio) {
          // ignore: use_build_context_synchronously
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => AudioViewer(url: url)));
        } else if (isPdf) {
          // ignore: use_build_context_synchronously
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => PdfViewer(url: url)));
        } else if (isText) {
          // ignore: use_build_context_synchronously
          Navigator.of(
            context,
          ).push(
            MaterialPageRoute(
              builder: (_) => TextViewer(
                url: url,
                name: p.basename(entry.path),
              ),
            ),
          );
        } else if (isJson) {
          final fname = p.basename(entry.path);
          final stem = p.basenameWithoutExtension(fname);
          final isPassblocks = RegExp(r'^passblocks\d*$', caseSensitive: false).hasMatch(stem);
          if (isPassblocks) {
            if (!context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PassblocksViewer(url: url, name: fname),
              ),
            );
            return;
          }

          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Unsupported file'),
              content: Text(
                'Cannot preview non passblocks json files.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else {
          // Unsupported type: keep user inside app and show info
          if (!context.mounted) return;
          // ignore: use_build_context_synchronously
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Unsupported file'),
              content: Text(
                'Cannot preview this file type (MIME: $mime, ext: $ext).',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.5),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
          gradient: const LinearGradient(
            colors: [Color(0x1913E3FF), Color(0x1200E5FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: RepaintBoundary(
                  child: Lottie.asset(
                    'assets/lottie/card_bg.json',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.6),
                  ),
                ),
                child: const Text(
                  'DECRYPTED',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _iconFor(entry.mediaType),
                    size: 46,
                    color: const Color(0xFF00E5FF),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.basename(entry.path),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String t) {
    final mime = t.toLowerCase();
    final top = mime.contains('/') ? mime.split('/')[0] : mime;
    final sub = mime.contains('/') ? mime.split('/')[1] : '';
    if (top == 'image' || mime.startsWith('image/')) return Icons.image;
    if (top == 'video' || mime.startsWith('video/')) return Icons.videocam;
    if (top == 'audio' || mime.startsWith('audio/')) return Icons.audiotrack;
    if (mime == 'application/pdf' || sub == 'pdf') return Icons.picture_as_pdf;
    if (top == 'text' || sub == 'plain') return Icons.description;
    return Icons.insert_drive_file;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEDIA VIEWERS
// ─────────────────────────────────────────────────────────────────────────────
class ImageViewer extends StatefulWidget {
  final String url;
  const ImageViewer({super.key, required this.url});
  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final TransformationController _transformationController;
  static const double _minScale = 0.5;
  static const double _maxScale = 5.0;
  static const double _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  void _handleDoubleTap() {
    final current = _transformationController.value;
    // Toggle between identity and a preset zoom level centered
    if (!mounted) return;
    setState(() {
      if (current.storage[0] > 1.01) {
        _transformationController.value = Matrix4.identity();
      } else {
        _transformationController.value = Matrix4.identity()..scale(_doubleTapScale);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Reset zoom',
            onPressed: _resetZoom,
            icon: const Icon(Icons.zoom_out_map),
          ),
        ],
      ),
      body: GestureDetector(
        onDoubleTap: _handleDoubleTap,
        child: InteractiveViewer(
          transformationController: _transformationController,
          minScale: _minScale,
          maxScale: _maxScale,
          panEnabled: true,
          scaleEnabled: true,
          boundaryMargin: const EdgeInsets.all(80),
          clipBehavior: Clip.none,
          child: Center(
            child: Image.network(
              widget.url,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const SizedBox.expand(
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              errorBuilder: (context, error, stack) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Failed to load image'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class VideoViewer extends StatefulWidget {
  final String url;
  const VideoViewer({super.key, required this.url});
  @override
  State<VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<VideoViewer> {
  VideoPlayerController? _controller;
  ChewieController? _chewie;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        setState(() {});
        _chewie = ChewieController(
          videoPlayerController: _controller!,
          autoPlay: true,
          looping: false,
        );
        setState(() {});
      });
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: _chewie == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: Center(child: Chewie(controller: _chewie!)),
                ),
                // Video progress bar
                /*if (_controller != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _VideoProgressBar(controller: _controller!),
                  ),*/
                SizedBox(height: 36,)
              ],
            ),
    );
  }
}

class AudioViewer extends StatefulWidget {
  final String url;
  const AudioViewer({super.key, required this.url});
  @override
  State<AudioViewer> createState() => _AudioViewerState();
}

class _AudioViewerState extends State<AudioViewer> {
  late final AudioPlayer _player;
  @override
  void initState() {
    super.initState();
    _player = AudioPlayer()..setUrl(widget.url).then((_) => _player.play());
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.audiotrack, size: 96),
            // Audio progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _AudioProgressBar(player: _player),
            ),
            const SizedBox(height: 8),
            StreamBuilder<PlayerState>(
              stream: _player.playerStateStream,
              builder: (context, snap) {
                final playing = snap.data?.playing ?? false;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () =>
                          playing ? _player.pause() : _player.play(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.restart_alt),
                      tooltip: 'Restart',
                      onPressed: () => _player.seek(Duration.zero),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioProgressBar extends StatelessWidget {
  final AudioPlayer player;
  const _AudioProgressBar({required this.player});

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final dur = player.duration ?? Duration.zero;
        final max = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
        final value = pos.inMilliseconds.clamp(0, dur.inMilliseconds).toDouble();
        return Column(
          children: [
            Slider(
              min: 0,
              max: max,
              value: value.isFinite ? value : 0,
              onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(pos), style: const TextStyle(color: Colors.white70)),
                Text(_fmt(dur), style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _VideoProgressBar extends StatefulWidget {
  final VideoPlayerController controller;
  const _VideoProgressBar({required this.controller});

  @override
  State<_VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<_VideoProgressBar> {
  late final Stream<Duration> _posStream;

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  void initState() {
    super.initState();
    _posStream = Stream<Duration>.periodic(
      const Duration(milliseconds: 250),
      (_) => widget.controller.value.position,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dur = widget.controller.value.duration;
    return StreamBuilder<Duration>(
      stream: _posStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final d = dur;
        final max = d.inMilliseconds > 0 ? d.inMilliseconds.toDouble() : 1.0;
        final value = pos.inMilliseconds.clamp(0, d.inMilliseconds).toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Slider(
              min: 0,
              max: max,
              value: value.isFinite ? value : 0,
              onChanged: (v) => widget.controller.seekTo(
                Duration(milliseconds: v.round()),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmt(pos), style: const TextStyle(color: Colors.white70)),
                Text(_fmt(d), style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ],
        );
      },
    );
  }
}

class PdfViewer extends StatefulWidget {
  final String url;
  const PdfViewer({super.key, required this.url});
  @override
  State<PdfViewer> createState() => _PdfViewerState();
}

class _PdfViewerState extends State<PdfViewer> {
  PdfControllerPinch? _controller;
  @override
  void initState() {
    super.initState();
    _controller = PdfControllerPinch(
      document: PdfDocument.openData(_networkData(widget.url)),
    );
  }

  static Future<Uint8List> _networkData(String url) async {
    // We already have a signed URL. Fetch bytes and render with pdfx.
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      final bytes = await consolidateHttpClientResponseBytes(response);
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: _controller == null
          ? const Center(child: CircularProgressIndicator())
          : PdfViewPinch(controller: _controller!),
    );
  }
}

class TextViewer extends StatelessWidget {
  final String url;
  final String? name; // used to choose between 'cmd' and 'code' modes
  const TextViewer({super.key, required this.url, this.name});
  Future<String> _load(String url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      final bytes = await consolidateHttpClientResponseBytes(resp);
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = (name ?? '').toLowerCase();
    final stem = base.isEmpty ? '' : p.basenameWithoutExtension(base);
    final isCmd = RegExp(r'^cmd\d*$', caseSensitive: false).hasMatch(stem);
    final isCode = RegExp(r'^code\d*$', caseSensitive: false).hasMatch(stem);
    return Scaffold(
      backgroundColor: isCmd ? Colors.black : const Color(0xFF0E1430),
      appBar: AppBar(
        backgroundColor: isCmd ? Colors.black : const Color(0xFF0E1430),
        title: Text(
          isCode ? (name ?? 'code') : 'Console',
          style: TextStyle(color: isCmd ? const Color(0xFF00FF66) : Colors.white),
        ),
      ),
      body: FutureBuilder<String>(
        future: _load(url),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (isCode) {
            return _CodeTypingEditor(text: snap.data!, filename: name ?? 'code');
          }
          // Default to hacker console when explicitly 'cmd' or unknown text
          return _HackerTypingConsole(text: snap.data!);
        },
      ),
    );
  }
}

class _HackerTypingConsole extends StatefulWidget {
  final String text;
  final Duration charDelay;
  const _HackerTypingConsole({
    required this.text,
    this.charDelay = const Duration(milliseconds: 14),
  });

  @override
  State<_HackerTypingConsole> createState() => _HackerTypingConsoleState();
}

class _HackerTypingConsoleState extends State<_HackerTypingConsole> {
  late final ScrollController _scrollController;
  Timer? _timer;
  int _index = 0;
  bool _cursorOn = true;
  Timer? _cursorTimer;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _timer = Timer.periodic(widget.charDelay, (t) {
      if (!mounted) return;
      if (_index >= widget.text.length) {
        t.cancel();
      } else {
        setState(() {
          _index++;
        });
        // Auto scroll to bottom as content grows
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
    _cursorTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      setState(() => _cursorOn = !_cursorOn);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cursorTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shown = _index.clamp(0, widget.text.length);
    final visibleText = widget.text.substring(0, shown);
    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: visibleText,
                style: const TextStyle(
                  color: Color(0xFF00FF66),
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.4,
                  shadows: [
                    Shadow(color: Color(0x8000FF66), blurRadius: 8),
                  ],
                ),
              ),
              TextSpan(
                text: _cursorOn ? '█' : ' ',
                style: const TextStyle(
                  color: Color(0xFF00FF66),
                  fontFamily: 'monospace',
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE 4 – SUCCESS (Robot recovered memory)
// ─────────────────────────────────────────────────────────────────────────────
class SuccessPage extends StatelessWidget {
  const SuccessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated gradient background similar to login/map
          const _ElectricBackground(),

          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(color: Colors.white30),
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 30,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Lottie.asset(
                            'assets/lottie/center_robot.json',
                            height: 140,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Memory Restored!',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.cyanAccent,
                                ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Great job! You cracked the final password.\n'
                            'Kenz Robot has recovered all lost data.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pushAndRemoveUntil(
                                    MaterialPageRoute(
                                      builder: (_) => const ConnectivityGate(
                                        child: MapPage(),
                                      ),
                                    ),
                                    (r) => false,
                                  );
                                },
                                icon: const Icon(Icons.map_outlined),
                                label: const Text('Back to Map'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UTILS
// ─────────────────────────────────────────────────────────────────────────────
double? lerpDouble(num? a, num? b, double t) {
  if (a == null && b == null) return null;
  a ??= 0.0;
  b ??= 0.0;
  return a * (1.0 - t) + b * t;
}
