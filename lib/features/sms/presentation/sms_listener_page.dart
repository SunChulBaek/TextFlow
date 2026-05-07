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
  static const MethodChannel _filterConfig = MethodChannel('textflow/filter_config');

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
    unawaited(_loadFiltersFromNative());
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
    final result = await Navigator.of(context).push<FilterWizardResult>(
      MaterialPageRoute(
        builder: (_) => FilterCreateWizardPage(nextIndex: _nextFilterId),
      ),
    );
    final draft = result?.draft;
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
    await _syncFiltersToNative();
  }

  FilterDraft _toDraft(ForwardingFilter filter) {
    return FilterDraft(
      title: filter.title,
      enabled: filter.enabled,
      allowSms: filter.allowSms,
      allowMms: filter.allowMms,
      forwardAll: filter.forwardAll,
      ignoreCase: filter.ignoreCase,
      useWildcard: filter.useWildcard,
      senderConditions: List<String>.from(filter.senderConditions),
      messageConditions: List<String>.from(filter.messageConditions),
      destinations: List<String>.from(filter.destinations),
      keepHistory: filter.keepHistory,
      notifyResult: filter.notifyResult,
    );
  }

  Future<void> _editFilter(int index) async {
    final current = _filters[index];
    final result = await Navigator.of(context).push<FilterWizardResult>(
      MaterialPageRoute(
        builder: (_) => FilterCreateWizardPage(
          nextIndex: current.id,
          initialDraft: _toDraft(current),
        ),
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    if (result.deleted) {
      setState(() {
        _filters.removeAt(index);
      });
      await _syncFiltersToNative();
      return;
    }

    final draft = result.draft;
    if (draft == null) {
      return;
    }

    setState(() {
      _filters[index] = ForwardingFilter(
        id: current.id,
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
    });
    await _syncFiltersToNative();
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
    unawaited(_syncFiltersToNative());
  }

  bool _asBool(Object? value, {required bool fallback}) {
    if (value is bool) {
      return value;
    }
    return fallback;
  }

  List<String> _asStringList(Object? value) {
    if (value is! List) {
      return const [];
    }

    return value
        .map((item) => item?.toString().trim() ?? '')
        .where((item) => item.isNotEmpty)
        .toList();
  }

  ForwardingFilter? _fromNativeFilterMap(Map<Object?, Object?> map, int id) {
    final title = (map['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) {
      return null;
    }

    return ForwardingFilter(
      id: id,
      title: title,
      allowSms: _asBool(map['allowSms'], fallback: true),
      allowMms: _asBool(map['allowMms'], fallback: true),
      forwardAll: _asBool(map['forwardAll'], fallback: true),
      ignoreCase: _asBool(map['ignoreCase'], fallback: true),
      useWildcard: _asBool(map['useWildcard'], fallback: false),
      senderConditions: _asStringList(map['senderConditions']),
      messageConditions: _asStringList(map['messageConditions']),
      destinations: _asStringList(map['destinations']),
      keepHistory: true,
      notifyResult: true,
      enabled: _asBool(map['enabled'], fallback: true),
    );
  }

  Future<void> _loadFiltersFromNative() async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      final rawFilters = await _filterConfig.invokeListMethod<Object?>('getFilters') ?? const [];
      final restoredFilters = <ForwardingFilter>[];
      var nextId = 1;

      for (final raw in rawFilters) {
        if (raw is! Map<Object?, Object?>) {
          continue;
        }

        final restored = _fromNativeFilterMap(raw, nextId);
        if (restored == null) {
          continue;
        }

        restoredFilters.add(restored);
        nextId += 1;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _filters
          ..clear()
          ..addAll(restoredFilters);
        _nextFilterId = nextId;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = '필터 복원 실패: $error';
      });
    }
  }

  Map<String, Object?> _toNativeFilterMap(ForwardingFilter filter) {
    return {
      'title': filter.title,
      'enabled': filter.enabled,
      'allowSms': filter.allowSms,
      'allowMms': filter.allowMms,
      'forwardAll': filter.forwardAll,
      'ignoreCase': filter.ignoreCase,
      'useWildcard': filter.useWildcard,
      'senderConditions': List<String>.from(filter.senderConditions),
      'messageConditions': List<String>.from(filter.messageConditions),
      'destinations': List<String>.from(filter.destinations),
    };
  }

  Future<void> _syncFiltersToNative() async {
    if (!Platform.isAndroid) {
      return;
    }

    final serializedFilters = _filters.map(_toNativeFilterMap).toList();

    try {
      await _filterConfig.invokeMethod('setFilters', serializedFilters);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = '필터 동기화 실패: $error';
      });
    }
  }

  Widget _buildFilterIcon(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.message_outlined, color: scheme.onPrimaryContainer, size: 30),
    );
  }

  Widget _buildFilterItem(BuildContext context, ForwardingFilter filter, int index) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => unawaited(_editFilter(index)),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              _buildFilterIcon(context),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      filter.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_messageTypeLabel(filter)} · ${_conditionLabel(filter)} · 대상 ${filter.destinations.length}개',
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Switch(
                value: filter.enabled,
                onChanged: (value) => _toggleFilter(filter, value),
              ),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () => unawaited(_editFilter(index)),
                splashRadius: 18,
              ),
            ],
          ),
        ),
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
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '하단 + 버튼으로 필터 추가 단계를 시작하세요.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
                      itemBuilder: (context, index) => _buildFilterItem(
                        context,
                        _filters[index],
                        index,
                      ),
                      separatorBuilder: (_, index) => const SizedBox(height: 14),
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        onPressed: () => unawaited(_addFilter()),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        shape: const CircleBorder(),
        child: const Icon(Icons.add, size: 36),
      ),
    );
  }
}

