import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../filters/models/filter_models.dart';
import '../../filters/presentation/filter_create_wizard_page.dart';
import '../models/sms_event.dart';

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
  String _statusMessage = '초기화 중...';
  String? _errorMessage;
  bool _isListening = false;
  int _nextFilterId = 1;
  final List<ForwardingFilter> _filters = [];

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

        SmsEvent.fromMap(event);
        if (!mounted) {
          return;
        }

        setState(() {
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

      SmsEvent.fromMap(event);
      setState(() {
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

  Future<void> _addFilter() async {
    final draft = await Navigator.of(context).push<FilterDraft>(
      MaterialPageRoute(
        builder: (_) => FilterCreateWizardPage(nextIndex: _nextFilterId),
      ),
    );
    if (draft == null || !mounted) {
      return;
    }

    final filter = ForwardingFilter(
      id: _nextFilterId++,
      title: draft.title,
      allowSms: draft.allowSms,
      allowMms: draft.allowMms,
      forwardAll: draft.forwardAll,
      ignoreCase: draft.ignoreCase,
      useWildcard: draft.useWildcard,
      senderConditions: draft.senderConditions,
      messageConditions: draft.messageConditions,
      destinations: draft.destinations,
      keepHistory: draft.keepHistory,
      notifyResult: draft.notifyResult,
      enabled: draft.enabled,
    );
    setState(() {
      _filters.add(filter);
    });
  }

  String _messageTypeLabel(ForwardingFilter filter) {
    if (filter.allowSms && filter.allowMms) {
      return 'SMS/MMS';
    }
    if (filter.allowSms) {
      return 'SMS';
    }
    return 'MMS';
  }

  String _conditionLabel(ForwardingFilter filter) {
    if (filter.forwardAll) {
      return '모두 전달';
    }
    final total = filter.senderConditions.length + filter.messageConditions.length;
    return '조건 $total개';
  }

  void _toggleFilter(ForwardingFilter filter, bool value) {
    setState(() {
      filter.enabled = value;
    });
  }

  Widget _buildFilterIcon() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEF8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.message_outlined, color: Color(0xFF3D7CCC), size: 30),
    );
  }

  Widget _buildFilterItem(BuildContext context, ForwardingFilter filter) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1016),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Row(
        children: [
          _buildFilterIcon(),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  filter.title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_messageTypeLabel(filter)} · ${_conditionLabel(filter)} · 대상 ${filter.destinations.length}개',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          Switch(
            value: filter.enabled,
            onChanged: (value) => _toggleFilter(filter, value),
            activeThumbColor: const Color(0xFFFFA000),
            activeTrackColor: const Color(0xFF5A3B00),
            inactiveThumbColor: Colors.grey.shade500,
            inactiveTrackColor: Colors.grey.shade800,
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '아직 생성된 필터가 없습니다.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '하단 + 버튼으로 필터 추가 단계를 시작하세요.',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _addFilter,
              icon: const Icon(Icons.add),
              label: const Text('필터 추가'),
            ),
          ],
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Expanded(
              child: _filters.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: _filters.length,
                      itemBuilder: (context, index) => _buildFilterItem(context, _filters[index]),
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                    ),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '상태: $_statusMessage · 권한: ${_permissionLabel()}',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () => unawaited(_addFilter()),
        backgroundColor: const Color(0xFFFFA000),
        foregroundColor: Colors.black,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 36),
      ),
    );
  }
}

