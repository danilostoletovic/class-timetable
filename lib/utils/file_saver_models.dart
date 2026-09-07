class SaveFileResult {
  final bool success;
  final String message;
  final bool cancelled;

  const SaveFileResult({
    required this.success,
    required this.message,
    this.cancelled = false,
  });
}
