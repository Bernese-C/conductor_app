import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'camera_preview_widget.dart';
import 'conductor_logic.dart';
import 'hand_tracker.dart';
import 'midi_player.dart';
import 'music_library.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ConductorApp());
}

class ConductorApp extends StatelessWidget {
  const ConductorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConductorLogic()),
        ChangeNotifierProvider(create: (_) => MusicLibrary()),
      ],
      child: MaterialApp(
        title: '指挥家',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.deepPurple,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const ConductorPage(),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Main page
// ═════════════════════════════════════════════════════════════════════════════

class ConductorPage extends StatefulWidget {
  const ConductorPage({super.key});

  @override
  State<ConductorPage> createState() => _ConductorPageState();
}

class _ConductorPageState extends State<ConductorPage>
    with WidgetsBindingObserver {
  late final HandTracker _handTracker;
  final MidiPlayer _midiPlayer = MidiPlayer();

  StreamSubscription<double>? _ySubscription;
  Timer? _syncTimer;

  bool _isInitializing = true;
  bool _audioOn = false;
  bool _userInteracted = false; // for web autoplay policy
  String? _errorMessage;

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handTracker = createHandTracker();
    _initAll();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _ySubscription?.cancel();
    _handTracker.dispose();
    _midiPlayer.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _handTracker.stop();
      _midiPlayer.pause();
    } else if (state == AppLifecycleState.resumed) {
      _handTracker.start();
      if (_audioOn) _midiPlayer.play();
    }
  }

  // ── Initialisation ─────────────────────────────────────────────────────

  Future<void> _initAll() async {
    try {
      await _handTracker.initialize();
      await _midiPlayer.initialize(
        source: context.read<MusicLibrary>().activeSource,
      );
      await _handTracker.start();

      _ySubscription = _handTracker.yStream.listen((y) {
        if (!mounted) return;
        context.read<ConductorLogic>().processY(y);
      });

      final logic = context.read<ConductorLogic>();
      logic.onConductingStarted = () {
        // Only web browsers require a user gesture before audio.
        // On native platforms, auto-play works fine.
        if (!_userInteracted && kIsWeb) {
          debugPrint('Conductor: auto-play blocked — need user gesture first');
          return;
        }
        _midiPlayer.play();
        setState(() => _audioOn = true);
      };
      logic.onConductingStopped = () {
        _midiPlayer.pause();
        setState(() => _audioOn = false);
      };

      _syncTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted) return;
        final l = context.read<ConductorLogic>();
        _midiPlayer.syncToConductor(l.avgBpm, l.volume);
      });

      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      debugPrint('Initialisation error: $e');
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  // ── Music source change handler ────────────────────────────────────────

  Future<void> _onMusicSourceChanged(MusicSource source) async {
    await _midiPlayer.loadSource(source);
  }

  // ── Mouse tracking (desktop) ───────────────────────────────────────────

  void _onMouseY(double normalizedY) {
    if (!mounted) return;
    context.read<ConductorLogic>().processY(normalizedY);
  }

  // ── Manual audio toggle ────────────────────────────────────────────────

  Future<void> _toggleAudio() async {
    _userInteracted = true; // satisfies browser autoplay policy
    if (_audioOn) {
      await _midiPlayer.pause();
    } else {
      await _midiPlayer.play();
    }
    setState(() => _audioOn = !_audioOn);
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(title: const Text('指挥家')),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在初始化...'),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('指挥家')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '初始化失败:\n$_errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ),
      );
    }

    final musicLib = context.watch<MusicLibrary>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('指挥家'),
        centerTitle: true,
        actions: [
          // Music source selector button.
          IconButton(
            icon: const Icon(Icons.library_music),
            tooltip: '选择音乐',
            onPressed: () => _showMusicSelector(context, musicLib),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(_audioOn ? Icons.volume_up : Icons.volume_off),
            tooltip: _audioOn ? '手动暂停' : '手动播放',
            onPressed: _toggleAudio,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Consumer<ConductorLogic>(
              builder: (_, logic, __) {
                return CameraPreviewWidget(
                  cameraController: _handTracker.cameraController,
                  trackedY: logic.isTracking ? logic.currentY : null,
                  onMouseYChanged:
                      isDesktopPlatform ? _onMouseY : null,
                );
              },
            ),
          ),

          const Divider(height: 1),

          Expanded(
            flex: 2,
            child: Consumer<ConductorLogic>(
              builder: (_, logic, __) => _Dashboard(
                logic: logic,
                trackingMode: _handTracker.trackingModeLabel,
                musicLib: musicLib,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Music selector bottom sheet ───────────────────────────────────────

  void _showMusicSelector(BuildContext context, MusicLibrary lib) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _MusicSelectorSheet(
        library: lib,
        onSourceChanged: _onMusicSourceChanged,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Dashboard
// ═════════════════════════════════════════════════════════════════════════════

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.logic, required this.musicLib, required this.trackingMode});
  final ConductorLogic logic;
  final MusicLibrary musicLib;
  final String trackingMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ConductorStateIndicator(state: logic.conductorState),
          const SizedBox(height: 8),
          // Current track name.
          Text(
            musicLib.activeSource.name,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Text(
            logic.isTracking ? logic.avgBpm.toStringAsFixed(0) : '--',
            style: theme.textTheme.displayLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          Text('BPM',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 10),
          _BpmBar(bpm: logic.isTracking ? logic.avgBpm : 120),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.volume_down,
                  color: theme.colorScheme.onSurfaceVariant, size: 16),
              const SizedBox(width: 6),
              SizedBox(
                width: 140,
                child: LinearProgressIndicator(
                  value: logic.isTracking ? logic.volume : 0.5,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.volume_up,
                  color: theme.colorScheme.onSurfaceVariant, size: 16),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${logic.playbackRate.toStringAsFixed(2)}x  |  '
            '$trackingMode  |  '
            '节拍 #${logic.beatCount}',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Conductor state indicator
// ═════════════════════════════════════════════════════════════════════════════

class _ConductorStateIndicator extends StatelessWidget {
  const _ConductorStateIndicator({required this.state});
  final ConductorState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color color;
    String label;
    IconData icon;

    switch (state) {
      case ConductorState.idle:
        color = Colors.grey;
        label = '抬手开始指挥';
        icon = Icons.touch_app;
      case ConductorState.ready:
        color = Colors.amber;
        label = '准备就绪 — 请挥拍';
        icon = Icons.visibility;
      case ConductorState.conducting:
        color = Colors.green;
        label = '正在指挥';
        icon = Icons.music_note;
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14, height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: state == ConductorState.conducting ? 12 : 6,
                spreadRadius: state == ConductorState.conducting ? 3 : 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Music selector bottom sheet
// ═════════════════════════════════════════════════════════════════════════════

class _MusicSelectorSheet extends StatefulWidget {
  const _MusicSelectorSheet({
    required this.library,
    required this.onSourceChanged,
  });
  final MusicLibrary library;
  final ValueChanged<MusicSource> onSourceChanged;

  @override
  State<_MusicSelectorSheet> createState() => _MusicSelectorSheetState();
}

class _MusicSelectorSheetState extends State<_MusicSelectorSheet> {
  final _urlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _addUrl() async {
    final url = _urlCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (url.isEmpty) return;

    await widget.library.addUrl(
      name.isEmpty ? _extractName(url) : name,
      url,
    );

    if (widget.library.error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.library.error!)),
      );
      widget.library.clearError();
    }

    if (widget.library.activeSource.type == MusicSourceType.url && mounted) {
      widget.onSourceChanged(widget.library.activeSource);
    }
    _urlCtrl.clear();
    _nameCtrl.clear();
  }

  String _extractName(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final segs = uri.pathSegments;
      if (segs.isNotEmpty) return segs.last;
    }
    return url.length > 40 ? '${url.substring(0, 40)}...' : url;
  }

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('选择音乐源', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),

          // ── Source list ──────────────────────────────────────────
          ...lib.sources.map((s) {
            final isActive = s == lib.activeSource;
            return ListTile(
              leading: Icon(
                isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isActive ? theme.colorScheme.primary : null,
              ),
              title: Text(s.name, style: theme.textTheme.bodyMedium,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: s.type == MusicSourceType.builtIn
                  ? const Text('内置旋律')
                  : Text(s.url ?? '', maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              onTap: () {
                lib.selectSource(s);
                widget.onSourceChanged(s);
                Navigator.pop(context);
              },
              dense: true,
            );
          }),

          const Divider(),
          const SizedBox(height: 8),

          // ── Add URL ─────────────────────────────────────────────
          Text('添加音频 URL', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              hintText: '名称（可选）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlCtrl,
            decoration: InputDecoration(
              hintText: 'https://...mp3',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: lib.isLoading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ))
                  : IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _addUrl,
                    ),
            ),
            keyboardType: TextInputType.url,
            onSubmitted: (_) => _addUrl(),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BPM horizontal bar
// ═════════════════════════════════════════════════════════════════════════════

class _BpmBar extends StatelessWidget {
  const _BpmBar({required this.bpm});
  final double bpm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final double fraction = ((bpm - 40) / (300 - 40)).clamp(0.0, 1.0);

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.green, Colors.yellow, Colors.red],
                        stops: [0.0, 0.5, 1.0],
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('40', style: theme.textTheme.labelSmall),
            Text('120', style: theme.textTheme.labelSmall),
            Text('300', style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}
