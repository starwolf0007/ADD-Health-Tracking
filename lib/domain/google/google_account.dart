// lib/domain/google/google_account.dart

class GoogleAccount {
  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  const GoogleAccount({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });
}
