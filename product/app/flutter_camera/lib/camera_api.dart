import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class CameraApiException implements Exception {
  CameraApiException(this.status, [this.message = '']);

  final String status;
  final String message;

  @override
  String toString() => message.isEmpty ? status : '$status: $message';
}

class CapturedImageEntry {
  const CapturedImageEntry({
    required this.handle,
    required this.filename,
    required this.size,
    required this.thumbWidth,
    required this.thumbHeight,
  });

  final int handle;
  final String filename;
  final int size;
  final int thumbWidth;
  final int thumbHeight;

  factory CapturedImageEntry.fromJson(Map<String, dynamic> json) =>
      CapturedImageEntry(
        handle: (json['handle'] as num?)?.toInt() ?? 0,
        filename: json['filename']?.toString() ?? '',
        size: (json['size'] as num?)?.toInt() ?? 0,
        thumbWidth: (json['thumbWidth'] as num?)?.toInt() ?? 0,
        thumbHeight: (json['thumbHeight'] as num?)?.toInt() ?? 0,
      );
}

class CameraCaptureEvent {
  const CameraCaptureEvent({
    required this.captureEvent,
    required this.captureEventSeq,
    required this.previewReady,
    required this.propertyChanged,
    required this.propertyCode,
    required this.propertyEventAt,
  });

  final bool captureEvent;
  final int captureEventSeq;
  final bool previewReady;
  final bool propertyChanged;
  final int propertyCode;
  final int propertyEventAt;

  factory CameraCaptureEvent.fromJson(Map<String, dynamic> json) =>
      CameraCaptureEvent(
        captureEvent: json['captureEvent'] == true,
        captureEventSeq: (json['captureEventSeq'] as num?)?.toInt() ?? 0,
        previewReady: json['previewReady'] == true,
        propertyChanged: json['propertyChanged'] == true,
        propertyCode: (json['propertyCode'] as num?)?.toInt() ?? 0,
        propertyEventAt: (json['propertyEventAt'] as num?)?.toInt() ?? 0,
      );
}

class ManualCameraStatus {
  const ManualCameraStatus({
    required this.manualMode,
    required this.mode,
    required this.aperture,
    required this.shutter,
    required this.iso,
    required this.configuredIso,
    required this.actualIso,
    required this.captureMode,
    required this.autoIso,
  });

  final bool manualMode;
  final int mode;
  final int aperture;
  final int shutter;
  final int iso;
  final int configuredIso;
  final int? actualIso;
  final int captureMode;
  final bool autoIso;

  factory ManualCameraStatus.fromJson(Map<String, dynamic> json) =>
      ManualCameraStatus(
        manualMode: json['manualMode'] == true,
        mode: (json['mode'] as num?)?.toInt() ?? 0,
        aperture: (json['aperture'] as num?)?.toInt() ?? 0,
        shutter: (json['shutter'] as num?)?.toInt() ?? 0,
        iso: (json['iso'] as num?)?.toInt() ?? 0,
        configuredIso: (json['configuredIso'] as num?)?.toInt() ?? 0,
        actualIso: (json['actualIso'] as num?)?.toInt(),
        captureMode: (json['captureMode'] as num?)?.toInt() ?? 0,
        autoIso: json['autoIso'] == true,
      );
}

class CameraRuntimeStatus {
  const CameraRuntimeStatus({
    required this.cameraReady,
    required this.liveView,
    required this.batteryPercent,
    required this.status,
    required this.cameraDetected,
    required this.hardwareDetected,
    required this.transportReady,
    required this.readinessState,
    required this.readinessReason,
    required this.uiPhase,
    required this.uiDetail,
    required this.readyAfterMs,
    required this.readinessAverageMs,
    required this.readinessMaxMs,
    required this.liveViewReady,
    required this.liveViewLimited,
    required this.liveViewLimitReason,
    required this.commandReady,
    required this.operationalState,
    required this.limitationActive,
    required this.limitationStage,
    required this.limitationReason,
    required this.faultActive,
    required this.faultDomain,
    required this.faultStage,
    required this.faultReason,
  });

  final bool cameraReady;
  final bool liveView;
  final int? batteryPercent;
  final String status;
  final bool cameraDetected;
  final bool hardwareDetected;
  final bool transportReady;
  final String readinessState;
  final String readinessReason;
  final String uiPhase;
  final String uiDetail;
  final int readyAfterMs;
  final int readinessAverageMs;
  final int readinessMaxMs;
  final bool liveViewReady;
  final bool liveViewLimited;
  final String liveViewLimitReason;
  final bool commandReady;
  final String operationalState;
  final bool limitationActive;
  final String limitationStage;
  final String limitationReason;
  final bool faultActive;
  final String faultDomain;
  final String faultStage;
  final String faultReason;

  bool get fullyReady =>
      cameraReady &&
      cameraDetected &&
      hardwareDetected &&
      transportReady &&
      commandReady &&
      (liveViewReady || liveViewLimited) &&
      (readinessState == 'ready' || readinessState == 'limited') &&
      !faultActive;

  factory CameraRuntimeStatus.fromJson(Map<String, dynamic> json) {
    final status = json['status']?.toString() ?? 'unavailable';
    final rawBattery = json['batteryPercent'] ?? json['batteryLevel'];
    final cameraDetected = json['cameraDetected'] == true;
    final hardwareDetected = json['hardwareDetected'] == true;
    final transportReady = json['transportReady'] == true;
    final hasUnifiedReadiness = json.containsKey('appReady');
    final cameraReady = hasUnifiedReadiness
        ? json['appReady'] == true
        : cameraDetected && hardwareDetected && transportReady;
    return CameraRuntimeStatus(
      cameraReady: cameraReady,
      liveView: json['liveView'] == true || status == 'liveview_on',
      batteryPercent:
          rawBattery is num ? rawBattery.round().clamp(0, 100) : null,
      status: status,
      cameraDetected: cameraDetected,
      hardwareDetected: hardwareDetected,
      transportReady: transportReady,
      readinessState: json['readinessState']?.toString() ??
          (cameraReady ? 'ready' : (cameraDetected ? 'verifying' : 'offline')),
      readinessReason: json['readinessReason']?.toString() ?? '',
      uiPhase: json['uiPhase']?.toString() ?? '',
      uiDetail: json['uiDetail']?.toString() ?? '',
      readyAfterMs: (json['readyAfterMs'] as num?)?.toInt() ?? 0,
      readinessAverageMs: (json['readinessAverageMs'] as num?)?.toInt() ?? 0,
      readinessMaxMs: (json['readinessMaxMs'] as num?)?.toInt() ?? 0,
      liveViewReady: json.containsKey('liveViewReady')
          ? json['liveViewReady'] == true
          : transportReady,
      liveViewLimited: json['liveViewLimited'] == true,
      liveViewLimitReason: json['liveViewLimitReason']?.toString() ?? '',
      commandReady: json.containsKey('commandReady')
          ? json['commandReady'] == true
          : transportReady,
      operationalState: json['operationalState']?.toString() ??
          (json['liveViewLimited'] == true ? 'limited' : 'normal'),
      limitationActive: json['limitationActive'] == true,
      limitationStage: json['limitationStage']?.toString() ?? '',
      limitationReason: json['limitationReason']?.toString() ?? '',
      faultActive: json['faultActive'] == true,
      faultDomain: json['faultDomain']?.toString() ?? 'none',
      faultStage: json['faultStage']?.toString() ?? 'none',
      faultReason: json['faultReason']?.toString() ?? 'none',
    );
  }
}

enum _RequestPriority { emergency, urgent, normal, background }

typedef _ScheduledSender = Future<Map<String, dynamic>> Function();

class _QueuedRequest {
  _QueuedRequest(this.action, this.parameters, this.traceId, {this.sender});

  final String action;
  final Map<String, String> parameters;
  final String traceId;
  final _ScheduledSender? sender;
  final List<Completer<Map<String, dynamic>>> completers = [];
}

class CameraApi {
  CameraApi({
    // Camera control stays on the Opal access-point LAN.  Tailscale is used
    // only by the PC-side log collection path.
    this.baseUrl = 'http://192.168.8.1',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;
  final Queue<_QueuedRequest> _emergency = Queue<_QueuedRequest>();
  final Queue<_QueuedRequest> _urgent = Queue<_QueuedRequest>();
  final Queue<_QueuedRequest> _normal = Queue<_QueuedRequest>();
  final Queue<_QueuedRequest> _background = Queue<_QueuedRequest>();
  final LinkedHashMap<String, _QueuedRequest> _settings =
      LinkedHashMap<String, _QueuedRequest>();
  final LinkedHashMap<String, int> _traceStartedAtMs = LinkedHashMap();
  Timer? _settingSettleTimer;
  bool _settingBatchReady = false;
  bool _running = false;
  bool _closed = false;
  final String _runId = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  int _traceSequence = 0;
  int _commandSequence = 0;
  static const int _telemetryRotateBytes = 2 * 1024 * 1024;

  File? get _telemetryFile => Platform.isAndroid
      ? File(
          '/data/user/0/com.example.underlab_camera/files/field-events.jsonl')
      : null;

  String newTraceId([String scope = 'operation']) {
    final safeScope = scope.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '-');
    final traceId = '$_runId-$safeScope-${++_traceSequence}';
    _traceStartedAtMs[traceId] = DateTime.now().millisecondsSinceEpoch;
    while (_traceStartedAtMs.length > 256) {
      _traceStartedAtMs.remove(_traceStartedAtMs.keys.first);
    }
    return traceId;
  }

  Future<void> close() async {
    _closed = true;
    _settingSettleTimer?.cancel();
    final error = StateError('CameraApi is closed');
    for (final request in [
      ..._emergency,
      ..._urgent,
      ..._normal,
      ..._background,
      ..._settings.values,
    ]) {
      for (final completer in request.completers) {
        if (!completer.isCompleted) completer.completeError(error);
      }
    }
    _emergency.clear();
    _urgent.clear();
    _normal.clear();
    _background.clear();
    _settings.clear();
    _client.close();
  }

  Future<String> action(String name, {String? traceId}) {
    final priority = switch (name) {
      // STOP and RESET fence every queued camera operation as soon as the
      // currently executing transport command returns.
      'live-off' || 'reset' || 'diagnose' => _RequestPriority.emergency,
      'af' ||
      'shutter' ||
      'shutter-prepare' ||
      'shutter-hold-start' ||
      'shutter-hold-stop' ||
      'live-on' =>
        _RequestPriority.urgent,
      _ => _RequestPriority.normal,
    };
    return _enqueue(name, const {}, priority, traceId: traceId)
        .then(jsonEncode);
  }

  Future<Map<String, dynamic>> diagnose({String? traceId}) => _enqueue(
        'diagnose',
        const {},
        _RequestPriority.emergency,
        traceId: traceId,
      );

  // The preview endpoint is intentionally thumbnail-only. Full JPEG transfer
  // is deferred until the user opens the captured image.
  Future<Uint8List> capturedPreview({String? traceId}) =>
      _getCaptured('/cgi-bin/captured-preview', traceId: traceId);

  Future<CameraCaptureEvent> captureEvents() async {
    final decoded = await _enqueueScheduled(
      'capture-event',
      const {},
      _RequestPriority.background,
      () => _getJson('/cgi-bin/capture-event',
          timeout: const Duration(seconds: 6)),
    );
    return CameraCaptureEvent.fromJson(decoded);
  }

  Future<List<CapturedImageEntry>> capturedImages({int limit = 1000}) async {
    final uri = Uri.parse('$baseUrl/cgi-bin/captured-images').replace(
      queryParameters: {
        'limit': '$limit',
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final response = await _client.get(uri, headers: const {
      'Cache-Control': 'no-cache',
      'X-D810-Client': 'flutter-camera',
    }).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CameraApiException('captured_images_unavailable');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      throw CameraApiException('captured_images_unavailable');
    }
    final rawImages = decoded['images'];
    if (rawImages is! List) return const [];
    return rawImages
        .whereType<Map<String, dynamic>>()
        .map(CapturedImageEntry.fromJson)
        .where((image) => image.handle > 0)
        .toList(growable: false);
  }

  Future<Uint8List> capturedThumbnail(int handle) => _getCaptured(
        '/cgi-bin/captured-thumbnail',
        parameters: {'handle': '$handle'},
      );

  Future<Uint8List> capturedObject([int? handle]) => _getCaptured(
        '/cgi-bin/captured-object',
        parameters: handle == null ? null : {'handle': '$handle'},
      );

  Future<Uint8List> capturedObjectWithProgress(
    int? handle, {
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    final traceId = newTraceId('captured-object-stream');
    final commandId = '$traceId-${++_commandSequence}';
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse('$baseUrl/cgi-bin/captured-object').replace(
      queryParameters: handle == null ? null : {'handle': '$handle'},
    );
    final request = http.Request('GET', uri)
      ..headers.addAll(const {
        'Cache-Control': 'no-cache',
        'X-D810-Client': 'flutter-camera',
      })
      ..headers.addAll({
        'X-D810-Trace': traceId,
        'X-D810-Command-Id': commandId,
        'X-D810-Event': 'captured-object-stream',
      });
    http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(
            const Duration(seconds: 120),
          );
    } catch (error) {
      _telemetry('request_completed', traceId, commandId,
          action: 'captured-object-stream',
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: error.runtimeType.toString());
      rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _telemetry('request_completed', traceId, commandId,
          action: 'captured-object-stream',
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: 'http_${response.statusCode}');
      throw CameraApiException('captured_object_unavailable');
    }
    final total = response.contentLength ?? 0;
    var received = 0;
    final chunks = <List<int>>[];
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 120),
      )) {
        chunks.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } catch (error) {
      _telemetry('request_completed', traceId, commandId,
          action: 'captured-object-stream',
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          bytes: received,
          errorCode: error.runtimeType.toString());
      rethrow;
    }
    final bytes = Uint8List(received);
    var offset = 0;
    for (final chunk in chunks) {
      bytes.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    _telemetry('request_completed', traceId, commandId,
        action: 'captured-object-stream',
        result: 'PASS',
        durationMs: stopwatch.elapsedMilliseconds,
        bytes: bytes.length);
    return bytes;
  }

  Future<CameraRuntimeStatus> runtimeStatus() async {
    final decoded = await _enqueueScheduled(
      'runtime-status',
      const {},
      _RequestPriority.background,
      () =>
          _getJson('/cgi-bin/status-v21', timeout: const Duration(seconds: 8)),
    );
    return CameraRuntimeStatus.fromJson(decoded);
  }

  Future<CameraRuntimeStatus> bootstrapRuntime() async {
    final decoded = await _enqueueScheduled(
      'project-boot',
      const {},
      _RequestPriority.emergency,
      () => _getJson('/cgi-bin/session-manager',
          parameters: const {'boot': 'flutter-project'},
          timeout: const Duration(seconds: 180)),
    );
    return CameraRuntimeStatus.fromJson(decoded);
  }

  Future<int?> batteryPercent() async {
    final status = await runtimeStatus();
    return status.batteryPercent;
  }

  Future<Uint8List> _getCaptured(
    String path, {
    Map<String, String>? parameters,
    String? traceId,
  }) async {
    final effectiveTraceId = traceId ?? newTraceId('captured');
    final commandId = '$effectiveTraceId-${++_commandSequence}';
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: {
        ...?parameters,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'Cache-Control': 'no-cache',
        'X-D810-Client': 'flutter-camera',
        'X-D810-Trace': effectiveTraceId,
        'X-D810-Command-Id': commandId,
        'X-D810-Event': 'captured-image',
      }).timeout(const Duration(seconds: 12));
    } catch (error) {
      _telemetry('request_completed', effectiveTraceId, commandId,
          action: path,
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: error.runtimeType.toString());
      rethrow;
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        response.bodyBytes.isEmpty) {
      _telemetry('request_completed', effectiveTraceId, commandId,
          action: path,
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: 'http_${response.statusCode}');
      throw CameraApiException('captured_image_unavailable', path);
    }
    _telemetry('request_completed', effectiveTraceId, commandId,
        action: path,
        result: 'PASS',
        durationMs: stopwatch.elapsedMilliseconds,
        bytes: response.bodyBytes.length);
    return response.bodyBytes;
  }

  Future<ManualCameraStatus> manualStatus() =>
      _enqueue('manual-status', const {}, _RequestPriority.normal)
          .then(ManualCameraStatus.fromJson);

  Future<int> setManualSetting(String key, int value) {
    return _setCoalesced(
      queueKey: key,
      action: 'manual-set',
      parameters: {'key': key, 'value': '$value'},
      fallbackValue: value,
    );
  }

  Future<ManualCameraStatus> setManualSettingAndVerify(
      String key, int value) async {
    await setManualSetting(key, value);
    final status = await manualStatus();
    final actual = switch (key) {
      'aperture' => status.aperture,
      'shutter' => status.shutter,
      _ => status.iso,
    };
    if (!status.manualMode || actual != value) {
      throw CameraApiException(
          'manual_setting_unconfirmed', '$key requested=$value actual=$actual');
    }
    return status;
  }

  Future<int> setManualMode() {
    return _setCoalesced(
      queueKey: 'mode',
      action: 'manual-mode',
      parameters: const {},
      fallbackValue: 1,
    );
  }

  Future<void> setAutoIso(bool enabled) {
    return _enqueue(
      'auto-iso',
      {'value': enabled ? '1' : '0'},
      _RequestPriority.normal,
    ).then((_) {});
  }

  Future<int> _setCoalesced({
    required String queueKey,
    required String action,
    required Map<String, String> parameters,
    required int fallbackValue,
  }) {
    if (_closed) return Future<int>.error(StateError('CameraApi is closed'));
    final completer = Completer<Map<String, dynamic>>();
    final replacement = _QueuedRequest(action, parameters, newTraceId(action))
      ..completers.add(completer);
    final previous = _settings.remove(queueKey);
    if (previous != null) {
      replacement.completers.insertAll(0, previous.completers);
    }
    _settings[queueKey] = replacement;
    _settingBatchReady = false;
    _settingSettleTimer?.cancel();
    _settingSettleTimer = Timer(const Duration(milliseconds: 90), () {
      _settingBatchReady = true;
      _pump();
    });
    return completer.future.then(
      (json) =>
          (json['value'] as num?)?.toInt() ??
          (json['mode'] as num?)?.toInt() ??
          fallbackValue,
    );
  }

  Future<Map<String, dynamic>> _enqueue(
    String action,
    Map<String, String> parameters,
    _RequestPriority priority, {
    String? traceId,
  }) {
    if (_closed) {
      return Future<Map<String, dynamic>>.error(
          StateError('CameraApi is closed'));
    }
    final completer = Completer<Map<String, dynamic>>();
    final request =
        _QueuedRequest(action, parameters, traceId ?? newTraceId(action))
          ..completers.add(completer);
    switch (priority) {
      case _RequestPriority.emergency:
        _emergency.add(request);
        break;
      case _RequestPriority.urgent:
        _urgent.add(request);
        break;
      case _RequestPriority.normal:
        _normal.add(request);
        break;
      case _RequestPriority.background:
        _background.add(request);
        break;
    }
    _pump();
    return completer.future;
  }

  Future<Map<String, dynamic>> _enqueueScheduled(
    String action,
    Map<String, String> parameters,
    _RequestPriority priority,
    _ScheduledSender sender, {
    String? traceId,
  }) {
    if (_closed) {
      return Future<Map<String, dynamic>>.error(
          StateError('CameraApi is closed'));
    }
    final completer = Completer<Map<String, dynamic>>();
    final request = _QueuedRequest(
      action,
      parameters,
      traceId ?? newTraceId(action),
      sender: sender,
    )..completers.add(completer);
    switch (priority) {
      case _RequestPriority.emergency:
        _emergency.add(request);
        break;
      case _RequestPriority.urgent:
        _urgent.add(request);
        break;
      case _RequestPriority.normal:
        _normal.add(request);
        break;
      case _RequestPriority.background:
        _background.add(request);
        break;
    }
    _pump();
    return completer.future;
  }

  void _pump() {
    if (_running || _closed) return;
    _QueuedRequest? request;
    if (_emergency.isNotEmpty) {
      request = _emergency.removeFirst();
    } else if (_urgent.isNotEmpty) {
      request = _urgent.removeFirst();
    } else if (_settingBatchReady && _settings.isNotEmpty) {
      final key = _settings.keys.first;
      request = _settings.remove(key);
    } else if (_normal.isNotEmpty) {
      request = _normal.removeFirst();
    } else if (_background.isNotEmpty) {
      request = _background.removeFirst();
    }
    if (request == null) return;
    _running = true;
    final operation = request.sender == null
        ? _send(request.action, request.parameters, request.traceId)
        : request.sender!();
    operation.then((result) {
      for (final completer in request!.completers) {
        if (!completer.isCompleted) completer.complete(result);
      }
    }, onError: (Object error, StackTrace stackTrace) {
      for (final completer in request!.completers) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      }
    }).whenComplete(() {
      _running = false;
      if (_settings.isEmpty) _settingBatchReady = false;
      _pump();
    });
  }

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? parameters,
    required Duration timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(
      queryParameters: {
        ...?parameters,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
    final response = await _client.get(uri, headers: const {
      'Cache-Control': 'no-cache',
      'X-D810-Client': 'flutter-camera',
    }).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CameraApiException(path.contains('capture-event')
          ? 'capture_event_unavailable'
          : path.contains('status-v21')
              ? 'status_unavailable'
              : 'project_boot_unavailable');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
      if (path.contains('capture-event')) {
        throw CameraApiException('capture_event_unavailable');
      }
      if (path.contains('status-v21')) {
        throw CameraApiException('invalid_status');
      }
      final stage =
          decoded is Map<String, dynamic> ? decoded['stage']?.toString() : null;
      throw CameraApiException(stage ?? 'project_boot_failed');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _send(
    String name,
    Map<String, String> parameters,
    String traceId,
  ) async {
    final commandId = '$traceId-${++_commandSequence}';
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse('$baseUrl/cgi-bin/action-v21').replace(
      queryParameters: {'action': name, ...parameters},
    );
    http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'Cache-Control': 'no-cache',
        'X-D810-Client': 'flutter-camera',
        'X-D810-Trace': traceId,
        'X-D810-Command-Id': commandId,
        'X-D810-Event': 'action',
        'X-D810-Action': name,
        'X-D810-Ui-At':
            '${_traceStartedAtMs[traceId] ?? DateTime.now().millisecondsSinceEpoch}',
      }).timeout(Duration(
          seconds: name == 'diagnose' ? 240 : (name == 'reset' ? 45 : 12)));
    } catch (error) {
      _telemetry('request_completed', traceId, commandId,
          action: name,
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: error.runtimeType.toString());
      rethrow;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _telemetry('request_completed', traceId, commandId,
          action: name,
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: 'http_${response.statusCode}');
      throw CameraApiException('http_${response.statusCode}', name);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      _telemetry('request_completed', traceId, commandId,
          action: name,
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: 'invalid_response');
      throw CameraApiException('invalid_response', name);
    }
    if (decoded is! Map<String, dynamic>) {
      _telemetry('request_completed', traceId, commandId,
          action: name,
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: 'invalid_response');
      throw CameraApiException('invalid_response', name);
    }
    if (decoded['ok'] != true) {
      _telemetry('request_completed', traceId, commandId,
          action: name,
          result: 'FAIL',
          durationMs: stopwatch.elapsedMilliseconds,
          errorCode: decoded['status']?.toString() ?? 'camera_error',
          sessionId: decoded['sessionId']);
      throw CameraApiException(
        decoded['status']?.toString() ?? 'camera_error',
        decoded['message']?.toString() ?? name,
      );
    }
    _telemetry('request_completed', traceId, commandId,
        action: name,
        result: 'PASS',
        durationMs: stopwatch.elapsedMilliseconds,
        sessionId: decoded['sessionId']);
    return decoded;
  }

  void _telemetry(
    String event,
    String traceId,
    String commandId, {
    required String action,
    required String result,
    required int durationMs,
    String? errorCode,
    Object? sessionId,
    int? bytes,
  }) {
    final line = jsonEncode({
      'wall': DateTime.now().toUtc().toIso8601String(),
      'component': 's10-app',
      'event': event,
      'traceId': traceId,
      'commandId': commandId,
      'action': action,
      'result': result,
      'durationMs': durationMs,
      if (_traceStartedAtMs[traceId] != null)
        'uiAtMs': _traceStartedAtMs[traceId],
      if (errorCode != null) 'errorCode': errorCode,
      if (sessionId != null) 'sessionId': sessionId,
      if (bytes != null) 'bytes': bytes,
    });
    developer.log(line, name: 'underlab.camera.telemetry');
    _persistTelemetry(line);
  }

  void _persistTelemetry(String line) {
    final file = _telemetryFile;
    if (file == null) return;
    try {
      if (file.existsSync() && file.lengthSync() >= _telemetryRotateBytes) {
        final previous = File('${file.path}.1');
        if (previous.existsSync()) previous.deleteSync();
        file.renameSync(previous.path);
      }
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (error) {
      developer.log('telemetry_persist_failed: $error',
          name: 'underlab.camera.telemetry');
    }
  }
}
