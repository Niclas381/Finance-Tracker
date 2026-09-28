import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._internal();

  static final AuthService instance = AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // WICHTIG: Gmail-Readonly Scope hinzufügen
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: <String>[
      'email',
      'https://www.googleapis.com/auth/gmail.readonly',
    ],
  );

  String? _accessToken;
  String? _idToken;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  GoogleSignIn get googleSignIn => _googleSignIn;

  /// Letzter bekannter Gmail Access Token (wird bei signInWithGoogle gesetzt).
  /// Kann null sein, wenn der User noch keinen Google-SignIn gemacht hat.
  String? get accessToken => _accessToken;

  String? get idToken => _idToken;

  Future<UserCredential?> signInWithGoogle() async {
    // User wählt Google-Account
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) {
      // Abgebrochen
      return null;
    }

    // Token abholen
    final googleAuth = await googleUser.authentication;

    // Token lokal merken (für Gmail Calls)
    _accessToken = googleAuth.accessToken;
    _idToken = googleAuth.idToken;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // Bei Firebase anmelden
    final userCredential = await _auth.signInWithCredential(credential);
    return userCredential;
  }

  /// Optional: versucht stillen Sign-In um Token zu refreshen.
  /// Falls du es später brauchst, kannst du im Sync-Service hierauf wechseln.
  Future<String?> refreshAccessTokenSilently() async {
    final googleUser = await _googleSignIn.signInSilently();
    if (googleUser == null) return _accessToken;

    final googleAuth = await googleUser.authentication;
    _accessToken = googleAuth.accessToken;
    _idToken = googleAuth.idToken;
    return _accessToken;
  }

  Future<void> signOut() async {
    _accessToken = null;
    _idToken = null;
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}
