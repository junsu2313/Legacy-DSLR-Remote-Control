import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'camera_api.dart';

class ExposureOption {
  const ExposureOption(this.label, this.value);

  final String label;
  final int value;
}

const apertureOptions = <ExposureOption>[
  ExposureOption('F2.8', 280),
  ExposureOption('F3.2', 320),
  ExposureOption('F3.5', 350),
  ExposureOption('F4', 400),
  ExposureOption('F4.5', 450),
  ExposureOption('F5', 500),
  ExposureOption('F5.6', 560),
  ExposureOption('F6.3', 630),
  ExposureOption('F7.1', 710),
  ExposureOption('F8', 800),
  ExposureOption('F9', 900),
  ExposureOption('F10', 1000),
  ExposureOption('F11', 1100),
  ExposureOption('F13', 1300),
  ExposureOption('F14', 1400),
  ExposureOption('F16', 1600),
  ExposureOption('F18', 1800),
  ExposureOption('F20', 2000),
  ExposureOption('F22', 2200),
];

const shutterOptions = <ExposureOption>[
  ExposureOption('1/8000', 1),
  ExposureOption('1/4000', 2),
  ExposureOption('1/3200', 3),
  ExposureOption('1/2500', 4),
  ExposureOption('1/2000', 5),
  ExposureOption('1/1600', 6),
  ExposureOption('1/1250', 8),
  ExposureOption('1/1000', 10),
  ExposureOption('1/800', 12),
  ExposureOption('1/640', 15),
  ExposureOption('1/500', 20),
  ExposureOption('1/400', 25),
  ExposureOption('1/320', 31),
  ExposureOption('1/250', 40),
  ExposureOption('1/200', 50),
  ExposureOption('1/160', 62),
  ExposureOption('1/125', 80),
  ExposureOption('1/100', 100),
  ExposureOption('1/80', 125),
  ExposureOption('1/60', 166),
  ExposureOption('1/50', 200),
  ExposureOption('1/40', 250),
  ExposureOption('1/30', 333),
  ExposureOption('1/25', 400),
  ExposureOption('1/20', 500),
  ExposureOption('1/15', 666),
  ExposureOption('1/13', 769),
  ExposureOption('1/10', 1000),
  ExposureOption('1/8', 1250),
  ExposureOption('1/6', 1666),
  ExposureOption('1/5', 2000),
  ExposureOption('1/4', 2500),
  ExposureOption('1/3', 3333),
  ExposureOption('1/2', 5000),
  ExposureOption('1s', 10000),
  ExposureOption('2s', 20000),
  ExposureOption('4s', 40000),
  ExposureOption('8s', 80000),
  ExposureOption('15s', 150000),
  ExposureOption('30s', 300000),
];

const isoOptions = <ExposureOption>[
  ExposureOption('ISO 64', 64),
  ExposureOption('ISO 80', 80),
  ExposureOption('ISO 100', 100),
  ExposureOption('ISO 125', 125),
  ExposureOption('ISO 160', 160),
  ExposureOption('ISO 200', 200),
  ExposureOption('ISO 250', 250),
  ExposureOption('ISO 320', 320),
  ExposureOption('ISO 400', 400),
  ExposureOption('ISO 500', 500),
  ExposureOption('ISO 640', 640),
  ExposureOption('ISO 800', 800),
  ExposureOption('ISO 1000', 1000),
  ExposureOption('ISO 1250', 1250),
  ExposureOption('ISO 1600', 1600),
  ExposureOption('ISO 2000', 2000),
  ExposureOption('ISO 2500', 2500),
  ExposureOption('ISO 3200', 3200),
  ExposureOption('ISO 4000', 4000),
  ExposureOption('ISO 5000', 5000),
  ExposureOption('ISO 6400', 6400),
  ExposureOption('ISO 8000', 8000),
  ExposureOption('ISO 10000', 10000),
  ExposureOption('ISO 12800', 12800),
  ExposureOption('ISO 16000', 16000),
  ExposureOption('ISO 20000', 20000),
  ExposureOption('ISO 25600', 25600),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const UnderlabCameraApp());
}

class UnderlabCameraApp extends StatelessWidget {
  const UnderlabCameraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'D810 Remote Camera',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: Colors.black,
          colorScheme: const ColorScheme.dark(
            primary: Colors.white,
            surface: Color(0xff080808),
          ),
          fontFamily: 'monospace',
        ),
        home: const CameraHomePage(),
      );
}

class CameraHomePage extends StatefulWidget {
  const CameraHomePage({super.key});

  @override
  State<CameraHomePage> createState() => _CameraHomePageState();
}

class _CameraHomePageState extends State<CameraHomePage>
    with WidgetsBindingObserver {
  late final CameraApi _cameraApi;
  String lastAction = 'SYNCING';
  bool cameraReady = false;
  bool cameraDetected = false;
  bool hardwareDetected = false;
  bool transportReady = false;
  bool commandReady = false;
  bool liveViewReady = false;
  bool liveViewLimited = false;
  String liveViewLimitReason = '';
  bool faultActive = false;
  String faultDomain = 'none';
  String faultStage = 'none';
  String faultReason = 'none';
  bool _goodVisible = false;
  bool _recoveryTimedOut = false;
  bool liveView = false;
  String readinessState = 'detecting';
  String readinessReason = '';
  String readinessPhase = '';
  String readinessDetail = '';
  int readyAfterMs = 0;
  int readinessAverageMs = 0;
  bool manualMode = false;
  int exposureMode = 3;
  int aperture = 400;
  int shutter = 166;
  int iso = 400;
  int? actualIso;
  int captureMode = 0;
  bool autoIso = true;
  Uint8List? capturedPreview;
  int? batteryPercent;
  Timer? _statusTimer;
  Timer? _manualStatusTimer;
  Timer? _captureEventTimer;
  Timer? _goodTimer;
  Timer? _recoveryTimeoutTimer;
  Timer? _lowBatteryNoticeTimer;
  int _runtimeSyncGeneration = 0;
  int _runtimeStatusFailures = 0;
  int _liveIntentGeneration = 0;
  int _captureEventSeq = 0;
  bool _captureEventBaselineReady = false;
  bool _captureEventPollBusy = false;
  bool _manualStatusBusy = false;
  Future<Uint8List>? _capturedPreviewInFlight;
  final Set<String> _pendingCommands = {};
  final Set<String> _pendingSettings = {};
  final Map<String, int> _draftSettings = {};
  final Map<String, int> _settingGeneration = {};
  bool _menuValuePending = false;
  String? _menuPendingSetting;
  String? _menuPendingValue;
  bool _lowBatteryNoticeVisible = false;

  static const int _liveViewBatteryLimit = 20;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cameraApi = CameraApi();
    unawaited(_bootstrapProjectRuntime());
    unawaited(_refreshManualStatus());
    _statusTimer = Timer.periodic(
      // While the app is assembling its camera runtime, the status control
      // must advance quickly enough to describe the stage the user is seeing.
      const Duration(seconds: 2),
      (_) => unawaited(_syncRuntimeStatus()),
    );
    _captureEventTimer = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => unawaited(_pollCaptureEvents()),
    );
    _manualStatusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) {
        if (cameraReady && _pendingSettings.isEmpty) {
          unawaited(_refreshManualStatus(silent: true));
        }
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncRuntimeStatus());
      unawaited(_refreshManualStatus());
      unawaited(_pollCaptureEvents());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    _manualStatusTimer?.cancel();
    _captureEventTimer?.cancel();
    _goodTimer?.cancel();
    _recoveryTimeoutTimer?.cancel();
    _lowBatteryNoticeTimer?.cancel();
    _cameraApi.close();
    super.dispose();
  }

  Future<void> _pollCaptureEvents() async {
    if (_captureEventPollBusy || !mounted) return;
    _captureEventPollBusy = true;
    try {
      final event = await _cameraApi.captureEvents();
      if (event.propertyChanged) {
        // This reuses the lightweight PTP event poll without touching the LV
        // frame path. AUTO ISO's actual capture value is resolved from EXIF.
        unawaited(_refreshManualStatus(silent: true));
      }
      if (!_captureEventBaselineReady) {
        _captureEventSeq = event.captureEventSeq;
        _captureEventBaselineReady = true;
        return;
      }
      if (!event.captureEvent || event.captureEventSeq == _captureEventSeq) {
        return;
      }
      _captureEventSeq = event.captureEventSeq;
      final preview = await _loadCapturedPreview();
      if (!mounted) return;
      setState(() {
        capturedPreview = preview;
        lastAction = 'SIDE SHUTTER';
      });
    } catch (_) {
      // Event polling is opportunistic; the normal status loop remains the
      // source of truth for camera connectivity.
    } finally {
      _captureEventPollBusy = false;
    }
  }

  Future<void> _bootstrapProjectRuntime() async {
    lastAction = 'PROJECT BOOT…';
    try {
      await _cameraApi.bootstrapRuntime();
      if (!mounted) return;
      await _syncRuntimeStatus(updateLabel: true, force: true);
      await _loadInitialGalleryPreview();
    } catch (_) {
      if (!mounted) return;
      await _syncRuntimeStatus(updateLabel: true, force: true);
      await _loadInitialGalleryPreview();
    }
  }

  Future<void> _loadInitialGalleryPreview() async {
    if (!mounted || !cameraReady || capturedPreview != null) return;
    try {
      final preview = await _loadCapturedPreview();
      if (!mounted || capturedPreview != null) return;
      setState(() => capturedPreview = preview);
    } catch (_) {
      // An empty camera card is valid when the camera has no captured media.
    }
  }

  Future<void> _syncRuntimeStatus({
    bool updateLabel = false,
    bool force = false,
  }) async {
    if (!force &&
        (_pendingCommands.contains('LIVE') ||
            _pendingCommands.contains('STOP'))) {
      return;
    }
    final generation = ++_runtimeSyncGeneration;
    try {
      final status = await _cameraApi.runtimeStatus();
      if (!mounted || generation != _runtimeSyncGeneration) return;
      final hadFault = faultActive;
      final recovered = hadFault && !status.faultActive && status.fullyReady;
      setState(() {
        _runtimeStatusFailures = 0;
        cameraReady = status.fullyReady;
        cameraDetected = status.cameraDetected;
        hardwareDetected = status.hardwareDetected;
        transportReady = status.transportReady;
        commandReady = status.commandReady;
        liveViewReady = status.liveViewReady;
        liveViewLimited = status.liveViewLimited;
        liveViewLimitReason = status.liveViewLimitReason;
        faultActive = status.faultActive;
        faultDomain = status.faultDomain;
        faultStage = status.faultStage;
        faultReason = status.faultReason;
        liveView = status.liveView;
        readinessState = status.readinessState;
        readinessReason = status.readinessReason;
        readinessPhase = status.uiPhase;
        readinessDetail = status.uiDetail;
        readyAfterMs = status.readyAfterMs;
        readinessAverageMs = status.readinessAverageMs;
        batteryPercent = status.batteryPercent;
        if (status.faultActive) {
          _goodVisible = false;
          if (!hadFault) _beginRecoveryWatchdog();
        } else {
          _recoveryTimeoutTimer?.cancel();
          _recoveryTimedOut = false;
        }
        if (updateLabel) {
          if (status.fullyReady) {
            lastAction = status.liveView ? 'LIVE ACTIVE' : 'CAMERA READY';
          } else if (status.readinessState == 'offline') {
            lastAction = 'CAMERA OFFLINE';
          } else {
            lastAction = 'CAMERA ${status.readinessState.toUpperCase()}';
          }
        }
      });
      if (status.fullyReady && capturedPreview == null) {
        unawaited(_loadInitialGalleryPreview());
      }
      if (recovered) _showGoodState();
    } catch (_) {
      if (!mounted || generation != _runtimeSyncGeneration) return;
      setState(() {
        _runtimeStatusFailures++;
        // One lost status packet must not tear down a healthy stream.
        if (_runtimeStatusFailures >= 3) {
          cameraReady = false;
          cameraDetected = false;
          hardwareDetected = false;
          transportReady = false;
          commandReady = false;
          liveViewReady = false;
          liveView = false;
          readinessState = 'offline';
          readinessReason = 'status_unavailable';
          readinessPhase = 'Offline';
          readinessDetail = 'Camera runtime status is unavailable';
        }
        if (updateLabel && _runtimeStatusFailures >= 3) {
          lastAction = 'CAMERA OFFLINE';
        }
      });
    }
  }

  void _beginRecoveryWatchdog() {
    _recoveryTimeoutTimer?.cancel();
    _recoveryTimedOut = false;
    _recoveryTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || !faultActive) return;
      setState(() => _recoveryTimedOut = true);
    });
  }

  void _showGoodState() {
    _goodTimer?.cancel();
    if (!mounted) return;
    setState(() => _goodVisible = true);
    _goodTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _goodVisible = false);
    });
  }

  String _faultStageLabel(String stage) => switch (stage) {
        'camera' => '카메라',
        'ptp' => 'PTP',
        'command' => '커맨드',
        'live_view' => '라이브뷰',
        'application' => '어플리케이션',
        _ => '시스템',
      };

  String _faultReasonLabel(String reason) => switch (reason) {
        'camera_usb_not_detected' => '카메라 USB 장치를 발견하지 못했습니다.',
        'hardware_not_detected' => '카메라 하드웨어가 확인되지 않습니다.',
        'project_transport_unavailable' => 'PTP 전송 서비스를 사용할 수 없습니다.',
        'ddserver_not_running' => '카메라 전송 서비스가 실행되지 않았습니다.',
        'transport_not_ready' => 'PTP 세션이 준비되지 않았습니다.',
        'command_not_ready' => '카메라 명령 세션이 준비되지 않았습니다.',
        'live_view_not_ready' => '라이브뷰 프레임 전달이 준비되지 않았습니다.',
        'duplicate_bridge_process' => '중복 브리지 프로세스가 발견되었습니다.',
        'bridge_unavailable' => '카메라 브리지가 응답하지 않습니다.',
        _ => '해당 단계의 준비 상태가 일치하지 않습니다.',
      };

  void command(String value) {
    if (value == 'LIVE' && liveViewLimited) {
      _lowBatteryNoticeTimer?.cancel();
      setState(() => _lowBatteryNoticeVisible = true);
      _lowBatteryNoticeTimer = Timer(const Duration(milliseconds: 2800), () {
        if (mounted) setState(() => _lowBatteryNoticeVisible = false);
      });
      return;
    }
    final action = <String, String>{
      'AF': 'af',
      'LIVE': 'live-on',
      'STOP': 'live-off',
      'DIAGNOSE': 'diagnose',
    }[value];
    if (action == null) return;
    if (_pendingCommands.contains(value)) return;
    final isLiveTransition = value == 'LIVE' || value == 'STOP';
    final liveIntent = isLiveTransition ? ++_liveIntentGeneration : null;
    setState(() {
      _pendingCommands.add(value);
      lastAction = '$value…';
      // Fence the local WebView before asking the server to stop. LIVE is
      // enabled only after the authoritative server status confirms it.
      if (value == 'STOP') {
        liveView = false;
        // Ignore a status response that began before this STOP intent.
        _runtimeSyncGeneration++;
      }
    });
    unawaited(_runCameraAction(value, action, liveIntent: liveIntent));
  }

  String _cameraFailureLabel(Object error, String fallback) {
    if (error is CameraApiException) {
      return switch (error.status) {
        'focus_failed' => 'FOCUS FAILED',
        'capture_missing' => 'IMAGE NOT SAVED',
        'camera_busy' => 'CAMERA BUSY',
        _ => fallback,
      };
    }
    return fallback;
  }

  String _diagnosisResultLabel(Map<String, dynamic> result) {
    final message = result['diagnosisMessage']?.toString();
    if (message != null && message.isNotEmpty) return message;
    if (result['recovered'] == true) return 'RECOVERY COMPLETE';
    if (result['recoveryOwner'] == 'user') return 'USER ACTION REQUIRED';
    return 'SYSTEM READY';
  }

  Future<void> _showDiagnosisResult(Map<String, dynamic> result) async {
    final userActionRequired = result['recoveryOwner'] == 'user';
    final diagnosisMessage = result['diagnosisMessage']?.toString() ??
        '진단 결과를 확인해 주세요.';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: AlertDialog(
          title: Text(userActionRequired ? '사용자 조치 필요' : '진단 및 복구 완료'),
          content: Text(diagnosisMessage),
          actions: const [],
        ),
      ),
    );
  }

  Future<void> _runCameraAction(
    String label,
    String action, {
    int? liveIntent,
  }) async {
    final traceId = _cameraApi.newTraceId('ui-$action');
    Object? failure;
    Map<String, dynamic>? result;
    try {
      if (action == 'diagnose') {
        result = await _cameraApi.diagnose(traceId: traceId);
      } else {
        await _cameraApi.action(action, traceId: traceId);
      }
    } catch (error) {
      failure = error;
    } finally {
      if (mounted) {
        final isCurrentIntent =
            liveIntent == null || liveIntent == _liveIntentGeneration;
        setState(() {
          _pendingCommands.remove(label);
          if (isCurrentIntent) {
            lastAction = failure != null
                ? _cameraFailureLabel(failure, '$label ERROR')
                : result != null
                    ? _diagnosisResultLabel(result)
                    : label;
          }
        });
        if (isCurrentIntent) {
          await _syncRuntimeStatus(force: true);
        }
        if (result != null && mounted) {
          await _showDiagnosisResult(result);
        }
      }
    }
  }

  Future<Uint8List> _loadCapturedPreview({String? traceId}) async {
    final existing = _capturedPreviewInFlight;
    if (existing != null) return existing;

    late Future<Uint8List> request;
    request = _loadCapturedPreviewOnce(traceId: traceId);
    _capturedPreviewInFlight = request;
    try {
      return await request;
    } finally {
      if (identical(_capturedPreviewInFlight, request)) {
        _capturedPreviewInFlight = null;
      }
    }
  }

  Future<Uint8List> _loadCapturedPreviewOnce({String? traceId}) async {
    Object? lastError;
    // Probe immediately, then keep polling through the D810's variable SD-card
    // commit interval. This shortens the best case without giving up too early
    // when a larger JPEG takes longer to expose its thumbnail.
    for (final delay in const [0, 100, 180, 300, 480, 700]) {
      if (delay > 0) {
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      try {
        return await _cameraApi.capturedPreview(traceId: traceId);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? StateError('captured_preview_unavailable');
  }

  Future<void> _refreshManualStatus({bool silent = false}) async {
    if (_manualStatusBusy) return;
    _manualStatusBusy = true;
    try {
      final status = await _cameraApi.manualStatus();
      if (!mounted) return;
      setState(() {
        manualMode = status.manualMode;
        exposureMode = status.mode;
        aperture = status.aperture;
        shutter = status.shutter;
        iso = status.configuredIso != 0 ? status.configuredIso : status.iso;
        actualIso = status.actualIso;
        captureMode = status.captureMode;
        autoIso = status.autoIso;
        lastAction = status.manualMode ? 'M READY' : 'SET DIAL TO M';
      });
    } catch (_) {
      if (!mounted) return;
      if (!silent) setState(() => lastAction = 'SETTINGS ERROR');
      unawaited(_syncRuntimeStatus());
    } finally {
      _manualStatusBusy = false;
    }
  }

  int _steppedValue(List<ExposureOption> options, int current, int stepDelta) {
    final index = options.indexWhere((option) => option.value == current);
    final start = index < 0 ? 0 : index;
    final next = (start + stepDelta) % options.length;
    return options[next < 0 ? next + options.length : next].value;
  }

  void stepManualSetting(String key, int stepDelta) {
    if (!manualMode) {
      setState(() => lastAction = 'TAP M');
      return;
    }
    if (stepDelta == 0) return;
    final options = switch (key) {
      'aperture' => apertureOptions,
      'shutter' => shutterOptions,
      _ => isoOptions,
    };
    final current = _draftSettings[key] ??
        switch (key) {
          'aperture' => aperture,
          'shutter' => shutter,
          _ => iso,
        };
    final next = _steppedValue(options, current, stepDelta);
    setState(() {
      _draftSettings[key] = next;
      if (key == 'aperture') aperture = next;
      if (key == 'shutter') shutter = next;
      if (key == 'iso') iso = next;
      _pendingSettings.add(key);
      lastAction = '${key.toUpperCase()} READY';
    });
  }

  void confirmManualSetting(String key) {
    if (key.isEmpty) return;
    if (!_pendingSettings.contains(key) || !_draftSettings.containsKey(key)) {
      return;
    }
    unawaited(_applyManualSetting(key, _draftSettings[key]!));
  }

  Future<void> enterManualMode() async {
    if (manualMode || _pendingSettings.contains('mode')) return;
    setState(() {
      _pendingSettings.add('mode');
      lastAction = 'M MODE…';
    });
    try {
      final confirmedMode = await _cameraApi.setManualMode();
      if (!mounted) return;
      setState(() {
        exposureMode = confirmedMode;
        manualMode = confirmedMode == 1;
        _pendingSettings.remove('mode');
        lastAction = manualMode ? 'M READY' : 'MODE ERROR';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pendingSettings.remove('mode');
        lastAction = 'MODE ERROR';
      });
      unawaited(_refreshManualStatus());
    }
  }

  Future<void> _applyManualSetting(String key, int value) async {
    final generation = (_settingGeneration[key] ?? 0) + 1;
    _settingGeneration[key] = generation;
    setState(() {
      _draftSettings[key] = value;
      _pendingSettings.add(key);
      lastAction = '${key.toUpperCase()}…';
    });
    try {
      final status = await _cameraApi.setManualSettingAndVerify(key, value);
      if (!mounted || _settingGeneration[key] != generation) return;
      setState(() {
        aperture = status.aperture;
        shutter = status.shutter;
        iso = status.iso;
        _draftSettings.remove(key);
        _pendingSettings.remove(key);
        manualMode = status.manualMode;
        lastAction = '${key.toUpperCase()} CONFIRMED';
      });
    } on CameraApiException catch (error) {
      if (!mounted || _settingGeneration[key] != generation) return;
      setState(() {
        _pendingSettings.remove(key);
        _draftSettings.remove(key);
        if (error.status == 'manual_mode_required') manualMode = false;
        lastAction = error.status == 'manual_mode_required'
            ? 'SET DIAL TO M'
            : '${key.toUpperCase()} ERROR';
      });
      unawaited(_refreshManualStatus());
    } catch (_) {
      if (!mounted || _settingGeneration[key] != generation) return;
      setState(() {
        _pendingSettings.remove(key);
        _draftSettings.remove(key);
        lastAction = '${key.toUpperCase()} ERROR';
      });
      unawaited(_refreshManualStatus());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LandscapeLayout(
            liveView: liveView,
            cameraReady: cameraReady,
            cameraDetected: cameraDetected,
            hardwareDetected: hardwareDetected,
            transportReady: transportReady,
            commandReady: commandReady,
            liveViewReady: liveViewReady,
            liveViewLimited: liveViewLimited,
            liveViewLimitReason: liveViewLimitReason,
            recovering: faultActive ||
                readinessState == 'degraded' ||
                (cameraDetected && hardwareDetected && !cameraReady),
            goodVisible: _goodVisible,
            faultActive: faultActive,
            faultDomain: faultDomain,
            faultStage: faultStage,
            faultReason: faultReason,
            readinessState: readinessState,
            readinessReason: readinessReason,
            readinessPhase: readinessPhase,
            readinessDetail: readinessDetail,
            readyAfterMs: readyAfterMs,
            readinessAverageMs: readinessAverageMs,
            recoveryTimedOut: _recoveryTimedOut,
            onCommand: command,
            manualMode: manualMode,
            exposureMode: exposureMode,
            aperture: aperture,
            shutter: shutter,
            iso: iso,
            actualIso: actualIso,
            captureMode: captureMode,
            autoIso: autoIso,
            pendingSettings: _pendingSettings,
            capturedPreview: capturedPreview,
            batteryPercent: batteryPercent,
            lowBatteryNoticeVisible: _lowBatteryNoticeVisible,
            diagnosing: _pendingCommands.contains('DIAGNOSE'),
            onOpenPreview: _showFullSizePreview,
            onSettingsOpened: _refreshManualStatus,
            onManualMode: enterManualMode,
            onManualSetting: stepManualSetting,
            onConfirmSetting: (key) => confirmManualSetting(key),
            onMenuValueChanged: _onMenuValueChanged,
            menuValuePending: _menuValuePending,
            onConfirmMenuValue: _confirmMenuValue,
          ),
        ),
      );

  Future<void> _showFullSizePreview() async {
    final thumbnail = capturedPreview;
    if (thumbnail == null) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => CapturedImageViewer(
        previewBytes: thumbnail,
        loadImages: _cameraApi.capturedImages,
        loadThumbnail: _cameraApi.capturedThumbnail,
        loadFullSize: _cameraApi.capturedObject,
        loadFullSizeProgress: _cameraApi.capturedObjectWithProgress,
      ),
    );
  }

  void _onMenuValueChanged(String setting, String value) {
    setState(() {
      _menuValuePending = true;
      _menuPendingSetting = setting;
      _menuPendingValue = value;
      lastAction = '$setting READY';
    });
  }

  void _confirmMenuValue() {
    final setting = _menuPendingSetting;
    final value = _menuPendingValue;
    if (!_menuValuePending || setting == null || value == null) return;
    if (setting == 'ISO 감도 제어') {
      final enabled = switch (value) {
        '자동' => true,
        '수동' => false,
        _ => null,
      };
      if (enabled != null) {
        setState(() => _menuValuePending = false);
        unawaited(_applyAutoIso(enabled));
        return;
      }
    }
    if (setting == 'ISO 감도') {
      final numericIso = int.tryParse(value);
      if (numericIso != null) {
        if (!manualMode) {
          setState(() => lastAction = 'TAP M');
          return;
        }
        setState(() => _menuValuePending = false);
        unawaited(_applyManualSetting('iso', numericIso));
        return;
      }
    }
    setState(() {
      _menuValuePending = false;
      lastAction = '$setting CONFIRMED';
    });
  }

  Future<void> _applyAutoIso(bool enabled) async {
    try {
      await _cameraApi.setAutoIso(enabled);
      if (!mounted) return;
      setState(() {
        autoIso = enabled;
        lastAction = enabled ? 'ISO AUTO CONFIRMED' : 'ISO MANUAL CONFIRMED';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => lastAction = 'ISO AUTO ERROR');
    }
  }
}

class LandscapeLayout extends StatefulWidget {
  const LandscapeLayout({
    required this.liveView,
    required this.cameraReady,
    required this.recovering,
    required this.goodVisible,
    required this.recoveryTimedOut,
    required this.cameraDetected,
    required this.hardwareDetected,
    required this.transportReady,
    required this.commandReady,
    required this.liveViewReady,
    required this.liveViewLimited,
    required this.liveViewLimitReason,
    required this.faultActive,
    required this.faultDomain,
    required this.faultStage,
    required this.faultReason,
    required this.readinessState,
    required this.readinessReason,
    required this.readinessPhase,
    required this.readinessDetail,
    required this.readyAfterMs,
    required this.readinessAverageMs,
    required this.onCommand,
    required this.manualMode,
    required this.exposureMode,
    required this.aperture,
    required this.shutter,
    required this.iso,
    required this.actualIso,
    required this.captureMode,
    required this.autoIso,
    required this.pendingSettings,
    required this.onSettingsOpened,
    required this.onManualMode,
    required this.onManualSetting,
    required this.onConfirmSetting,
    required this.onMenuValueChanged,
    required this.menuValuePending,
    required this.onConfirmMenuValue,
    required this.capturedPreview,
    required this.onOpenPreview,
    required this.batteryPercent,
    required this.lowBatteryNoticeVisible,
    required this.diagnosing,
    super.key,
  });
  final bool liveView;
  final bool cameraReady;
  final bool recovering;
  final bool goodVisible;
  final bool recoveryTimedOut;
  final bool cameraDetected;
  final bool hardwareDetected;
  final bool transportReady;
  final bool commandReady;
  final bool liveViewReady;
  final bool liveViewLimited;
  final String liveViewLimitReason;
  final bool faultActive;
  final String faultDomain;
  final String faultStage;
  final String faultReason;
  final String readinessState;
  final String readinessReason;
  final String readinessPhase;
  final String readinessDetail;
  final int readyAfterMs;
  final int readinessAverageMs;
  final ValueChanged<String> onCommand;
  final bool manualMode;
  final int exposureMode;
  final int aperture;
  final int shutter;
  final int iso;
  final int? actualIso;
  final int captureMode;
  final bool autoIso;
  final Set<String> pendingSettings;
  final VoidCallback onSettingsOpened;
  final VoidCallback onManualMode;
  final void Function(String key, int stepDelta) onManualSetting;
  final ValueChanged<String> onConfirmSetting;
  final void Function(String setting, String value) onMenuValueChanged;
  final bool menuValuePending;
  final VoidCallback onConfirmMenuValue;
  final Uint8List? capturedPreview;
  final VoidCallback onOpenPreview;
  final int? batteryPercent;
  final bool lowBatteryNoticeVisible;
  final bool diagnosing;

  @override
  State<LandscapeLayout> createState() => _LandscapeLayoutState();
}

class _LandscapeLayoutState extends State<LandscapeLayout> {
  static const MethodChannel _layoutChannel = MethodChannel('underlab/layout');
  static const Offset _previewPeekOffset = Offset(0, -76);
  static const List<String> _editableControlIds = [
    'af',
    'diagnose',
    'live',
    'stop',
    'dial',
    'ok',
    'preview_top',
  ];

  bool _showSettings = false;
  bool _showMenu = false;
  bool _showImageControlPanel = false;
  double _imageControlPanelLeft = -200;
  bool _menuExpanded = false;
  bool _editing = false;
  bool _layoutSaving = false;
  bool _layoutTouched = false;
  bool _previewVisible = false;
  bool _cameraStatusExpanded = false;
  Timer? _previewHideTimer;
  double _fps = 0;
  double _pendingFps = 0;
  bool _fpsUpdateQueued = false;
  final Map<String, Offset> _controlOffsets = {};

  @override
  void didUpdateWidget(covariant LandscapeLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.capturedPreview != null &&
        widget.capturedPreview != oldWidget.capturedPreview) {
      _revealPreview();
    }
  }

  Offset _offset(String id) => _controlOffsets[id] ?? Offset.zero;
  void _move(String id, Offset delta) {
    _layoutTouched = true;
    setState(() => _controlOffsets[id] = _offset(id) + delta);
  }

  void _revealPreview() {
    _previewHideTimer?.cancel();
    if (mounted) setState(() => _previewVisible = true);
    _previewHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_editing) setState(() => _previewVisible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadLayout());
  }

  @override
  void dispose() {
    _previewHideTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLayout() async {
    try {
      final saved =
          await _layoutChannel.invokeMapMethod<Object?, Object?>('load');
      if (!mounted || _layoutTouched || saved == null) return;
      final restored = <String, Offset>{};
      for (final entry in saved.entries) {
        final id = entry.key;
        final coordinates = entry.value;
        if (id is! String || coordinates is! List || coordinates.length < 2) {
          continue;
        }
        final x = coordinates[0];
        final y = coordinates[1];
        if (x is num && y is num) {
          restored[id] = Offset(x.toDouble(), y.toDouble());
        }
      }
      setState(() => _controlOffsets.addAll(restored));
    } on PlatformException {
      // Keep the default layout if this device cannot restore saved positions.
    }
  }

  Future<void> _toggleEditing() async {
    if (_layoutSaving) return;
    if (!_editing) {
      setState(() {
        _editing = true;
        _previewVisible = true;
      });
      return;
    }

    setState(() => _layoutSaving = true);
    try {
      final positions = <String, List<double>>{
        for (final id in _editableControlIds)
          id: [_offset(id).dx, _offset(id).dy],
      };
      final saved = await _layoutChannel.invokeMethod<bool>('save', positions);
      if (!mounted) return;
      if (saved == true) {
        setState(() {
          _editing = false;
          _previewVisible = false;
          _layoutSaving = false;
          _layoutTouched = false;
        });
        return;
      }
    } on PlatformException {
      // Keep edit mode open so the user does not lose unsaved positioning.
    }
    if (mounted) setState(() => _layoutSaving = false);
  }

  void _onFps(double value) {
    _pendingFps = value;
    if (_fpsUpdateQueued) return;
    _fpsUpdateQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fpsUpdateQueued = false;
      if (!mounted || _fps == _pendingFps) return;
      setState(() => _fps = _pendingFps);
    });
  }

  void _toggleSettings() {
    final opening = !_showSettings;
    setState(() => _showSettings = opening);
    if (opening) widget.onSettingsOpened();
  }

  void _openMenu() {
    setState(() {
      if (!_showMenu) {
        _showMenu = true;
        _menuExpanded = false;
      } else {
        _menuExpanded = !_menuExpanded;
      }
    });
  }

  void _openImageControlPanel() {
    setState(() {
      _showImageControlPanel = true;
      _imageControlPanelLeft = 0;
      _showSettings = false;
      _showMenu = false;
      _menuExpanded = false;
    });
  }

  void _dragImageControlPanel(DragUpdateDetails details) {
    setState(() {
      _imageControlPanelLeft = (_imageControlPanelLeft + details.delta.dx)
          .clamp(-200.0, 0.0)
          .toDouble();
    });
  }

  void _finishImageControlPanelDrag(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    final open = velocity > 0
        ? true
        : velocity < 0
            ? false
            : _imageControlPanelLeft > -100;
    setState(() {
      _showImageControlPanel = open;
      _imageControlPanelLeft = open ? 0 : -200;
    });
  }

  void _closeMenu() {
    if (_showMenu) {
      setState(() {
        _showMenu = false;
        _menuExpanded = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Stack(
                fit: StackFit.expand,
                children: [
                  ImageControlPreviewLayer(
                    child: LiveViewFrame(
                      active: widget.liveView,
                      onFps: _onFps,
                    ),
                  ),
                  if (widget.liveView)
                    const Center(
                        child: SizedBox(
                            width: 68,
                            height: 52,
                            child: CustomPaint(painter: FocusPainter()))),
                ],
              ),
              if (widget.capturedPreview != null)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: TweenAnimationBuilder<Offset>(
                      key: ValueKey(_previewVisible),
                      tween: Tween<Offset>(
                        begin: _previewVisible
                            ? _previewPeekOffset
                            : _offset('preview_top'),
                        end: _previewVisible || _editing
                            ? _offset('preview_top')
                            : _previewPeekOffset,
                      ),
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutBack,
                      builder: (context, offset, child) => Transform.translate(
                        offset: offset,
                        child: child,
                      ),
                      child: GestureDetector(
                        onPanUpdate: _editing
                            ? (details) => _move('preview_top', details.delta)
                            : null,
                        child: ShotThumbnail(
                          imageBytes: widget.capturedPreview!,
                          onTap: _editing ? null : widget.onOpenPreview,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                left: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LandscapePill(label: 'ADC', onTap: _toggleSettings),
                    const SizedBox(width: 6),
                    LandscapePill(
                        label: _menuExpanded ? 'MENU-E' : 'MENU',
                        onTap: _openMenu),
                    const SizedBox(width: 6),
                    LandscapePill(label: 'I.C.', onTap: _openImageControlPanel),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: LandscapePill(
                    label: _layoutSaving
                        ? 'SAVING'
                        : _editing
                            ? 'SAVE'
                            : 'EDIT',
                    onTap: _toggleEditing),
              ),
              Positioned(
                right: 22,
                bottom: 88,
                child: Transform.translate(
                  offset: _offset('af'),
                  child: AfSlideControl(
                    editing: _editing,
                    onFocus: () => widget.onCommand('AF'),
                    onMove: (delta) => _move('af', delta),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                bottom: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CameraReadinessControl(
                          ready: widget.cameraReady,
                          recovering: widget.recovering,
                          goodVisible: widget.goodVisible,
                          warning: widget.liveViewLimited,
                          recoveryTimedOut: widget.recoveryTimedOut,
                          onTap: _editing
                              ? () {}
                              : () => setState(() {
                                    _cameraStatusExpanded =
                                        !_cameraStatusExpanded;
                                  }),
                        ),
                        const SizedBox(height: 7),
                        EditableLandscapeControl(
                          id: 'diagnose',
                          offset: _offset('diagnose'),
                          editing: _editing,
                          onMove: _move,
                          child: LandscapeControl(
                            label: 'DIAG',
                            caption: 'recover',
                            onTap: _editing
                                ? () {}
                                : () => widget.onCommand('DIAGNOSE'),
                            active: widget.diagnosing,
                          ),
                        ),
                      ],
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.centerLeft,
                      child: _cameraStatusExpanded
                          ? Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: CameraReadinessDetails(
                                cameraReady: widget.cameraReady,
                                cameraDetected: widget.cameraDetected,
                                hardwareDetected: widget.hardwareDetected,
                                transportReady: widget.transportReady,
                                commandReady: widget.commandReady,
                                liveViewReady: widget.liveViewReady,
                                liveViewLimited: widget.liveViewLimited,
                                liveViewLimitReason: widget.liveViewLimitReason,
                                faultActive: widget.faultActive,
                                faultStage: widget.faultStage,
                                faultReason: widget.faultReason,
                                recoveryTimedOut: widget.recoveryTimedOut,
                                readyAfterMs: widget.readyAfterMs,
                                readinessAverageMs: widget.readinessAverageMs,
                                batteryPercent: widget.batteryPercent,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 90 + MediaQuery.sizeOf(context).height * .05,
                height: 32,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedSlide(
                      offset: widget.lowBatteryNoticeVisible
                          ? Offset.zero
                          : const Offset(0, 1.15),
                      duration: const Duration(milliseconds: 560),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: widget.lowBatteryNoticeVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeInOut,
                        child: const OverlayBadge(
                          label: '',
                          value: '배터리 부족!',
                          danger: true,
                          warning: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 46,
                child: OverlayBadge(
                  label: 'BATTERY',
                  value: widget.batteryPercent == null
                      ? '--'
                      : '${widget.batteryPercent}%',
                  danger: widget.batteryPercent != null &&
                      widget.batteryPercent! <= 20,
                ),
              ),
              Positioned(
                right: 16,
                bottom: 80,
                child: OverlayBadge(
                  label: 'RELEASE',
                  value: _releaseModeLabel(widget.captureMode),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 20,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      EditableLandscapeControl(
                          id: 'live',
                          offset: _offset('live'),
                          editing: _editing,
                          onMove: _move,
                          child: LandscapeControl(
                            key: const Key('live-control'),
                            label: 'LIVE',
                            caption: 'start',
                            onTap: _editing
                                ? () {}
                                : () => widget.onCommand('LIVE'),
                            accent: true,
                          )),
                      const SizedBox(width: 10),
                      EditableLandscapeControl(
                          id: 'stop',
                          offset: _offset('stop'),
                          editing: _editing,
                          onMove: _move,
                          child: LandscapeControl(
                              label: 'STOP',
                              caption: 'live',
                              onTap: _editing
                                  ? () {}
                                  : () => widget.onCommand('STOP'),
                              danger: true)),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 16,
                bottom: 10,
                child: OverlayBadge(
                    label: 'FPS',
                    value: _fps == 0 ? '--' : _fps.toStringAsFixed(1)),
              ),
              if (_showSettings)
                Positioned.fill(
                  child: LandscapeSettingsOverlay(
                    editing: _editing,
                    dialOffset: _offset('dial'),
                    onDialMove: (delta) => _move('dial', delta),
                    okOffset: _offset('ok'),
                    onOkMove: (delta) => _move('ok', delta),
                    manualMode: widget.manualMode,
                    exposureMode: widget.exposureMode,
                    aperture: widget.aperture,
                    shutter: widget.shutter,
                    iso: widget.iso,
                    actualIso: widget.actualIso,
                    autoIso: widget.autoIso,
                    pendingSettings: widget.pendingSettings,
                    onManualMode: widget.onManualMode,
                    onSettingStep: widget.onManualSetting,
                    onConfirmSetting: widget.onConfirmSetting,
                    menuValuePending: widget.menuValuePending,
                    onConfirmMenuValue: widget.onConfirmMenuValue,
                  ),
                ),
              if (_showMenu)
                Positioned.fill(
                  child: CameraMenuTree(
                    expanded: _menuExpanded,
                    autoIso: widget.autoIso,
                    onClose: _closeMenu,
                    onValueChanged: widget.onMenuValueChanged,
                  ),
                ),
              Positioned(
                left: _imageControlPanelLeft,
                top: 0,
                bottom: 0,
                width: 218,
                child: ImageControlSidePanel(
                  open: _showImageControlPanel,
                  onDragUpdate: _dragImageControlPanel,
                  onDragEnd: _finishImageControlPanelDrag,
                ),
              ),
              if (_editing && !_showSettings)
                const Positioned.fill(child: LandscapeEditOverlay()),
            ],
          ),
        ),
      );
}

class ImageControlPreviewLayer extends StatelessWidget {
  const ImageControlPreviewLayer({required this.child, super.key});

  final Widget child;

  static const List<double> _neutralMatrix = [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];

  @override
  Widget build(BuildContext context) => ColorFiltered(
        colorFilter: const ColorFilter.matrix(_neutralMatrix),
        child: child,
      );
}

class ImageControlSidePanel extends StatelessWidget {
  const ImageControlSidePanel({
    required this.open,
    required this.onDragUpdate,
    required this.onDragEnd,
    super.key,
  });

  final bool open;
  final ValueChanged<DragUpdateDetails> onDragUpdate;
  final ValueChanged<DragEndDetails> onDragEnd;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 18,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xf20b0b0b),
                  border: Border(
                    right: BorderSide(color: Color(0xff555555), width: 1),
                  ),
                ),
                child: const Stack(
                  children: [
                    Positioned(
                      top: 24,
                      left: 18,
                      child: Text(
                        'IMAGE CONTROL',
                        style: TextStyle(
                          color: Color(0xffeeeeee),
                          fontSize: 11,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 66,
                      left: 18,
                      right: 18,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ImageControlPlaceholder(label: 'EXPOSURE'),
                          _ImageControlPlaceholder(label: 'CONTRAST'),
                          _ImageControlPlaceholder(label: 'CURVE'),
                          _ImageControlPlaceholder(label: 'COLOR'),
                          _ImageControlPlaceholder(label: 'SATURATION'),
                          _ImageControlPlaceholder(label: 'TEXTURE'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: 18,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: onDragUpdate,
                onHorizontalDragEnd: onDragEnd,
                child: Center(
                  child: CustomPaint(
                    size: const Size(18, 54),
                    painter: _ImageControlHandlePainter(open: open),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _ImageControlPlaceholder extends StatelessWidget {
  const _ImageControlPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: Row(
          children: [
            const Text(
              '>',
              style: TextStyle(
                color: Color(0xffdddddd),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xffbbbbbb),
                fontSize: 10,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      );
}

class _ImageControlHandlePainter extends CustomPainter {
  const _ImageControlHandlePainter({required this.open});

  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xffdddddd);
    final outline = Paint()
      ..color = const Color(0xff777777)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..moveTo(2, 0)
      ..lineTo(size.width - 2, 7)
      ..lineTo(size.width - 2, size.height - 7)
      ..lineTo(2, size.height)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, outline);

    final arrow = Path();
    if (open) {
      arrow
        ..moveTo(11, 19)
        ..lineTo(6, 27)
        ..lineTo(11, 35);
    } else {
      arrow
        ..moveTo(7, 19)
        ..lineTo(12, 27)
        ..lineTo(7, 35);
    }
    canvas.drawPath(
      arrow,
      Paint()
        ..color = const Color(0xff222222)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.square
        ..strokeJoin = StrokeJoin.miter,
    );
  }

  @override
  bool shouldRepaint(covariant _ImageControlHandlePainter oldDelegate) =>
      oldDelegate.open != open;
}

class LandscapeEditOverlay extends StatelessWidget {
  const LandscapeEditOverlay({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        border: Border.all(color: const Color(0x88777777))))),
            const Positioned(
                top: 50,
                left: 16,
                child: Text('EDIT MODE  ·  BUTTON LAYOUT',
                    style: TextStyle(
                        color: Color(0xffdddddd),
                        fontSize: 9,
                        letterSpacing: 1.5))),
            const Positioned(
                bottom: 54,
                left: 0,
                right: 0,
                child: Center(
                    child: Text('버튼 위치 조정 모드  ·  DONE으로 종료',
                        style: TextStyle(
                            color: Color(0xff999999),
                            fontSize: 9,
                            letterSpacing: 1.2)))),
          ],
        ),
      );
}

String _exposureLabel(
  List<ExposureOption> options,
  int value,
  String fallbackPrefix,
) {
  for (final option in options) {
    if (option.value == value) return option.label;
  }

  return '$fallbackPrefix$value';
}

String _releaseModeLabel(int mode) => switch (mode) {
      1 => 'S',
      2 => 'CH',
      _ => '--',
    };

class CameraMenuTree extends StatefulWidget {
  const CameraMenuTree({
    required this.expanded,
    required this.autoIso,
    required this.onClose,
    required this.onValueChanged,
    super.key,
  });

  final bool expanded;
  final bool autoIso;
  final VoidCallback onClose;
  final void Function(String setting, String value) onValueChanged;

  @override
  State<CameraMenuTree> createState() => _CameraMenuTreeState();
}

class _CameraMenuTreeState extends State<CameraMenuTree> {
  // ignore: unused_field
  static const Map<String, Map<String, List<String>>> _tree = {
    'CAMERA': {
      '촬영 모드': ['P', 'A', 'S', 'M'],
      '측광 방식': ['멀티 패턴', '중앙 중점', '스팟'],
      '화이트밸런스': ['자동', '맑은 날', '흐림'],
    },
    'LIVEVIEW': {
      '라이브뷰 표시': ['클린', '격자', '히스토그램'],
      '초점 표시': ['십자선', '초점 박스', '끄기'],
      '프레임레이트': ['15 fps', '24 fps', '30 fps'],
    },
    'FOCUS': {
      '초점 모드': ['AF-S', 'AF-C', '수동'],
      'AF 영역': ['단일 포인트', '와이드 영역', '얼굴 우선'],
      '초점 우선': ['릴리즈', '초점'],
    },
    'PICTURE': {
      '사진 리뷰': ['유지', '2초', '5초'],
      '사진 선택': ['최근 사진', '표시 사진', '전체'],
      '히스토그램': ['RGB', '밝기', '끄기'],
    },
  };

  static const Map<String, Map<String, List<String>>> _officialTree = {
    'D': {
      '재생 폴더': ['모든 폴더', '현재 폴더'],
      '화상 삭제': ['선택 화상', '날짜 선택', '모든 화상'],
      '재생 화상 확인': ['ON', 'OFF'],
      '삭제 후': ['다음 화상', '이전 화상', '삭제 전 상태'],
      '화상 자동 회전': ['ON', 'OFF'],
    },
    'C': {
      '파일 형식': ['NEF (RAW)', 'JPEG', 'NEF+JPEG'],
      '화상 사이즈': ['L', 'M', 'S'],
      '화질': ['JPEG Fine', 'JPEG Normal', 'JPEG Basic'],
      '화이트밸런스': ['자동', '백열등', '맑은 날', '흐림', '플래시', '수동 프리셋'],
      'Picture Control 설정': ['표준', '자연스럽게', '선명하게', '모노크롬'],
      '색공간': ['sRGB', 'Adobe RGB'],
      '액티브 D-Lighting': ['OFF', '약하게', '표준', '강하게'],
    },
    'A': {
      'AF-C 우선 조건 선택': ['릴리즈', '초점'],
      'AF-S 우선 조건 선택': ['초점', '릴리즈'],
      '초점 포인트 수': ['51포인트', '11포인트'],
      'AF 영역 모드': ['싱글 포인트', '다이내믹 영역', '3D-tracking', '그룹 영역', '자동 영역'],
      'ISO 감도 설정': ['100', '200', '400', '800', '1600', '자동'],
      '버튼 사용자 설정': ['Fn 버튼', 'Pv 버튼', 'AE-L/AF-L 버튼'],
      '커맨드 다이얼 설정': ['기본', '반전', '노출 보정 다이얼'],
    },
    'B': {
      '모니터 밝기': ['-5', '-2', '0', '+2', '+5'],
      '언어': ['한국어', 'English'],
      '시간대 및 날짜': ['자동 설정', '수동 설정'],
      '저장 및 불러오기': ['설정 저장', '설정 불러오기'],
      '이미지 코멘트': ['ON', 'OFF'],
      '저작권 정보': ['ON', 'OFF'],
      '배터리 정보': ['퍼센트', '아이콘', '숨김'],
    },
  };

  static const Map<String, Map<String, List<String>>> _quickTree = {
    'D': {
      '재생 화상 확인': ['ON', 'OFF'],
      '사진 리뷰': ['유지', '2초', '5초'],
      '히스토그램': ['RGB', '밝기', '끄기'],
    },
    'C': {
      'ISO 감도 제어': ['자동', '수동'],
      'ISO 감도': ['100', '200', '400', '800', '1600', '3200'],
      '화이트밸런스': ['자동', '맑은 날', '흐림', '백열등', '플래시', '수동 프리셋'],
      '측광 방식': ['멀티 패턴', '중앙 중점', '스팟'],
      '노출 보정': ['-3', '-2', '-1', '0', '+1', '+2', '+3'],
      'Picture Control': ['표준', '자연스럽게', '선명하게', '모노크롬'],
    },
    'A': {
      '초점 모드': ['AF-S', 'AF-C', '수동'],
      'AF 영역': ['싱글 포인트', '다이내믹 영역', '3D-tracking', '자동 영역'],
      '초점 우선': ['릴리즈', '초점'],
    },
    'B': {
      '모니터 밝기': ['-5', '-2', '0', '+2', '+5'],
      '배터리 정보': ['퍼센트', '아이콘', '숨김'],
      '레이아웃': ['기본', '컨트롤 편집', '초기화'],
    },
  };

  String? _category;
  String? _setting;
  final Map<String, String> _selected = {
    '촬영 모드': 'P',
    '측광 방식': '멀티 패턴',
    '화이트밸런스': '자동',
    '초점 모드': 'AF-S',
  };

  @override
  void initState() {
    super.initState();
    _selected['ISO 감도 제어'] = widget.autoIso ? '자동' : '수동';
  }

  @override
  void didUpdateWidget(covariant CameraMenuTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoIso != widget.autoIso) {
      _selected['ISO 감도 제어'] = widget.autoIso ? '자동' : '수동';
    }
    if (!oldWidget.expanded && widget.expanded) {
      setState(() => _category = 'C');
    } else if (oldWidget.expanded && !widget.expanded) {
      setState(() {
        _category = null;
        _setting = null;
      });
    }
  }

  void _goBack() {
    if (_setting != null) {
      setState(() => _setting = null);
    } else if (_category != null) {
      setState(() => _category = null);
    }
  }

  void _selectValue(String setting, String value) {
    setState(() => _selected[setting] = value);
    widget.onValueChanged(setting, value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.expanded && _category == null) _category = 'C';
    final categories = <String, String>{
      'D': 'D',
      'C': 'C',
      'A': 'A',
      'B': 'B',
    };
    final categoryIcons = <String, IconData>{
      'D': Icons.play_arrow_outlined,
      'C': Icons.camera_alt_outlined,
      'A': Icons.edit_outlined,
      'B': Icons.build_outlined,
    };
    const activeTree = _officialTree;
    final settings = _category == null
        ? const <MapEntry<String, List<String>>>[]
        : activeTree[_category!]!.entries.toList();
    final categoryEntries = categories.entries.toList(growable: false);
    final categoryButtons = SizedBox(
      width: 24,
      height: 135,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          final index = (event.localPosition.dy / 27).floor();
          debugPrint(
              '[MENU_TOUCH] rail down local=${event.localPosition} index=$index');
          if (index < 0 || index >= categoryEntries.length) return;
          final entry = categoryEntries[index];
          debugPrint(
              '[MENU_TOUCH] select key=${entry.key} value=${entry.value}');
          setState(() {
            _category = entry.value;
            _setting = null;
          });
        },
        onPointerUp: (event) =>
            debugPrint('[MENU_TOUCH] rail up local=${event.localPosition}'),
        onPointerCancel: (event) =>
            debugPrint('[MENU_TOUCH] rail cancel local=${event.localPosition}'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: categoryEntries
              .map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: IgnorePointer(
                      child: _MenuSquareButton(
                        key: ValueKey('menu-category-${entry.key}'),
                        label: entry.key,
                        icon: categoryIcons[entry.key],
                        selected: _category == entry.value,
                        onTap: () {},
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
    final settingColumn = _category == null
        ? const SizedBox.shrink()
        : SizedBox(
            width: 122,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: settings
                  .map((item) => _MenuSettingGroup(
                        label: item.key,
                        selected: _setting == item.key,
                        values: item.value,
                        selectedValue: _selected[item.key] ?? item.value.first,
                        valueIcons: null,
                        onToggle: () => setState(() {
                          _setting = _setting == item.key ? null : item.key;
                        }),
                        onSelect: (value) => _selectValue(item.key, value),
                      ))
                  .toList(),
            ),
          );
    final quickSettings = _category == null
        ? const <MapEntry<String, List<String>>>[]
        : _quickTree[_category!]!.entries.toList();
    final quickSettingColumn = _category == null
        ? const SizedBox.shrink()
        : SizedBox(
            width: 122,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: quickSettings
                  .map((item) => _MenuSettingGroup(
                        label: item.key,
                        selected: _setting == item.key,
                        values: item.value,
                        selectedValue: _selected[item.key] ?? item.value.first,
                        valueIcons: null,
                        onToggle: () => setState(() {
                          _setting = _setting == item.key ? null : item.key;
                        }),
                        onSelect: (value) => _selectValue(item.key, value),
                      ))
                  .toList(),
            ),
          );
    final quickSettingsPane = quickSettingColumn;
    final settingsPane = settingColumn;
    Widget fixedMenuContent(Widget pane) => SizedBox(
          width: 158,
          height: 135,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(left: 0, top: 0, child: categoryButtons),
              if (_category != null) ...[
                const Positioned(left: 30, top: 0, child: _MenuDivider()),
                Positioned(left: 36, top: 0, width: 122, child: pane),
              ],
            ],
          ),
        );
    final quickContent = fixedMenuContent(quickSettingsPane);
    final content = fixedMenuContent(settingsPane);
    final menuContent = widget.expanded ? content : quickContent;

    return Stack(
      children: [
        Positioned(
          top: 124,
          left: 18,
          width: 196,
          height: 155,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (event) => debugPrint(
                '[MENU_TOUCH] panel down local=${event.localPosition}'),
            child: Material(
              color: const Color(0x22101010),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        debugPrint('[MENU_TOUCH] panel background tap');
                        _goBack();
                      },
                      child: const ColoredBox(color: Colors.transparent),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 8,
                        right: 30,
                        top: widget.expanded ? 14 : 8,
                        bottom: 8,
                      ),
                      child: menuContent,
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: IconButton(
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close, size: 14),
                      color: Colors.white70,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 18, height: 18),
                      visualDensity: VisualDensity.compact,
                      splashRadius: 9,
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

class _MenuSquareButton extends StatelessWidget {
  const _MenuSquareButton({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        button: true,
        selected: selected,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 24,
            height: 24,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected ? Colors.white : const Color(0x33101010),
                border: Border.all(
                    color: selected ? Colors.white : const Color(0x66777777)),
              ),
              child: Center(
                child: icon == null
                    ? ExcludeSemantics(
                        child: Text(label,
                            style: TextStyle(
                                color: selected ? Colors.black : Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                      )
                    : Icon(icon,
                        size: 15,
                        color: selected ? Colors.black : Colors.white),
              ),
            ),
          ),
        ),
      );
}

class _MenuListRow extends StatelessWidget {
  const _MenuListRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected ? Colors.white : const Color(0xffc4c4c4),
                  fontSize: 9,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        ),
      );
}

class _MenuSettingGroup extends StatelessWidget {
  const _MenuSettingGroup({
    required this.label,
    required this.selected,
    required this.values,
    required this.selectedValue,
    this.valueIcons,
    required this.onToggle,
    required this.onSelect,
  });

  final String label;
  final bool selected;
  final List<String> values;
  final String? selectedValue;
  final Map<String, IconData>? valueIcons;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MenuListRow(label: label, selected: selected, onTap: onToggle),
          if (selected)
            ...values.map((value) => _MenuValueRow(
                  label: value,
                  selected: selectedValue == value,
                  icon: valueIcons?[value],
                  onTap: () => onSelect(value),
                )),
        ],
      );
}

class _MenuDivider extends StatelessWidget {
  const _MenuDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 1,
        height: 122,
        child: ColoredBox(color: Color(0x55777777)),
      );
}

class _MenuValueRow extends StatelessWidget {
  const _MenuValueRow({
    required this.label,
    required this.selected,
    this.icon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 17, top: 4, bottom: 4),
          child: Row(
            children: [
              Icon(
                  icon ??
                      (selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked),
                  size: 12,
                  color: selected ? Colors.white : Colors.white38),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: selected ? Colors.white : const Color(0xffb0b0b0),
                      fontSize: 8,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400)),
            ],
          ),
        ),
      );
}

class CameraMenuShell extends StatefulWidget {
  const CameraMenuShell({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  State<CameraMenuShell> createState() => _CameraMenuShellState();
}

class _CameraMenuShellState extends State<CameraMenuShell> {
  static const Map<String, List<String>> _menuTree = {
    'SHOOTING': ['Drive mode', 'Metering', 'White balance'],
    'LIVE VIEW': ['Display layout', 'Focus display', 'Frame rate'],
    'FOCUS': ['Focus mode', 'AF area', 'Focus priority'],
    'PLAYBACK': ['Review behavior', 'Image selection', 'Histogram'],
    'SYSTEM': ['Network', 'Battery', 'Layout'],
  };

  final Set<String> _expanded = {'SHOOTING'};

  void _toggle(String key) {
    setState(() {
      if (!_expanded.add(key)) _expanded.remove(key);
    });
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: Color(0x66000000)),
          ),
          Positioned(
            top: 54,
            left: 16,
            width: 270,
            child: Material(
              color: const Color(0xee101010),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'CAMERA MENU',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        IconButton(
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close, size: 18),
                          color: Colors.white70,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'CUSTOM CAMERA MENU',
                      style: TextStyle(
                        color: Color(0xff888888),
                        fontSize: 9,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: ListView(
                        shrinkWrap: true,
                        children: _menuTree.entries.expand((entry) {
                          final open = _expanded.contains(entry.key);
                          return [
                            InkWell(
                              onTap: () => _toggle(entry.key),
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  children: [
                                    Icon(
                                      open
                                          ? Icons.expand_more
                                          : Icons.chevron_right,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                    Text(
                                      entry.key,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (open)
                              ...entry.value.map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(
                                      left: 24, bottom: 7),
                                  child: Text(
                                    '└ $item',
                                    style: const TextStyle(
                                      color: Color(0xffaaaaaa),
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                          ];
                        }).toList(),
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

class LandscapeSettingsOverlay extends StatefulWidget {
  const LandscapeSettingsOverlay({
    required this.editing,
    required this.dialOffset,
    required this.onDialMove,
    required this.okOffset,
    required this.onOkMove,
    required this.manualMode,
    required this.exposureMode,
    required this.aperture,
    required this.shutter,
    required this.iso,
    required this.actualIso,
    required this.autoIso,
    required this.pendingSettings,
    required this.onManualMode,
    required this.onSettingStep,
    required this.onConfirmSetting,
    required this.menuValuePending,
    required this.onConfirmMenuValue,
    super.key,
  });

  final bool editing;
  final Offset dialOffset;
  final ValueChanged<Offset> onDialMove;
  final Offset okOffset;
  final ValueChanged<Offset> onOkMove;
  final bool manualMode;
  final int exposureMode;
  final int aperture;
  final int shutter;
  final int iso;
  final int? actualIso;
  final bool autoIso;
  final Set<String> pendingSettings;
  final VoidCallback onManualMode;
  final void Function(String key, int stepDelta) onSettingStep;
  final ValueChanged<String> onConfirmSetting;
  final bool menuValuePending;
  final VoidCallback onConfirmMenuValue;

  @override
  State<LandscapeSettingsOverlay> createState() =>
      _LandscapeSettingsOverlayState();
}

class _LandscapeSettingsOverlayState extends State<LandscapeSettingsOverlay> {
  String? _selectedSetting;

  void _toggleSetting(String key) =>
      setState(() => _selectedSetting = _selectedSetting == key ? null : key);

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(
              child:
                  IgnorePointer(child: ColoredBox(color: Colors.transparent))),
          Positioned(
            left: 18,
            top: 66,
            width: 190,
            child: LandscapeSettingGroup(
              label: widget.manualMode ? 'PRIORITY' : 'PRIORITY  ·  TAP M',
              child: Row(
                children: ['A', 'P', 'S', 'M']
                    .map((mode) => Expanded(
                        child: _ModeButton(
                            label: mode,
                            selected: widget.exposureMode ==
                                const {'M': 1, 'P': 2, 'A': 3, 'S': 4}[mode],
                            pending: mode == 'M' &&
                                widget.pendingSettings.contains('mode'),
                            enabled: mode == 'M' && !widget.manualMode,
                            onTap: widget.onManualMode)))
                    .toList(),
              ),
            ),
          ),
          Positioned(
            right: 18,
            top: 66,
            width: 210,
            child: Column(
              children: [
                _ValueButton(
                    label: 'APERTURE',
                    value:
                        _exposureLabel(apertureOptions, widget.aperture, 'F'),
                    selected: _selectedSetting == 'aperture',
                    pending: widget.pendingSettings.contains('aperture'),
                    onTap: () => _toggleSetting('aperture')),
                _ValueButton(
                    label: 'SHUTTER',
                    value: _exposureLabel(shutterOptions, widget.shutter, ''),
                    selected: _selectedSetting == 'shutter',
                    pending: widget.pendingSettings.contains('shutter'),
                    onTap: () => _toggleSetting('shutter')),
                _ValueButton(
                    label: 'ISO',
                    value: widget.autoIso
                        ? (widget.actualIso == null
                            ? 'AUTO'
                            : _exposureLabel(
                                isoOptions, widget.actualIso!, 'ISO '))
                        : _exposureLabel(isoOptions, widget.iso, 'ISO '),
                    selected: _selectedSetting == 'iso',
                    pending: widget.pendingSettings.contains('iso'),
                    onTap: () => _toggleSetting('iso')),
              ],
            ),
          ),
          Center(
              child: Transform.translate(
            offset: widget.dialOffset,
            child: SettingsDial(
              editing: widget.editing,
              onMove: widget.onDialMove,
              active: _selectedSetting != null && widget.manualMode,
              onStep: (stepDelta) {
                final key = _selectedSetting;
                if (key != null) widget.onSettingStep(key, stepDelta);
              },
            ),
          )),
          Center(
            child: Transform.translate(
              offset: widget.dialOffset + widget.okOffset + const Offset(98, 0),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: widget.editing
                    ? (details) => widget.onOkMove(details.delta)
                    : null,
                child: SizedBox(
                  width: 52,
                  height: 22,
                  child: OutlinedButton(
                    onPressed: widget.editing
                        ? null
                        : _selectedSetting != null
                            ? (widget.pendingSettings.contains(_selectedSetting)
                                ? () =>
                                    widget.onConfirmSetting(_selectedSetting!)
                                : null)
                            : (widget.menuValuePending
                                ? widget.onConfirmMenuValue
                                : null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xff8de8b5),
                      disabledForegroundColor: const Color(0x55777777),
                      side: const BorderSide(color: Color(0x998de8b5)),
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700),
                    ),
                    child: const Text('OK'),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
              bottom: 112,
              left: 0,
              right: 0,
              child: Center(
                  child: Text('FOCUS AREA  ·  AF-S',
                      style: TextStyle(
                          color: Color(0xffaaaaaa),
                          fontSize: 9,
                          letterSpacing: 1.4)))),
        ],
      );
}

class SettingsDial extends StatefulWidget {
  const SettingsDial({
    required this.editing,
    required this.onMove,
    required this.active,
    required this.onStep,
    super.key,
  });

  final bool editing;
  final ValueChanged<Offset> onMove;
  final bool active;
  final ValueChanged<int> onStep;

  @override
  State<SettingsDial> createState() => _SettingsDialState();
}

class _SettingsDialState extends State<SettingsDial>
    with SingleTickerProviderStateMixin {
  static const double _size = 164;
  // Twelve detents make each tooth feel deliberate instead of overly fine.
  static const double _detent = math.pi / 6;
  late final AnimationController _inertia;
  double _angle = 0;
  double _lastTouchAngle = 0;
  double _detentRemainder = 0;
  Offset _lastPosition = const Offset(_size / 2, _size / 2);

  @override
  void initState() {
    super.initState();
    _inertia = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        final nextAngle = _inertia.value;
        final delta = nextAngle - _angle;
        _angle = nextAngle;
        _consumeDetents(delta);
        if (mounted) setState(() {});
      });
  }

  @override
  void didUpdateWidget(covariant SettingsDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _detentRemainder = 0;
  }

  @override
  void dispose() {
    _inertia.dispose();
    super.dispose();
  }

  double _touchAngle(Offset position) =>
      math.atan2(position.dy - _size / 2, position.dx - _size / 2);

  double _normalizedDelta(double delta) {
    while (delta > math.pi) {
      delta -= math.pi * 2;
    }
    while (delta < -math.pi) {
      delta += math.pi * 2;
    }
    return delta;
  }

  void _consumeDetents(double delta) {
    _detentRemainder += delta;
    final steps = (_detentRemainder / _detent).truncate();
    if (steps == 0) return;
    _detentRemainder -= steps * _detent;
    if (widget.active) {
      widget.onStep(steps);
    }
    // Free-spin still feels like a physical toothed wheel. Limit bursts from
    // fast drags so the haptic motor is not driven harder than necessary.
    for (var index = 0; index < math.min(steps.abs(), 3); index++) {
      HapticFeedback.selectionClick();
    }
  }

  void _rotate(double delta) {
    final distanceToTooth = math.min(
      _detentRemainder.abs(),
      (_detent - _detentRemainder.abs()).abs(),
    );
    const resistanceZone = _detent * .22;
    final resistance = distanceToTooth < resistanceZone
        ? .30 + .70 * (distanceToTooth / resistanceZone)
        : 1.0;
    final resistedDelta = delta * resistance;
    _angle += resistedDelta;
    _inertia.value = _angle;
    _consumeDetents(resistedDelta);
    setState(() {});
  }

  void _start(DragStartDetails details) {
    _inertia.stop();
    if (widget.editing) return;
    _lastPosition = details.localPosition;
    _lastTouchAngle = _touchAngle(details.localPosition);
  }

  void _update(DragUpdateDetails details) {
    if (widget.editing) {
      widget.onMove(details.delta);
      return;
    }
    _lastPosition = details.localPosition;
    final nextTouchAngle = _touchAngle(details.localPosition);
    final delta = _normalizedDelta(nextTouchAngle - _lastTouchAngle);
    _lastTouchAngle = nextTouchAngle;
    _rotate(delta);
  }

  void _end(DragEndDetails details) {
    if (widget.editing) return;
    final radius = _lastPosition - const Offset(_size / 2, _size / 2);
    final radiusSquared = math.max(900.0, radius.distanceSquared);
    final velocity = details.velocity.pixelsPerSecond;
    final angularVelocity =
        ((radius.dx * velocity.dy - radius.dy * velocity.dx) / radiusSquared)
            .clamp(-12.0, 12.0);
    if (angularVelocity.abs() < .35) return;
    _inertia.value = _angle;
    _inertia.animateWith(FrictionSimulation(.18, _angle, angularVelocity));
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _start,
          onPanUpdate: _update,
          onPanEnd: _end,
          child: SizedBox.square(
            dimension: _size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                    painter: SettingsDialPainter(
                        angle: _angle, active: widget.active)),
                Center(
                    child: IgnorePointer(
                  ignoring: widget.editing,
                  child: const FourWayDialPad(),
                )),
              ],
            ),
          ),
        ),
      );
}

enum FourWayDirection { none, up, right, down, left }

class FourWayDialPad extends StatefulWidget {
  const FourWayDialPad({super.key});

  @override
  State<FourWayDialPad> createState() => _FourWayDialPadState();
}

class _FourWayDialPadState extends State<FourWayDialPad> {
  static const double _size = 113;
  static const double _innerRadius = 18;
  static const double _outerRadius = 53;
  static const double _halfAngle = math.pi / 6;
  static const Duration _minimumPress = Duration(milliseconds: 120);
  FourWayDirection _direction = FourWayDirection.none;
  bool _pressed = false;
  Timer? _releaseTimer;
  DateTime? _pressedAt;

  FourWayDirection _directionFor(Offset position) {
    final radius = position.distance;
    if (radius < _innerRadius || radius > _outerRadius) {
      return FourWayDirection.none;
    }
    final angle = math.atan2(position.dy, position.dx);
    final sector = ((angle / (math.pi / 2)).round() % 4 + 4) % 4;
    final centerAngle = sector * math.pi / 2;
    var difference = (angle - centerAngle).abs();
    if (difference > math.pi) difference = math.pi * 2 - difference;
    if (difference > _halfAngle) return FourWayDirection.none;
    return const [
      FourWayDirection.right,
      FourWayDirection.down,
      FourWayDirection.left,
      FourWayDirection.up,
    ][sector];
  }

  void _update(Offset localPosition) {
    const center = Offset(_size / 2, _size / 2);
    final next = _directionFor(localPosition - center);
    if (next == FourWayDirection.none) {
      _releaseTimer?.cancel();
      _pressedAt = null;
      if (_direction != FourWayDirection.none || _pressed) {
        setState(() {
          _direction = FourWayDirection.none;
          _pressed = false;
        });
      }
      return;
    }
    if (_direction != next) HapticFeedback.selectionClick();
    _releaseTimer?.cancel();
    _pressedAt ??= DateTime.now();
    setState(() {
      _direction = next;
      _pressed = true;
    });
  }

  void _release() {
    final elapsed = _pressedAt == null
        ? _minimumPress
        : DateTime.now().difference(_pressedAt!);
    final remaining = _minimumPress - elapsed;
    if (remaining > Duration.zero) {
      _releaseTimer = Timer(remaining, _reset);
    } else {
      _reset();
    }
  }

  void _reset() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _pressedAt = null;
    setState(() {
      _direction = FourWayDirection.none;
      _pressed = false;
    });
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) => _update(details.localPosition),
        onTapUp: (_) => _release(),
        onTapCancel: _reset,
        child: SizedBox.square(
          dimension: _size,
          child: CustomPaint(
              painter:
                  FourWayDialPainter(direction: _direction, pressed: _pressed)),
        ),
      );
}

class FourWayDialPainter extends CustomPainter {
  const FourWayDialPainter({required this.direction, required this.pressed});

  final FourWayDirection direction;
  final bool pressed;

  double _angleFor(FourWayDirection value) => switch (value) {
        FourWayDirection.up => -math.pi / 2,
        FourWayDirection.right => 0,
        FourWayDirection.down => math.pi / 2,
        FourWayDirection.left => math.pi,
        FourWayDirection.none => 0,
      };

  Path _buttonPath(Offset center, double inner, double outer, double angle,
      double halfAngle) {
    final path = Path()
      ..moveTo(center.dx + math.cos(angle - halfAngle) * inner,
          center.dy + math.sin(angle - halfAngle) * inner)
      ..lineTo(center.dx + math.cos(angle - halfAngle) * outer,
          center.dy + math.sin(angle - halfAngle) * outer)
      ..arcToPoint(
        Offset(center.dx + math.cos(angle + halfAngle) * outer,
            center.dy + math.sin(angle + halfAngle) * outer),
        radius: Radius.circular(outer),
        clockwise: true,
      )
      ..lineTo(center.dx + math.cos(angle + halfAngle) * inner,
          center.dy + math.sin(angle + halfAngle) * inner)
      ..arcToPoint(
        Offset(center.dx + math.cos(angle - halfAngle) * inner,
            center.dy + math.sin(angle - halfAngle) * inner),
        radius: Radius.circular(inner),
        clockwise: false,
      )
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const inner = _FourWayDialPadState._innerRadius;
    const outer = _FourWayDialPadState._outerRadius;
    const halfAngle = _FourWayDialPadState._halfAngle;
    for (final value in FourWayDirection.values.skip(1)) {
      final isActive = value == direction;
      final path = _buttonPath(center, inner, isActive ? outer + 5 : outer,
          _angleFor(value), halfAngle);
      canvas.drawPath(
          path,
          Paint()
            ..color =
                isActive ? const Color(0x668de8b5) : const Color(0x33222222));
      canvas.drawPath(
          path,
          Paint()
            ..color =
                isActive ? const Color(0xff8de8b5) : const Color(0x88777777)
            ..style = PaintingStyle.stroke
            ..strokeWidth = isActive && pressed ? 2.4 : 1.2);
    }
    canvas.drawCircle(center, 16, Paint()..color = const Color(0x66222222));
    canvas.drawCircle(
        center, pressed ? 9.5 : 8, Paint()..color = const Color(0xffbdbdbd));
  }

  @override
  bool shouldRepaint(covariant FourWayDialPainter oldDelegate) =>
      oldDelegate.direction != direction || oldDelegate.pressed != pressed;
}

class SettingsDialPainter extends CustomPainter {
  const SettingsDialPainter({required this.angle, required this.active});

  final double angle;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 7;
    final accent = active ? const Color(0xff8de8b5) : const Color(0xffaaaaaa);
    canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = const Color(0x44777777)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    for (var index = 0; index < 12; index++) {
      final tickAngle = angle + index * math.pi * 2 / 12;
      final outer =
          center + Offset(math.cos(tickAngle), math.sin(tickAngle)) * radius;
      final innerRadius = radius - (index % 3 == 0 ? 9 : 5);
      final inner = center +
          Offset(math.cos(tickAngle), math.sin(tickAngle)) * innerRadius;
      canvas.drawLine(
          inner,
          outer,
          Paint()
            ..color = index % 3 == 0 ? accent : const Color(0x66777777)
            ..strokeWidth = index % 3 == 0 ? 1.8 : 1);
    }
    final marker =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius - 16);
    canvas.drawCircle(marker, 4.2, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant SettingsDialPainter oldDelegate) =>
      oldDelegate.angle != angle || oldDelegate.active != active;
}

class LandscapeSettingGroup extends StatelessWidget {
  const LandscapeSettingGroup(
      {required this.label, required this.child, super.key});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xff777777), fontSize: 9, letterSpacing: 1.5)),
        const SizedBox(height: 10),
        child
      ]);
}

class _ModeButton extends StatelessWidget {
  const _ModeButton(
      {required this.label,
      required this.selected,
      required this.pending,
      required this.enabled,
      required this.onTap});
  final String label;
  final bool selected;
  final bool pending;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color:
                          selected ? Colors.white : const Color(0x44777777)))),
          child: Text(label,
              style: TextStyle(
                  color: pending
                      ? const Color(0xffffcc66)
                      : selected
                          ? Colors.white
                          : const Color(0xff555555),
                  fontWeight: FontWeight.w700))));
}

class _ValueButton extends StatefulWidget {
  const _ValueButton(
      {required this.label,
      required this.value,
      required this.selected,
      required this.pending,
      required this.onTap});
  final String label;
  final String value;
  final bool selected;
  final bool pending;
  final VoidCallback onTap;

  @override
  State<_ValueButton> createState() => _ValueButtonState();
}

class _ValueButtonState extends State<_ValueButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 760),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: widget.onTap,
      child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child:
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(widget.label,
                style: TextStyle(
                    color: widget.selected
                        ? Colors.white
                        : const Color(0xff777777),
                    fontSize: 9,
                    letterSpacing: 1.3)),
            AnimatedBuilder(
                animation: _blink,
                builder: (context, child) => Opacity(
                    opacity: widget.pending && widget.selected
                        ? .58 + (_blink.value * .42)
                        : 1,
                    child: Text(widget.value,
                        style: TextStyle(
                            color: widget.pending
                                ? const Color(0xff8de8b5)
                                : widget.selected
                                    ? const Color(0xff8de8b5)
                                    : Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0)))),
          ])));
}

class LandscapePill extends StatelessWidget {
  const LandscapePill({required this.label, required this.onTap, super.key});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: .58),
        shape: const StadiumBorder(side: BorderSide(color: Color(0x55777777))),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2)),
          ),
        ),
      );
}

class EditableLandscapeControl extends StatelessWidget {
  const EditableLandscapeControl(
      {required this.id,
      required this.offset,
      required this.editing,
      required this.onMove,
      required this.child,
      super.key});
  final String id;
  final Offset offset;
  final bool editing;
  final void Function(String id, Offset delta) onMove;
  final Widget child;

  @override
  Widget build(BuildContext context) => Transform.translate(
        offset: offset,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: editing ? (details) => onMove(id, details.delta) : null,
          child: child,
        ),
      );
}

class AfSlideControl extends StatefulWidget {
  const AfSlideControl(
      {required this.editing,
      required this.onFocus,
      required this.onMove,
      super.key});
  final bool editing;
  final VoidCallback onFocus;
  final ValueChanged<Offset> onMove;

  @override
  State<AfSlideControl> createState() => _AfSlideControlState();
}

enum _AfSlidePhase { idle, focusing }

class _AfSlideControlState extends State<AfSlideControl> {
  static const double _travel = 96;
  static const double _focusDetent = 18;

  double _slide = 0;
  double _dragOriginX = 0;
  double _dragOriginSlide = 0;
  _AfSlidePhase _phase = _AfSlidePhase.idle;

  void _beginSlide(DragStartDetails details) {
    _dragOriginX = details.localPosition.dx;
    _dragOriginSlide = _slide;
  }

  void _updateSlide(DragUpdateDetails details) {
    final next = (_dragOriginSlide + details.localPosition.dx - _dragOriginX)
        .clamp(0, _travel)
        .toDouble();

    if (_phase == _AfSlidePhase.idle && next >= _focusDetent) {
      _phase = _AfSlidePhase.focusing;
      HapticFeedback.selectionClick();
      widget.onFocus();
    }
    setState(() => _slide = next);
  }

  void _finishSlide() {
    setState(() {
      _slide = 0;
      _phase = _AfSlidePhase.idle;
    });
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.editing ? null : widget.onFocus,
        onPanUpdate:
            widget.editing ? (details) => widget.onMove(details.delta) : null,
        onHorizontalDragStart: widget.editing ? null : _beginSlide,
        onHorizontalDragUpdate: widget.editing ? null : _updateSlide,
        onHorizontalDragEnd: widget.editing ? null : (_) => _finishSlide(),
        onHorizontalDragCancel: widget.editing ? null : _finishSlide,
        child: Container(
          width: 148,
          height: 49,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0x55777777)),
            borderRadius: BorderRadius.circular(28),
            color: Colors.black.withValues(alpha: .58),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned(
                  left: 4 + _slide,
                  child: Container(
                      width: 43,
                      height: 43,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: _phase == _AfSlidePhase.focusing
                                  ? const Color(0xff96ebbe)
                                  : Colors.white70),
                          color: (_phase == _AfSlidePhase.idle
                                  ? Colors.white
                                  : const Color(0xff96ebbe))
                              .withValues(alpha: .12)),
                      child: const Center(
                          child: Text('AF',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700))))),
              const Positioned(
                  right: 27,
                  child: Text('→',
                      style: TextStyle(color: Colors.white70, fontSize: 15))),
              const Positioned(
                  right: 7,
                  child: Text('FOCUS',
                      style: TextStyle(
                          color: Color(0xff888888),
                          fontSize: 7,
                          letterSpacing: .8))),
            ],
          ),
        ),
      );
}

class LandscapeControl extends StatefulWidget {
  const LandscapeControl({
    required this.label,
    required this.caption,
    required this.onTap,
    this.wide = false,
    this.accent = false,
    this.danger = false,
    this.active = false,
    super.key,
  });
  final String label;
  final String caption;
  final VoidCallback onTap;
  final bool wide;
  final bool accent;
  final bool danger;
  final bool active;

  @override
  State<LandscapeControl> createState() => _LandscapeControlState();
}

class _LandscapeControlState extends State<LandscapeControl>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant LandscapeControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _pulse.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    final baseBorder = widget.accent
        ? const Color(0xaa96ebbe)
        : widget.danger
            ? const Color(0xaaeb9696)
            : const Color(0x55777777);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final pulse = widget.active ? _pulse.value : 0.0;
        final background = Color.lerp(Colors.black.withValues(alpha: .58), Colors.white, pulse)!;
        final foreground = pulse > .45 ? Colors.black : Colors.white;
        final caption = pulse > .45 ? Colors.black54 : const Color(0xff888888);
        return SizedBox(
          width: widget.wide ? 148 : 70,
          height: widget.wide ? 49 : 70,
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.wide ? 28 : 40),
              side: BorderSide(
                color: widget.active
                    ? Color.lerp(baseBorder, Colors.white, pulse)!
                    : baseBorder,
              ),
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(widget.wide ? 28 : 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.label,
                        style: TextStyle(
                            color: foreground,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0)),
                    if (widget.caption.isNotEmpty)
                      Text(widget.caption,
                          style: TextStyle(
                              color: caption,
                              fontSize: 7,
                              letterSpacing: .8)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ShotThumbnail extends StatelessWidget {
  const ShotThumbnail({
    required this.imageBytes,
    required this.onTap,
    super.key,
  });

  final Uint8List imageBytes;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 132,
            height: 88,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xccffffff)),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 12)
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              cacheWidth: 264,
              cacheHeight: 176,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
      );
}

class CapturedImageViewer extends StatefulWidget {
  const CapturedImageViewer({
    required this.previewBytes,
    required this.loadImages,
    required this.loadThumbnail,
    required this.loadFullSize,
    required this.loadFullSizeProgress,
    super.key,
  });

  final Uint8List previewBytes;
  final Future<List<CapturedImageEntry>> Function({int limit}) loadImages;
  final Future<Uint8List> Function(int handle) loadThumbnail;
  final Future<Uint8List> Function([int? handle]) loadFullSize;
  final Future<Uint8List> Function(
    int? handle, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) loadFullSizeProgress;

  @override
  State<CapturedImageViewer> createState() => _CapturedImageViewerState();
}

class _CapturedImageViewerState extends State<CapturedImageViewer> {
  static const _downloadChannel = MethodChannel('underlab/downloads');
  late MemoryImage _previewImageProvider;
  MemoryImage? _fullImageProvider;
  List<CapturedImageEntry> _images = const [];
  int _selectedIndex = 0;
  int _loadGeneration = 0;
  bool _loadingThumbnail = false;
  bool _loadingFull = false;
  Object? _error;
  static const _thumbnailCacheLimit = 192;
  static const _fullImageCacheLimit = 3;
  final LinkedHashMap<int, Uint8List> _thumbnailCache = LinkedHashMap();
  final Map<int, Future<Uint8List>> _thumbnailLoads = {};
  final LinkedHashMap<int, Uint8List> _fullImageCache = LinkedHashMap();
  final Set<int> _markedHandles = <int>{};
  bool _selectionMode = false;
  int _gridColumns = 4;
  bool _downloading = false;
  int _downloadedCount = 0;
  int _downloadTotal = 0;
  double _downloadProgress = 0;
  bool _cancelDownloadRequested = false;

  @override
  void initState() {
    super.initState();
    _previewImageProvider = MemoryImage(widget.previewBytes);
    unawaited(_initializeBrowser());
  }

  Future<void> _initializeBrowser() async {
    try {
      final images = await widget.loadImages(limit: 1000);
      if (!mounted) return;
      setState(() {
        _images = images;
        _selectedIndex = 0;
      });
      await _loadFullImage(images.isEmpty ? null : images.first.handle);
    } catch (_) {
      await _loadFullImage(null);
    }
  }

  Future<void> _selectImage(int index) async {
    if (index < 0 || index >= _images.length || index == _selectedIndex) return;
    final generation = ++_loadGeneration;
    setState(() {
      _selectedIndex = index;
      _fullImageProvider = null;
      _loadingThumbnail = true;
      _loadingFull = false;
      _error = null;
    });
    try {
      final bytes = await widget.loadThumbnail(_images[index].handle);
      if (!mounted || generation != _loadGeneration) return;
      final provider = MemoryImage(bytes);
      await precacheImage(provider, context);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _previewImageProvider = provider;
          _loadingThumbnail = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loadingThumbnail = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _loadFullImage([int? handle]) async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loadingFull = true;
      _error = null;
    });
    try {
      final cached = handle == null ? null : _fullImageCache.remove(handle);
      final image = cached ?? await widget.loadFullSize(handle);
      if (handle != null) {
        _fullImageCache[handle] = image;
        while (_fullImageCache.length > _fullImageCacheLimit) {
          _fullImageCache.remove(_fullImageCache.keys.first);
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      final provider = MemoryImage(image);
      // Decode the 9MP JPEG while the thumbnail remains visible. Swapping only
      // after the decoded frame is cached avoids a large decode on the
      // AnimatedSwitcher transition frame.
      await precacheImage(provider, context);
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _fullImageProvider = provider;
          _loadingFull = false;
        });
      }
    } catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _loadingFull = false;
          _error = error;
        });
      }
    }
  }

  Future<Uint8List> _thumbnailFor(int handle) {
    final cached = _thumbnailCache.remove(handle);
    if (cached != null) {
      _thumbnailCache[handle] = cached;
      return Future.value(cached);
    }
    final pending = _thumbnailLoads[handle];
    if (pending != null) return pending;
    final load = widget.loadThumbnail(handle).then((bytes) {
      _thumbnailLoads.remove(handle);
      _thumbnailCache[handle] = bytes;
      while (_thumbnailCache.length > _thumbnailCacheLimit) {
        _thumbnailCache.remove(_thumbnailCache.keys.first);
      }
      return bytes;
    }).catchError((Object error) {
      _thumbnailLoads.remove(handle);
      throw error;
    });
    _thumbnailLoads[handle] = load;
    return load;
  }

  Future<void> _downloadOne(
    CapturedImageEntry image, {
    required void Function(double) onProgress,
  }) async {
    final bytes = await widget.loadFullSizeProgress(
      image.handle,
      onProgress: (received, total) {
        if (_cancelDownloadRequested) {
          throw CameraApiException('download_cancelled');
        }
        onProgress(total > 0 ? received / total : 0);
      },
    );
    await _downloadChannel.invokeMethod<Map<Object?, Object?>>('saveImage', {
      'bytes': bytes,
      'filename':
          image.filename.isEmpty ? 'D810_${image.handle}.jpg' : image.filename,
      // Some camera listings expose only the object handle.  Do not collapse
      // every such image into the same empty dedupe key.
      'key': image.filename.isNotEmpty || image.size > 0
          ? '${image.filename}:${image.size}'
          : 'handle:${image.handle}',
    });
  }

  Future<void> _downloadSelected() async {
    final selected = _images.isEmpty ? null : _images[_selectedIndex];
    if (selected == null || _downloading) return;
    setState(() {
      _downloading = true;
      _downloadTotal = 1;
      _downloadedCount = 0;
      _downloadProgress = 0;
      _cancelDownloadRequested = false;
      _error = null;
    });
    try {
      await _downloadOne(
        selected,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      if (mounted)
        setState(() {
          _downloadedCount = 1;
          _downloadProgress = 1;
        });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('IMAGE SAVED TO DEVICE')),
        );
      }
    } catch (error) {
      if (mounted &&
          (error is! CameraApiException ||
              error.status != 'download_cancelled')) {
        setState(() => _error = error);
      }
      if (mounted &&
          error is CameraApiException &&
          error.status == 'download_cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DOWNLOAD CANCELLED')),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _downloading = false;
          _cancelDownloadRequested = false;
        });
    }
  }

  Future<void> _downloadAll({List<CapturedImageEntry>? targets}) async {
    final imagesToDownload = targets ?? _images;
    if (_downloading || imagesToDownload.isEmpty) return;
    setState(() {
      _downloading = true;
      _downloadedCount = 0;
      _downloadTotal = imagesToDownload.length;
      _downloadProgress = 0;
      _cancelDownloadRequested = false;
      _error = null;
    });
    try {
      for (final image in imagesToDownload) {
        if (!mounted) return;
        if (_cancelDownloadRequested) {
          throw CameraApiException('download_cancelled');
        }
        final completed = _downloadedCount;
        await _downloadOne(
          image,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _downloadProgress = (completed + progress) / _downloadTotal;
              });
            }
          },
        );
        if (mounted) {
          setState(() {
            _downloadedCount++;
            _downloadProgress = _downloadedCount / _downloadTotal;
          });
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('DOWNLOADED $_downloadedCount IMAGES')),
        );
      }
    } catch (error) {
      if (mounted &&
          (error is! CameraApiException ||
              error.status != 'download_cancelled')) {
        setState(() => _error = error);
      }
      if (mounted &&
          error is CameraApiException &&
          error.status == 'download_cancelled') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DOWNLOAD CANCELLED')),
        );
      }
    } finally {
      if (mounted)
        setState(() {
          _downloading = false;
          _cancelDownloadRequested = false;
        });
    }
  }

  void _cancelDownload() {
    if (!_downloading) return;
    setState(() => _cancelDownloadRequested = true);
  }

  void _toggleMarked(CapturedImageEntry image) {
    setState(() {
      if (!_markedHandles.add(image.handle)) {
        _markedHandles.remove(image.handle);
      }
    });
  }

  void _enterSelectionMode(CapturedImageEntry image) {
    setState(() {
      _selectionMode = true;
      _markedHandles.add(image.handle);
    });
  }

  Future<void> _showGrid() async {
    if (_images.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xff111111),
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .82,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      Text(
                        _selectionMode
                            ? 'SELECT MODE  •  MARKED ${_markedHandles.length}'
                            : 'CAPTURED IMAGES  •  VIEW ${_selectedIndex + 1}/${_images.length}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const Spacer(),
                      for (final columns in [4, 5, 10])
                        TextButton(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            setState(() => _gridColumns = columns);
                            unawaited(_showGrid());
                          },
                          child: Text('${columns}×$columns'),
                        ),
                      if (_selectionMode)
                        IconButton(
                          onPressed: () {
                            setState(() => _selectionMode = false);
                            setSheetState(() {});
                          },
                          icon: const Icon(Icons.done, color: Colors.white),
                          tooltip: 'Finish selection',
                        ),
                      IconButton(
                        onPressed: _downloading
                            ? null
                            : () {
                                final marked = _images
                                    .where((image) =>
                                        _markedHandles.contains(image.handle))
                                    .toList(growable: false);
                                Navigator.pop(sheetContext);
                                unawaited(_downloadAll(
                                    targets: marked.isEmpty ? null : marked));
                              },
                        icon: const Icon(Icons.download, color: Colors.white),
                        tooltip: _markedHandles.isEmpty
                            ? 'Download all'
                            : 'Download marked',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _gridColumns,
                      crossAxisSpacing: 4,
                      mainAxisSpacing: 4,
                    ),
                    itemCount: _images.length,
                    itemBuilder: (_, index) => FutureBuilder<Uint8List>(
                      future: _thumbnailFor(_images[index].handle),
                      builder: (_, snapshot) {
                        final bytes = snapshot.data;
                        return InkWell(
                          onTap: () {
                            if (_selectionMode) {
                              _toggleMarked(_images[index]);
                              setSheetState(() {});
                              return;
                            }
                            Navigator.pop(sheetContext);
                            unawaited(_selectImage(index));
                          },
                          onLongPress: () {
                            _enterSelectionMode(_images[index]);
                            setSheetState(() {});
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (bytes != null)
                                Image.memory(bytes,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.low)
                              else
                                const ColoredBox(
                                    color: Color(0xff242424),
                                    child: Icon(Icons.image,
                                        color: Colors.white38)),
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: .7),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 2),
                                    child: Text('${index + 1}',
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 9)),
                                  ),
                                ),
                              ),
                              if (index == _selectedIndex)
                                const Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.fromBorderSide(BorderSide(
                                          color: Colors.white, width: 3)),
                                    ),
                                    child: Align(
                                      alignment: Alignment.topRight,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.visibility,
                                            color: Colors.white, size: 18),
                                      ),
                                    ),
                                  ),
                                ),
                              if (_markedHandles
                                  .contains(_images[index].handle))
                                const Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.fromBorderSide(BorderSide(
                                          color: Colors.amber, width: 3)),
                                    ),
                                    child: Align(
                                      alignment: Alignment.topLeft,
                                      child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: Icon(Icons.check_circle,
                                            color: Colors.amber, size: 18),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _previousImage() => unawaited(_selectImage(_selectedIndex + 1));

  void _nextImage() => unawaited(_selectImage(_selectedIndex - 1));

  @override
  Widget build(BuildContext context) {
    final imageProvider = _fullImageProvider ?? _previewImageProvider;
    final selected = _images.isEmpty ? null : _images[_selectedIndex];
    final hasPrevious = _selectedIndex + 1 < _images.length;
    final hasNext = _selectedIndex > 0;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -250 && hasPrevious) _previousImage();
              if (velocity > 250 && hasNext) _nextImage();
            },
            child: InteractiveViewer(
              minScale: .5,
              maxScale: 4,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: Image.memory(
                    imageProvider.bytes,
                    key: ValueKey<ImageProvider>(imageProvider),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ),
          if (_loadingThumbnail || _loadingFull)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_error != null)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 76,
              child: Center(
                child: Text('IMAGE UNAVAILABLE',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
              ),
            ),
          if (_downloading)
            Positioned(
              right: 18,
              bottom: 18,
              child: SafeArea(
                top: false,
                left: false,
                child: SizedBox(
                  width: 190,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .78),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'DOWNLOADING ${(_downloadProgress * 100).round()}%  $_downloadedCount/$_downloadTotal',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10),
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: _downloadProgress,
                            minHeight: 3,
                          ),
                          const SizedBox(height: 5),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _cancelDownload,
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text('CANCEL'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (hasPrevious)
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton.filledTonal(
                  onPressed: _previousImage,
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous image',
                ),
              ),
            ),
          if (hasNext)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton.filledTonal(
                  onPressed: _nextImage,
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next image',
                ),
              ),
            ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected != null)
                    Flexible(
                      child: Text(
                        '${_selectedIndex + 1}/${_images.length}  ${selected.filename.isEmpty ? 'HANDLE ${selected.handle}' : selected.filename}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  if (selected != null && _fullImageProvider == null) ...[
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: _loadingThumbnail || _loadingFull
                          ? null
                          : () => unawaited(
                                _loadFullImage(selected.handle),
                              ),
                      icon: const Icon(Icons.hd, size: 18),
                      label: const Text('9MP'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: _showGrid,
                    icon: const Icon(Icons.grid_view),
                    tooltip: 'Image grid',
                  ),
                  if (selected != null)
                    IconButton.filledTonal(
                      onPressed: _downloading ? null : _downloadSelected,
                      icon: const Icon(Icons.download),
                      tooltip: 'Download selected image',
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: 'Close preview',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PreviewPanel extends StatelessWidget {
  const PreviewPanel({
    required this.liveView,
    required this.cameraReady,
    required this.faultActive,
    super.key,
  });
  final bool liveView;
  final bool cameraReady;
  final bool faultActive;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xff1d1d1d)),
          color: const Color(0xff050505),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            LiveViewFrame(active: liveView),
            Positioned(
              left: 10,
              bottom: 10,
              child: OverlayBadge(
                label: 'CAMERA',
                value: faultActive
                    ? 'ERROR'
                    : cameraReady
                        ? 'READY'
                        : 'OFFLINE',
              ),
            ),
            if (liveView)
              const Center(
                child: SizedBox(
                  width: 94,
                  height: 94,
                  child: CustomPaint(painter: FocusPainter()),
                ),
              ),
          ],
        ),
      );
}

class LiveViewFrame extends StatefulWidget {
  const LiveViewFrame({required this.active, this.onFps, super.key});

  final bool active;
  final ValueChanged<double>? onFps;

  @override
  State<LiveViewFrame> createState() => _LiveViewFrameState();
}

class _LiveViewFrameState extends State<LiveViewFrame> {
  static const MethodChannel _channel = MethodChannel('underlab/liveview');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (!mounted || call.method != 'fps') return;
    final value = (call.arguments as num?)?.toDouble() ?? 0;
    widget.onFps?.call(value);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: !widget.active
            ? const SizedBox.expand()
            : const AndroidView(
                viewType: 'underlab/liveview-web',
                layoutDirection: TextDirection.ltr,
              ),
      );
}

class ControlsPanel extends StatelessWidget {
  const ControlsPanel({
    required this.lastAction,
    required this.onCommand,
    super.key,
  });
  final String lastAction;
  final ValueChanged<String> onCommand;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SizedBox(height: 18),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: ControlStage(onCommand: onCommand),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              lastAction.toUpperCase(),
              style: const TextStyle(
                color: Color(0xff777777),
                fontSize: 10,
                letterSpacing: 1.6,
              ),
            ),
          ),
        ],
      );
}

class ControlStage extends StatelessWidget {
  const ControlStage({required this.onCommand, super.key});
  final ValueChanged<String> onCommand;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          return Stack(
            alignment: Alignment.center,
            children: [
              Align(
                  alignment: const Alignment(.48, -.72),
                  child: CameraButton(
                      label: 'AF',
                      caption: 'FOCUS',
                      kind: ButtonKind.accent,
                      onTap: () => onCommand('AF'))),
              Align(
                  alignment: const Alignment(.78, -.72),
                  child: CameraButton(
                      label: 'AF →',
                      caption: '',
                      kind: ButtonKind.accent,
                      size: 78,
                      onTap: () => onCommand('AF'))),
              Align(
                alignment: const Alignment(.78, -.12),
                child: CameraButton(
                  label: 'LIVE',
                  caption: 'START',
                  kind: ButtonKind.accent,
                  onTap: () => onCommand('LIVE'),
                ),
              ),
              Align(
                alignment: const Alignment(.48, .34),
                child: CameraButton(
                  label: 'STOP',
                  caption: 'LIVE',
                  kind: ButtonKind.danger,
                  onTap: () => onCommand('STOP'),
                ),
              ),
              Align(
                alignment: const Alignment(.02, .82),
                child: CameraButton(
                  label: 'DIAG',
                  caption: 'RECOVER',
                  kind: ButtonKind.danger,
                  onTap: () => onCommand('DIAGNOSE'),
                ),
              ),
            ],
          );
        },
      );
}

enum ButtonKind { normal, accent, primary, danger }

class CameraButton extends StatefulWidget {
  const CameraButton({
    required this.label,
    required this.caption,
    required this.onTap,
    this.kind = ButtonKind.normal,
    this.size = 82,
    this.active = false,
    super.key,
  });
  final String label;
  final String caption;
  final VoidCallback onTap;
  final ButtonKind kind;
  final double size;
  final bool active;

  @override
  State<CameraButton> createState() => _CameraButtonState();
}

class _CameraButtonState extends State<CameraButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didUpdateWidget(covariant CameraButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _pulse.repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    final border = switch (widget.kind) {
      ButtonKind.primary => const Color(0xff414141),
      ButtonKind.accent => const Color(0xff2c2c2c),
      ButtonKind.danger => const Color(0xff292929),
      ButtonKind.normal => const Color(0xff242424),
    };
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final pulse = widget.active ? _pulse.value : 0.0;
        final background = Color.lerp(const Color(0xff101010), Colors.white, pulse)!;
        final foreground = pulse > .45 ? Colors.black : Colors.white;
        final caption = pulse > .45 ? Colors.black54 : const Color(0xff777777);
        final activeBorder = Color.lerp(border, Colors.white, pulse)!;
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(widget.size > 100 ? 22 : widget.size / 2),
              side: BorderSide(color: widget.active ? activeBorder : border),
            ),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(widget.size > 100 ? 22 : widget.size / 2),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: foreground,
                        fontSize: widget.size > 100 ? 15 : 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.caption,
                      style: TextStyle(
                        color: caption,
                        fontSize: 8,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OverlayBadge extends StatelessWidget {
  const OverlayBadge({
    required this.label,
    required this.value,
    this.danger = false,
    this.warning = false,
    super.key,
  });
  final String label;
  final String value;
  final bool danger;
  final bool warning;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .56),
          border: (danger || warning)
              ? Border.all(
                  color: warning
                      ? const Color(0xffffd45c)
                      : const Color(0xffff5a5a),
                  width: 1,
                )
              : null,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xff999999),
              ),
              children: [
                if (label.isNotEmpty) TextSpan(text: '$label  '),
                TextSpan(
                  text: value,
                  style: TextStyle(
                    color: warning ? const Color(0xffffd45c) : Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class CameraReadinessControl extends StatelessWidget {
  const CameraReadinessControl({
    required this.ready,
    required this.recovering,
    required this.goodVisible,
    required this.warning,
    required this.recoveryTimedOut,
    required this.onTap,
    super.key,
  });

  final bool ready;
  final bool recovering;
  final bool goodVisible;
  final bool warning;
  final bool recoveryTimedOut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: warning
            ? const Color(0xff30290f)
            : recovering
                ? const Color(0xff2a0d0d)
                : Colors.black.withValues(alpha: .68),
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            width: 88,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                color: warning
                    ? const Color(0xffffd45c)
                    : recovering
                        ? const Color(0xffff4d4d)
                        : ready || goodVisible
                            ? const Color(0xaa96ebbe)
                            : const Color(0x66777777),
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (warning) ...[
                    const Text(
                      'CAMERA',
                      style: TextStyle(fontSize: 8, color: Color(0xff999999)),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'READY?',
                      style: TextStyle(
                        color: Color(0xffffd45c),
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'CAMERA',
                      style: TextStyle(fontSize: 8, color: Color(0xff999999)),
                    ),
                    const SizedBox(width: 5),
                    if (goodVisible)
                      const Text(
                        'GOOD!',
                        style: TextStyle(
                          color: Color(0xff96ebbe),
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else if (recovering && recoveryTimedOut)
                      const Text(
                        '!',
                        style: TextStyle(
                          color: Color(0xffff4d4d),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      )
                    else if (recovering)
                      const _BouncingEllipsis(color: Color(0xffff7777))
                    else if (ready)
                      const Text(
                        'READY',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    else
                      const _BouncingEllipsis(),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

class _BouncingEllipsis extends StatefulWidget {
  const _BouncingEllipsis({this.color = Colors.white});

  final Color color;

  @override
  State<_BouncingEllipsis> createState() => _BouncingEllipsisState();
}

class _BouncingEllipsisState extends State<_BouncingEllipsis>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final phase = (_controller.value - index * .18) % 1.0;
            final lift = math.max(0.0, math.sin(phase * math.pi * 2)) * 4;
            return Transform.translate(
              offset: Offset(0, -lift),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 1),
                child: Text(
                  '.',
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            );
          }),
        ),
      );
}

class CameraReadinessDetails extends StatelessWidget {
  const CameraReadinessDetails({
    required this.cameraReady,
    required this.cameraDetected,
    required this.hardwareDetected,
    required this.transportReady,
    required this.commandReady,
    required this.liveViewReady,
    required this.liveViewLimited,
    required this.liveViewLimitReason,
    required this.faultActive,
    required this.faultStage,
    required this.faultReason,
    required this.recoveryTimedOut,
    required this.readyAfterMs,
    required this.readinessAverageMs,
    required this.batteryPercent,
    super.key,
  });

  final bool cameraReady;
  final bool cameraDetected;
  final bool hardwareDetected;
  final bool transportReady;
  final bool commandReady;
  final bool liveViewReady;
  final bool liveViewLimited;
  final String liveViewLimitReason;
  final bool faultActive;
  final String faultStage;
  final String faultReason;
  final bool recoveryTimedOut;
  final int readyAfterMs;
  final int readinessAverageMs;
  final int? batteryPercent;

  String _seconds(int milliseconds) =>
      '${(milliseconds / 1000).toStringAsFixed(1)}s';

  String _reasonLabel(String reason) => switch (reason) {
        'bridge_unavailable' => '카메라 브리지 응답 없음',
        'command_not_ready' => '커맨드 세션 준비 안 됨',
        'transport_not_ready' => 'PTP 세션 준비 안 됨',
        'live_view_not_ready' => '라이브뷰 프레임 전달 안 됨',
        'ddserver_not_running' => '카메라 전송 서비스 중단',
        _ => reason == 'none' ? '원인 확인 중' : reason,
      };

  @override
  Widget build(BuildContext context) {
    final detected = cameraDetected && hardwareDetected;
    return Container(
      width: 176,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .82),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x556f6f6f)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ReadinessStage(
            label: 'CAMERA',
            complete: detected,
            fault: faultActive && faultStage == 'camera',
          ),
          _ReadinessStage(
            label: 'PTP',
            complete: transportReady,
            fault: faultActive && faultStage == 'ptp',
          ),
          _ReadinessStage(
            label: 'COMMAND',
            complete: commandReady,
            fault: faultActive && faultStage == 'command',
          ),
          _ReadinessStage(
            label: 'LIVE VIEW',
            complete: liveViewReady,
            fault: faultActive && faultStage == 'live_view' && !liveViewLimited,
            warning: liveViewLimited,
          ),
          _ReadinessStage(
            label: 'APPLICATION',
            complete: cameraReady,
            fault: faultActive && faultStage == 'application',
          ),
          if (faultActive) ...[
            const SizedBox(height: 7),
            Text(
              recoveryTimedOut
                  ? '복구 시간 초과 · DIAG로 재진단'
                  : '${_reasonLabel(faultReason)} · 자동 복구 중',
              style: const TextStyle(
                color: Color(0xffff7777),
                fontSize: 8,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (readyAfterMs > 0 || readinessAverageMs > 0) ...[
            const SizedBox(height: 7),
            Text(
              [
                if (readyAfterMs > 0)
                  '${cameraReady ? 'LAST' : 'CURRENT'} ${_seconds(readyAfterMs)}',
                if (readinessAverageMs > 0)
                  'AVG ${_seconds(readinessAverageMs)}',
              ].join('  ·  '),
              style: const TextStyle(
                color: Color(0xff888888),
                fontSize: 8,
                letterSpacing: .4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadinessStage extends StatelessWidget {
  const _ReadinessStage({
    required this.label,
    required this.complete,
    this.fault = false,
    this.warning = false,
  });

  final String label;
  final bool complete;
  final bool fault;
  final bool warning;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            if (warning)
              Container(
                width: 11,
                height: 11,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xffffd45c),
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '?',
                  style: TextStyle(
                    color: Color(0xff211d0c),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              )
            else
              Icon(
                fault
                    ? Icons.error
                    : complete
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                size: 11,
                color: fault
                    ? const Color(0xffff4d4d)
                    : complete
                        ? const Color(0xff96ebbe)
                        : const Color(0xff666666),
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: warning
                    ? const Color(0xffffd45c)
                    : fault
                        ? const Color(0xffff7777)
                        : complete
                            ? Colors.white
                            : const Color(0xff888888),
                fontSize: 8,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      );
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.label, required this.value, super.key});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Text(
        '$label $value',
        style: const TextStyle(
          color: Color(0xff8d8d8d),
          fontSize: 10,
          letterSpacing: .8,
        ),
      );
}

class Footer extends StatelessWidget {
  const Footer({required this.lastAction, super.key});
  final String lastAction;
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 28,
        child: Center(
          child: Text(
            'D810 REMOTE  ·  ${lastAction.toUpperCase()}',
            style: const TextStyle(
              color: Color(0xff555555),
              fontSize: 9,
              letterSpacing: 1.2,
            ),
          ),
        ),
      );
}

class FocusPainter extends CustomPainter {
  const FocusPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xff777777)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromCenter(center: size.center(Offset.zero), width: 42, height: 42),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
