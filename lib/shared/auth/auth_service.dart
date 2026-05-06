import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._internal();

  static final AuthService instance = AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

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

  /// Letzter bekannter Gmail Access Token (wird bei signInWithGoogle gesetzt).
  String? get accessToken => _accessToken;

  String? get idToken => _idToken;

  Future<UserCredential?> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return null;
      }

      final googleAuth = await googleUser.authentication;
      _accessToken = googleAuth.accessToken;
      _idToken = googleAuth.idToken;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      return await _auth.signInWithCredential(credential);
    } catch (e) {
      return null;
    }
  }

  Future<void> signOut() async {
    _accessToken = null;
    _idToken = null;
    await _auth.signOut();
    await _googleSignIn.signOut();
  }

  Future<String?> refreshAccessTokenSilently() async {
    try {
      final googleUser = await _googleSignIn.signInSilently();
      if (googleUser == null) return null;

      final googleAuth = await googleUser.authentication;
      _accessToken = googleAuth.accessToken;
      _idToken = googleAuth.idToken;
      return _accessToken;
    } catch (e) {
      return null;
    }
  }
}
