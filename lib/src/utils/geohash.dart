/// Minimal Geohash encoder (base32) for latitude/longitude.
/// Adapted for project use; no dependencies.
const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

String encodeGeohash(double latitude, double longitude, {int precision = 10}) {
  var latMin = -90.0, latMax = 90.0;
  var lonMin = -180.0, lonMax = 180.0;
  var bits = [16, 8, 4, 2, 1];
  var bit = 0;
  var ch = 0;
  var even = true;
  final buffer = StringBuffer();

  while (buffer.length < precision) {
    if (even) {
      final mid = (lonMin + lonMax) / 2;
      if (longitude > mid) {
        ch |= bits[bit];
        lonMin = mid;
      } else {
        lonMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (latitude > mid) {
        ch |= bits[bit];
        latMin = mid;
      } else {
        latMax = mid;
      }
    }
    even = !even;
    if (bit < 4) {
      bit++;
    } else {
      buffer.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return buffer.toString();
}
