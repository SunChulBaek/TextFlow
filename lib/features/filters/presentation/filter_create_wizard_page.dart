import 'package:flutter/material.dart';

import '../../../shared/widgets/simple_input_dialog.dart';
import '../models/filter_models.dart';

class FilterCreateWizardPage extends StatefulWidget {
  const FilterCreateWizardPage({
    super.key,
    required this.nextIndex,
  });

  final int nextIndex;

  @override
  State<FilterCreateWizardPage> createState() => _FilterCreateWizardPageState();
}

class _FilterCreateWizardPageState extends State<FilterCreateWizardPage> {
  late final TextEditingController _nameController;

  int _step = 0;
  bool _allowSms = true;
  bool _allowMms = true;
  bool _forwardAll = true;
  bool _ignoreCase = true;
  bool _useWildcard = false;
  bool _enabled = true;
  bool _keepHistory = true;
  bool _notifyResult = true;
  final List<String> _senderConditions = [];
  final List<String> _messageConditions = [];
  final List<String> _destinations = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: '필터 ${widget.nextIndex}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _stepTitle() {
    return switch (_step) {
      0 => '전달 조건 1/4',
      1 => '포워딩 대상 2/4',
      2 => '필터 설정 3/4',
      _ => '요약 4/4',
    };
  }

  String _messageTypeLabel() {
    if (_allowSms && _allowMms) {
      return 'SMS/MMS';
    }
    if (_allowSms) {
      return 'SMS';
    }
    return 'MMS';
  }

  Future<void> _addItemTo(List<String> target, String title, String hint) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => SimpleInputDialog(title: title, hint: hint),
    );
    if (value == null || value.trim().isEmpty || !mounted) {
      return;
    }
    setState(() {
      target.add(value.trim());
    });
  }

  void _showValidation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  bool _validateStep() {
    if (_step == 0) {
      if (!_allowSms && !_allowMms) {
        _showValidation('SMS 또는 MMS 중 하나 이상 선택해 주세요.');
        return false;
      }
      if (!_forwardAll && _senderConditions.isEmpty && _messageConditions.isEmpty) {
        _showValidation('조건 확인 모드에서는 최소 1개 조건이 필요합니다.');
        return false;
      }
    }
    if (_step == 1 && _destinations.isEmpty) {
      _showValidation('포워딩 대상을 1개 이상 추가해 주세요.');
      return false;
    }
    if (_step == 2 && _nameController.text.trim().isEmpty) {
      _showValidation('필터 이름을 입력해 주세요.');
      return false;
    }
    return true;
  }

  void _nextOrSubmit() {
    if (!_validateStep()) {
      return;
    }
    if (_step < 3) {
      setState(() {
        _step += 1;
      });
      return;
    }

    Navigator.of(context).pop(
      FilterDraft(
        title: _nameController.text.trim(),
        enabled: _enabled,
        allowSms: _allowSms,
        allowMms: _allowMms,
        forwardAll: _forwardAll,
        ignoreCase: _ignoreCase,
        useWildcard: _useWildcard,
        senderConditions: List<String>.from(_senderConditions),
        messageConditions: List<String>.from(_messageConditions),
        destinations: List<String>.from(_destinations),
        keepHistory: _keepHistory,
        notifyResult: _notifyResult,
      ),
    );
  }

  Widget _buildConditionStep(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('수신 메시지 유형', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _allowSms,
          onChanged: (value) => setState(() => _allowSms = value ?? false),
          title: const Text('SMS'),
          contentPadding: EdgeInsets.zero,
        ),
        CheckboxListTile(
          value: _allowMms,
          onChanged: (value) => setState(() => _allowMms = value ?? false),
          title: const Text('MMS'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(value: true, label: Text('모두 전달하기')),
            ButtonSegment<bool>(value: false, label: Text('조건 확인 후 전달하기')),
          ],
          selected: {_forwardAll},
          onSelectionChanged: (selected) {
            setState(() {
              _forwardAll = selected.first;
            });
          },
        ),
        if (!_forwardAll) ...[
          const SizedBox(height: 8),
          SwitchListTile(
            value: _ignoreCase,
            onChanged: (value) => setState(() => _ignoreCase = value),
            title: const Text('조건 확인시 영어 대소문자 무시하기'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _useWildcard,
            onChanged: (value) => setState(() => _useWildcard = value),
            title: const Text('와일드카드(*) 사용하기'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          Text('전화번호 조건', style: theme.textTheme.titleMedium),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _senderConditions
                .map(
                  (item) => InputChip(
                    label: Text(item),
                    onDeleted: () => setState(() => _senderConditions.remove(item)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _addItemTo(_senderConditions, '전화번호 조건 추가', '예: 1588*'),
            icon: const Icon(Icons.add),
            label: const Text('추가'),
          ),
          const SizedBox(height: 12),
          Text('메시지 내용 조건', style: theme.textTheme.titleMedium),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _messageConditions
                .map(
                  (item) => InputChip(
                    label: Text(item),
                    onDeleted: () => setState(() => _messageConditions.remove(item)),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _addItemTo(_messageConditions, '메시지 조건 추가', '예: 승인'),
            icon: const Icon(Icons.add),
            label: const Text('추가'),
          ),
        ],
      ],
    );
  }

  Widget _buildDestinationStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('어디로 전달할까요?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text('이 폰으로부터 메시지를 받을 전화번호, 이메일, URL 등을 입력해 주세요.'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _destinations
              .map(
                (item) => InputChip(
                  label: Text(item),
                  onDeleted: () => setState(() => _destinations.remove(item)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => _addItemTo(_destinations, '포워딩 대상 추가', '전화번호, 이메일, URL'),
          icon: const Icon(Icons.add),
          label: const Text('추가'),
        ),
      ],
    );
  }

  Widget _buildNameAndOptionStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('필터 이름', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '예: 우리카드 승인 알림',
          ),
        ),
        const SizedBox(height: 18),
        SwitchListTile(
          value: _keepHistory,
          onChanged: (value) => setState(() => _keepHistory = value),
          title: const Text('전송 기록 남기기'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _notifyResult,
          onChanged: (value) => setState(() => _notifyResult = value),
          title: const Text('전송 결과 알림'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _enabled,
          onChanged: (value) => setState(() => _enabled = value),
          title: const Text('생성 후 바로 활성화'),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildSummaryStep(BuildContext context) {
    final theme = Theme.of(context);
    final conditionText = _forwardAll
        ? '모두 전달하기'
        : '전화번호 ${_senderConditions.length}개 / 메시지 ${_messageConditions.length}개';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Text('요약', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('필터 이름', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(_nameController.text.trim().isEmpty ? '(미입력)' : _nameController.text.trim()),
                const Divider(height: 24),
                Text('수신 유형: ${_messageTypeLabel()}'),
                const SizedBox(height: 4),
                Text('전달 조건: $conditionText'),
                const SizedBox(height: 4),
                Text('포워딩 대상 ${_destinations.length}개'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('옵션', style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text('전송 기록 남기기: ${_keepHistory ? '켜짐' : '꺼짐'}'),
                Text('전송 결과 알림: ${_notifyResult ? '켜짐' : '꺼짐'}'),
                Text('필터 활성화: ${_enabled ? '켜짐' : '꺼짐'}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _currentStepView(BuildContext context) {
    return switch (_step) {
      0 => _buildConditionStep(context),
      1 => _buildDestinationStep(context),
      2 => _buildNameAndOptionStep(context),
      _ => _buildSummaryStep(context),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_stepTitle())),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: _currentStepView(context),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        if (_step == 0) {
                          Navigator.of(context).pop();
                        } else {
                          setState(() {
                            _step -= 1;
                          });
                        }
                      },
                      child: Text(_step == 0 ? '닫기' : '이전'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: _nextOrSubmit,
                      child: Text(_step == 3 ? '완료' : '다음'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

