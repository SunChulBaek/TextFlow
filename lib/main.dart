import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const TextFlowApp());
}

class TextFlowApp extends StatelessWidget {
  const TextFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TextFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
      ),
      home: const SmsListenerPage(),
    );
  }
}

class SmsEvent {
  const SmsEvent({
    required this.messageType,
    required this.address,
    required this.body,
    required this.receivedAt,
  });

  final String messageType;
  final String address;
  final String body;
  final DateTime receivedAt;

  factory SmsEvent.fromMap(Map<Object?, Object?> map) {
    final rawTimestamp = map['receivedAt'];
    final timestamp = switch (rawTimestamp) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? DateTime.now().millisecondsSinceEpoch,
      _ => DateTime.now().millisecondsSinceEpoch,
    };

    return SmsEvent(
      messageType: (map['messageType'] as String?)?.toLowerCase() == 'mms' ? 'mms' : 'sms',
      address: (map['address'] as String?)?.trim().isNotEmpty == true
          ? map['address']! as String
          : '알 수 없음',
      body: (map['body'] as String?)?.trim() ?? '',
      receivedAt: DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
  }
}

class SmsListenerPage extends StatefulWidget {
  const SmsListenerPage({super.key});

  @override
  State<SmsListenerPage> createState() => _SmsListenerPageState();
}

class _SmsListenerPageState extends State<SmsListenerPage>
    with WidgetsBindingObserver {
  static const EventChannel _smsEvents = EventChannel('textflow/sms_events');
  static const MethodChannel _smsStore = MethodChannel('textflow/sms_store');

  StreamSubscription<dynamic>? _smsSubscription;
  PermissionStatus? _permissionStatus;
  SmsEvent? _latestSms;
  String _statusMessage = '초기화 중...';
  String? _errorMessage;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initializeSmsHandling());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _smsSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshLatestSmsFromStore());
    }
  }

  Future<void> _initializeSmsHandling() async {
    if (!Platform.isAndroid) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = 'SMS/MMS 수신 이벤트는 Android에서만 지원됩니다.';
        _isListening = false;
      });
      return;
    }

    await _refreshLatestSmsFromStore();
    await _requestPermissionAndStartListening();
  }

  Future<void> _requestPermissionAndStartListening() async {
    setState(() {
      _statusMessage = '메시지 권한을 확인하는 중입니다...';
      _errorMessage = null;
    });

    try {
      final currentStatus = await Permission.sms.status;
      final resolvedStatus = currentStatus.isGranted
          ? currentStatus
          : await Permission.sms.request();

      if (!mounted) {
        return;
      }

      setState(() {
        _permissionStatus = resolvedStatus;
      });

      if (!resolvedStatus.isGranted) {
        setState(() {
          _statusMessage = '메시지 수신 권한이 필요합니다.';
          _isListening = false;
        });
        return;
      }

      await _startListening();
    } on MissingPluginException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = '플랫폼 채널을 사용할 수 없습니다.';
        _errorMessage = error.message;
        _isListening = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage = '메시지 권한 확인에 실패했습니다.';
        _errorMessage = error.toString();
        _isListening = false;
      });
    }
  }

  Future<void> _startListening() async {
    await _smsSubscription?.cancel();

    if (!mounted) {
      return;
    }

    setState(() {
      _statusMessage = '메시지 수신 대기 중';
      _errorMessage = null;
      _isListening = true;
    });

    _smsSubscription = _smsEvents.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map<Object?, Object?>) {
          if (!mounted) {
            return;
          }

          setState(() {
            _statusMessage = '알 수 없는 메시지 이벤트 형식입니다.';
            _isListening = false;
          });
          return;
        }

        final sms = SmsEvent.fromMap(event);
        if (!mounted) {
          return;
        }

        setState(() {
          _latestSms = sms;
          _statusMessage = '새 메시지를 수신했습니다.';
          _errorMessage = null;
          _isListening = true;
        });
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }

        setState(() {
          _statusMessage = '메시지 수신 대기 중 오류가 발생했습니다.';
          _errorMessage = error.toString();
          _isListening = false;
        });
      },
      cancelOnError: false,
    );
  }

  Future<void> _refreshLatestSmsFromStore() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      final event = await _smsStore.invokeMapMethod<Object?, Object?>('getLatestMessage');
      if (event == null || !mounted) {
        return;
      }

      final sms = SmsEvent.fromMap(event);
      setState(() {
        _latestSms = sms;
        _statusMessage = _isListening ? '메시지 수신 대기 중' : '최근 수신 메시지를 불러왔습니다.';
        _errorMessage = null;
      });
    } on MissingPluginException {
      // Android 네이티브 구현이 없는 플랫폼/테스트에서는 무시합니다.
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = '최근 메시지 복원 실패: $error';
      });
    }
  }

  String _permissionLabel() {
    final status = _permissionStatus;
    if (status == null) {
      return '확인 전';
    }
    if (status.isGranted) {
      return '허용됨';
    }
    if (status.isPermanentlyDenied) {
      return '영구 거부됨';
    }
    if (status.isDenied) {
      return '거부됨';
    }
    if (status.isRestricted) {
      return '제한됨';
    }
    if (status.isLimited) {
      return '부분 허용';
    }
    if (status.isProvisional) {
      return '임시 허용';
    }
    return status.toString();
  }

  String _formatDateTime(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    final second = value.second.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute:$second';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.colorScheme.inversePrimary,
        title: const Text('TextFlow SMS/MMS Listener'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                _isListening ? Icons.sms : Icons.sms_failed,
                color: _isListening
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              title: Text(_statusMessage),
              subtitle: Text('권한 상태: ${_permissionLabel()}'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '최근 수신 메시지',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (_latestSms == null)
                    const Text('아직 수신된 메시지 이벤트가 없습니다.')
                  else ...[
                    Text('유형: ${_latestSms!.messageType.toUpperCase()}'),
                    const SizedBox(height: 8),
                    Text('발신 번호: ${_latestSms!.address}'),
                    const SizedBox(height: 8),
                    Text('수신 시각: ${_formatDateTime(_latestSms!.receivedAt)}'),
                    const SizedBox(height: 8),
                    Text('본문: ${_latestSms!.body.isEmpty ? '(빈 메시지)' : _latestSms!.body}'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '테스트 방법',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('1. Android 실기기에서 앱을 실행합니다.'),
                  const Text('2. 첫 실행 시 메시지 권한을 허용합니다.'),
                  const Text('3. 다른 번호에서 이 기기로 SMS 또는 MMS를 보내면 화면이 갱신됩니다.'),
                ],
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ),
          ],
        ],
      ),
      floatingActionButton: Platform.isAndroid
          ? FloatingActionButton.extended(
              onPressed: _requestPermissionAndStartListening,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 연결'),
            )
          : null,
    );
  }
}
