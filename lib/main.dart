import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const LocationBackgroundApp());

class LocationBackgroundApp extends StatelessWidget {
  const LocationBackgroundApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: '位置后台演示',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF006C67)),
      useMaterial3: true,
    ),
    home: const LocationBackgroundPage(),
  );
}

class LocationBackgroundPage extends StatefulWidget {
  const LocationBackgroundPage({super.key});

  @override
  State<LocationBackgroundPage> createState() => _LocationBackgroundPageState();
}

class _LocationBackgroundPageState extends State<LocationBackgroundPage>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('location_baohuo/background_location');
  Timer? _refreshTimer;
  bool _loading = true;
  bool _running = false;
  String _authorization = '未请求';
  int _minuteCount = 0;
  int _locationEvents = 0;
  DateTime? _lastTickAt;
  DateTime? _lastLocationAt;
  String _location = '尚无位置';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final state = await _channel.invokeMapMethod<String, dynamic>('status');
      if (!mounted || state == null) return;
      setState(() {
        _applyState(state);
        _loading = false;
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? error.code);
    }
  }

  Future<void> _call(String method) async {
    setState(() => _loading = true);
    try {
      final state = await _channel.invokeMapMethod<String, dynamic>(method);
      if (!mounted || state == null) return;
      setState(() {
        _applyState(state);
        _error = null;
      });
    } on PlatformException catch (error) {
      if (mounted) setState(() => _error = error.message ?? error.code);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyState(Map<String, dynamic> state) {
    _running = state['running'] == true;
    _authorization = state['authorization'] as String? ?? '未知';
    _minuteCount = (state['minuteCount'] as num?)?.toInt() ?? 0;
    _locationEvents = (state['locationEvents'] as num?)?.toInt() ?? 0;
    _lastTickAt = _toDate(state['lastTickAt']);
    _lastLocationAt = _toDate(state['lastLocationAt']);
    final lat = state['latitude'] as num?;
    final lng = state['longitude'] as num?;
    _location = lat == null || lng == null
        ? '尚无位置'
        : '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}';
  }

  DateTime? _toDate(Object? value) => value is num && value > 0
      ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
      : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('iOS 后台定位计数 Demo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('每分钟计数', style: theme.textTheme.titleMedium),
            Text('$_minuteCount', style: theme.textTheme.displayLarge),
            Text(_running ? '位置更新已开启' : '位置更新未开启'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loading
                  ? null
                  : () => _call(_running ? 'stop' : 'start'),
              icon: Icon(_running ? Icons.stop : Icons.location_searching),
              label: Text(_running ? '停止' : '授权并开启定位'),
            ),
            const SizedBox(height: 24),
            _Info(label: '定位权限', value: _authorization),
            _Info(label: '位置回调数', value: '$_locationEvents'),
            _Info(label: '最后位置', value: _location),
            _Info(label: '最后计数', value: _format(_lastTickAt)),
            _Info(label: '最后定位', value: _format(_lastLocationAt)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              '仅用于具有真实后台定位需求的应用。iOS 不能保证任意定时器在后台持续运行，位置事件和计数会受系统调度、权限与实际移动情况影响。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  String _format(DateTime? time) {
    if (time == null) return '无';
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}
