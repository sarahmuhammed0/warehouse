/// The Flutter-side counterpart to the backend's `AppError` — every
/// repository method that can fail returns/throws one of these instead of
/// letting a raw `DioException` or parsing error reach the UI. Screens show
/// `failure.message` directly; it's already written to be user-facing
/// (architecture §31/§53 — never surface a raw stack trace or driver error).
class Failure {
  final String code;
  final String message;

  const Failure(this.code, this.message);

  factory Failure.network() =>
      const Failure('NETWORK_ERROR', 'Could not reach the server. Check your connection.');

  factory Failure.unexpected([String? detail]) =>
      Failure('UNEXPECTED_ERROR', detail ?? 'Something went wrong. Please try again.');

  @override
  String toString() => 'Failure($code: $message)';
}
