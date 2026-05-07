class ForwardingFilter {
  ForwardingFilter({
    required this.id,
    required this.title,
    required this.allowSms,
    required this.allowMms,
    required this.forwardAll,
    required this.ignoreCase,
    required this.useWildcard,
    required this.senderConditions,
    required this.messageConditions,
    required this.destinations,
    required this.keepHistory,
    required this.notifyResult,
    this.enabled = true,
  });

  final int id;
  final String title;
  final bool allowSms;
  final bool allowMms;
  final bool forwardAll;
  final bool ignoreCase;
  final bool useWildcard;
  final List<String> senderConditions;
  final List<String> messageConditions;
  final List<String> destinations;
  final bool keepHistory;
  final bool notifyResult;
  bool enabled;
}

class FilterDraft {
  FilterDraft({
    required this.title,
    required this.enabled,
    required this.allowSms,
    required this.allowMms,
    required this.forwardAll,
    required this.ignoreCase,
    required this.useWildcard,
    required this.senderConditions,
    required this.messageConditions,
    required this.destinations,
    required this.keepHistory,
    required this.notifyResult,
  });

  final String title;
  final bool enabled;
  final bool allowSms;
  final bool allowMms;
  final bool forwardAll;
  final bool ignoreCase;
  final bool useWildcard;
  final List<String> senderConditions;
  final List<String> messageConditions;
  final List<String> destinations;
  final bool keepHistory;
  final bool notifyResult;
}

class FilterWizardResult {
  const FilterWizardResult.saved(FilterDraft this.draft)
      : deleted = false;

  const FilterWizardResult.deleted()
      : draft = null,
        deleted = true;

  final FilterDraft? draft;
  final bool deleted;
}

