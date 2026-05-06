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

