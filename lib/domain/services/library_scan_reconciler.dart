/// Pure decision for whether a fresh scan result may replace the library that
/// is currently loaded in memory.
///
/// The dangerous case this guards against: the app resumes, a transient
/// folder-access blip makes a scan yield zero songs, and that empty result
/// overwrites a perfectly good library — leaving the user staring at an empty
/// home screen asking them to re-select a folder they already configured.
///
/// Kept free of I/O so it can be unit-tested directly (see
/// test/library_scan_guard_test.dart).
///
/// Returns `false` only when replacing would wipe a non-empty library with an
/// empty, untrusted scan. In every other case the caller may adopt the scan.
bool shouldReplaceLibrary({
  required int currentCount,
  required int scannedCount,
  required bool scanTrusted,
}) {
  if (scannedCount == 0 && currentCount > 0 && !scanTrusted) {
    return false;
  }
  return true;
}
