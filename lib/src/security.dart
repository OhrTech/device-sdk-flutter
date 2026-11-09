import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'core.dart';
import 'messages.g.dart' as g;

/// The suite of a device attestation: [ec] (P-256), or [ecMlDsa65], post-quantum (both keys attested,
/// everything signed with both).
enum OhrAttestationSuite {
  ec('ec'),
  ecMlDsa65('ec-mldsa65');

  const OhrAttestationSuite(this.wire);
  final String wire;
}

/// The attested key(s): [ec] and, for [OhrAttestationSuite.ecMlDsa65], [mlDsa65], each a certificate
/// chain (DER) from the key's certificate to the OhrTech root. Send [json] to your server with the challenge.
class OhrAttestationResult {
  OhrAttestationResult._(g.AttestationInfo a)
      : suite = OhrAttestationSuite.values.firstWhere((s) => s.wire == a.suite),
        ec = List.unmodifiable(a.ec),
        mlDsa65 = a.mlDsa65 == null ? null : List.unmodifiable(a.mlDsa65!),
        json = (jsonDecode(a.json) as Map).cast<String, Object?>();
  final OhrAttestationSuite suite;
  final List<Uint8List> ec;
  final List<Uint8List>? mlDsa65;

  /// The chains as base64 DER, as `POST /v1/attestations/verify` takes them.
  final Map<String, Object?> json;
}

/// Device attestation: proof, for the app's server, that a request comes from this app, unmodified, on
/// a specific, genuine and secure OhrTech device. [attest] once (the server checks the chain and keeps
/// the key), then a [token] with each request.
abstract final class OhrAttestation {
  /// A new attested key (or keys) bound to [challenge] (your server's nonce, 1 to 128 bytes), replacing
  /// the one before. Takes a moment: the TEE makes and certifies the key.
  static Future<OhrAttestationResult> attest(Uint8List challenge, {OhrAttestationSuite suite = OhrAttestationSuite.ec}) async =>
      OhrAttestationResult._(await call((a) => a.attestationAttest(challenge, suite.wire)));

  /// A short-lived proof for one request, signed by the attested key(s): `header.payload.ecSignature[.mlDsa65Signature]`.
  static Future<String> token(String audience, {Duration ttl = const Duration(minutes: 5), String? nonce}) =>
      call((a) => a.attestationToken(audience, ttl.inSeconds, nonce));

  /// The suite of the current attested key, or null before [attest].
  static Future<OhrAttestationSuite?> suite() async {
    final s = await call((a) => a.attestationSuite());
    return s == null ? null : OhrAttestationSuite.values.firstWhere((x) => x.wire == s);
  }
}

/// A client certificate: [alias] as the app names it; [imported] from the fleet's PKCS#12. A device-made
/// certificate has two [paths] (DER, leaf first): through the organisation's client root and through the
/// OhrTech Device Identity Root.
class OhrCertificate {
  OhrCertificate._(g.CertificateInfo c)
      : alias = c.alias,
        paths = [for (final p in c.paths) List<Uint8List>.unmodifiable(p.certificates)],
        imported = c.imported;
  final String alias;
  final List<List<Uint8List>> paths;
  final bool imported;
  List<Uint8List> get chain => paths.first;
  Uint8List get certificate => paths.first.first;
}

/// The app's client certificates and trusted CAs (Agent 1061+). The keys live in the device's Android
/// Keystore, which Dart's own TLS can't use: make requests with [client], which goes through Android's.
abstract final class OhrCertificates {
  /// Whether the fleet gives this app an issuing CA, so [request] can work.
  static Future<bool> canRequest() => call((a) => a.certificatesCanRequest());

  /// A new key and certificate under [alias] (1 to 64 of A-Z a-z 0-9 . _ -), replacing the one before.
  /// The key is made in the TEE and attested; the hub certifies it only if the attestation holds.
  static Future<OhrCertificate> request(String alias, {Duration timeout = const Duration(seconds: 60)}) async =>
      OhrCertificate._(await call((a) => a.certificatesRequest(alias, timeout.inMilliseconds)));

  /// A new key and certificate for [alias] when less than a third of its lifetime is left; null when not due.
  static Future<OhrCertificate?> renewIfDue(String alias) async {
    final c = await call((a) => a.certificatesRenewIfDue(alias));
    return c == null ? null : OhrCertificate._(c);
  }

  /// The app's client certificates: device-made and imported.
  static Future<List<OhrCertificate>> list() async => [for (final c in await call((a) => a.certificatesList())) OhrCertificate._(c)];

  /// An HTTP client (package:http) presenting [alias]'s certificate (or, null, any of the app's) to servers
  /// that ask for one, and trusting the system's CAs and the private CAs the fleet gives the app.
  static http.Client client({String? alias, Duration timeout = const Duration(seconds: 30)}) => _OhrHttpClient(alias, timeout);

  /// The fleet changed the app's certificates (issuing CA, trusted CAs, imported bundles).
  static final Stream<void> changes = shared(g.certificates, (g.CertificatesChangedInfo _) {});
}

/// package:http over Android's HTTP stack with the app's certificates. Bodies are sent and read whole.
class _OhrHttpClient extends http.BaseClient {
  _OhrHttpClient(this.alias, this.timeout);
  final String? alias;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = await request.finalize().toBytes();
    final r = await call((a) => a.httpSend(g.HttpRequestData(
          method: request.method,
          url: request.url.toString(),
          headers: request.headers,
          body: body.isEmpty ? null : body,
          alias: alias,
          timeoutMs: timeout.inMilliseconds,
          followRedirects: request.followRedirects,
        )));
    return http.StreamedResponse(
      Stream.value(r.body),
      r.status,
      contentLength: r.body.length,
      request: request,
      headers: r.headers,
      reasonPhrase: r.reason,
      isRedirect: r.status >= 300 && r.status < 400,
    );
  }
}

/// A KEM algorithm of [OhrKeys].
enum OhrKeyAlgorithm {
  mlKem768('ML-KEM-768'),
  mlKem1024('ML-KEM-1024'),
  xWing('X-Wing'),

  /// HPKE DHKEM(X25519) only: [OhrKeys.hpkeOpen]; there is no raw encapsulate or decapsulate.
  x25519('X25519');

  const OhrKeyAlgorithm(this.standardName);
  final String standardName;

  static OhrKeyAlgorithm named(String name) => values.firstWhere((a) => a.standardName.toLowerCase() == name.toLowerCase());
}

class OhrKeyInfo {
  OhrKeyInfo._(g.KeyInfoData k)
      : alias = k.alias,
        algorithm = OhrKeyAlgorithm.named(k.algorithm),
        createdAt = DateTime.fromMillisecondsSinceEpoch(k.createdAtMs);
  final String alias;
  final OhrKeyAlgorithm algorithm;
  final DateTime createdAt;
}

/// An encapsulation: [ciphertext] to send, [sharedSecret] (32 bytes) to keep.
class OhrEncapsulated {
  OhrEncapsulated._(g.EncapsulatedData e)
      : ciphertext = e.ciphertext,
        sharedSecret = e.sharedSecret;
  final Uint8List ciphertext;
  final Uint8List sharedSecret;
}

/// Proof that [publicKey] was made in this device's TEE for this app: send all of it, with the challenge,
/// to `POST /v1/devices/{deviceId}/key-attestations/verify` (base64 fields).
class OhrKeyAttestation {
  OhrKeyAttestation._(g.KeyAttestationData k)
      : algorithm = OhrKeyAlgorithm.named(k.algorithm),
        publicKey = k.publicKey,
        owner = k.owner,
        coseSign1 = k.coseSign1,
        diceChain = k.diceChain;
  final OhrKeyAlgorithm algorithm;
  final Uint8List publicKey;

  /// How the TEE names this app (`app:<the Agent's UUID for the app>:<package>`), as signed.
  final String owner;
  final Uint8List coseSign1;
  final Uint8List diceChain;
}

/// HPKE (RFC 9180) identifiers for [OhrKeys.hpkeOpen].
abstract final class OhrHpke {
  static const kdfHkdfSha256 = 1;
  static const aeadAes128Gcm = 1;
  static const aeadAes256Gcm = 2;
  static const aeadChaCha20Poly1305 = 3;
}

/// Post-quantum and classical KEM keys whose private halves never leave the device's TEE: ML-KEM-768,
/// ML-KEM-1024, X-Wing, and X25519 for HPKE. Each app has its own keys, by alias.
abstract final class OhrKeys {
  /// Whether this device's OS has the OhrTech KEM app.
  static Future<bool> isAvailable() => call((a) => a.keysIsAvailable());

  /// A new key under [alias] (1-64 of A-Z a-z 0-9 . _ -, not starting "ohr."), replacing any key of that
  /// alias. Returns its public key. At most 32 keys per app.
  static Future<Uint8List> generate(String alias, OhrKeyAlgorithm algorithm) => call((a) => a.keysGenerate(alias, algorithm.standardName));
  static Future<List<OhrKeyInfo>> list() async => [for (final k in await call((a) => a.keysList())) OhrKeyInfo._(k)];

  /// The public key, or null if there's no such key.
  static Future<Uint8List?> publicKey(String alias) => call((a) => a.keysPublicKey(alias));
  static Future<void> delete(String alias) => call((a) => a.keysDelete(alias));

  /// The 32-byte shared secret of [ciphertext] (ML-KEM and X-Wing keys).
  static Future<Uint8List> decapsulate(String alias, Uint8List ciphertext) => call((a) => a.keysDecapsulate(alias, ciphertext));

  /// Encapsulates to anyone's public key of [algorithm] (ML-KEM, X-Wing); needs no key of yours.
  static Future<OhrEncapsulated> encapsulate(OhrKeyAlgorithm algorithm, Uint8List publicKey) async =>
      OhrEncapsulated._(await call((a) => a.keysEncapsulate(algorithm.standardName, publicKey)));

  /// HPKE base mode, one message, with the key's own KEM. Plaintext at most 8,192 bytes. [OhrFailed]
  /// ("does not open") if it isn't for this key.
  static Future<Uint8List> hpkeOpen(String alias, Uint8List enc, Uint8List ciphertext,
          {int kdf = OhrHpke.kdfHkdfSha256, int aead = OhrHpke.aeadAes128Gcm, Uint8List? info, Uint8List? aad}) =>
      call((a) => a.keysHpkeOpen(alias, kdf, aead, enc, info ?? Uint8List(0), aad ?? Uint8List(0), ciphertext));

  /// Proof the key is this app's, in this device's TEE, bound to [challenge] (at most 128 bytes).
  static Future<OhrKeyAttestation> attest(String alias, Uint8List challenge) async =>
      OhrKeyAttestation._(await call((a) => a.keysAttest(alias, challenge)));
}
