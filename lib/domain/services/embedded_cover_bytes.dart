/// Recovery of the real image payload from an embedded-tag picture frame.
///
/// Pure and I/O-free so it can be tested directly.
library;

import 'dart:typed_data';

/// An image payload recovered from a tag's picture frame.
class EmbeddedCover {
  const EmbeddedCover(this.bytes, this.extension);

  /// The payload, starting exactly at the format's magic bytes.
  final Uint8List bytes;

  /// File extension for the sniffed format, leading dot included.
  final String extension;
}

/// How far into the payload a signature is still believed to be the real start
/// of the image rather than something that happens to look like one inside the
/// pixel data. Leading junk comes from a mis-parsed frame description, which is
/// short in practice.
const int _maxLeadingJunk = 512;

/// The image payload in [raw], with any leading junk removed, or null when
/// [raw] holds no recognisable image.
///
/// audio_metadata_reader 1.4.2 stops scanning a picture frame's description at
/// the first single null byte. A UTF-16 description hits one halfway through
/// its first character, so the payload it hands back still has the tail of the
/// description glued to the front — `Cover` in UTF-16 leaves ten bytes before
/// the JPEG's `FF D8`. Writing that straight to disk produces a file no decoder
/// will touch, which is why a tagged song can still show no art. Sniffing the
/// signature repairs those frames and validates the rest.
EmbeddedCover? recoverEmbeddedCover(Uint8List raw) {
  if (raw.length < 4) return null;

  // Weak two-byte signature, so only trusted where the payload should start.
  if (_matches(raw, 0, const [0x42, 0x4D])) {
    return EmbeddedCover(raw, '.bmp');
  }

  final limit = raw.length < _maxLeadingJunk ? raw.length : _maxLeadingJunk;
  for (int offset = 0; offset < limit; offset++) {
    final extension = _signatureAt(raw, offset);
    if (extension == null) continue;
    return EmbeddedCover(
      offset == 0 ? raw : Uint8List.sublistView(raw, offset),
      extension,
    );
  }

  return null;
}

/// How many leading bytes of a file [hasImageSignature] needs to judge it.
const int imageSignatureProbeLength = 16;

/// Whether [head] — the first [imageSignatureProbeLength] bytes of a file —
/// starts with the magic bytes of an image format a decoder will accept.
///
/// Used to spot cover files cached before [recoverEmbeddedCover] existed, whose
/// contents start partway through a picture frame's description and so decode
/// as nothing at all.
bool hasImageSignature(Uint8List head) =>
    _signatureAt(head, 0) != null || _matches(head, 0, const [0x42, 0x4D]);

/// The extension for the image format whose signature starts at [offset], or
/// null when none does.
String? _signatureAt(Uint8List bytes, int offset) {
  if (_matches(bytes, offset, const [0xFF, 0xD8, 0xFF])) return '.jpg';
  if (_matches(
      bytes, offset, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return '.png';
  }
  if (_matches(bytes, offset, const [0x47, 0x49, 0x46, 0x38])) return '.gif';
  // RIFF....WEBP — the four size bytes in between are not part of either tag.
  if (_matches(bytes, offset, const [0x52, 0x49, 0x46, 0x46]) &&
      _matches(bytes, offset + 8, const [0x57, 0x45, 0x42, 0x50])) {
    return '.webp';
  }
  return null;
}

bool _matches(Uint8List bytes, int offset, List<int> signature) {
  if (offset < 0 || offset + signature.length > bytes.length) return false;
  for (int i = 0; i < signature.length; i++) {
    if (bytes[offset + i] != signature[i]) return false;
  }
  return true;
}
