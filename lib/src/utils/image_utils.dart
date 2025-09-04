import 'dart:typed_data';
import 'package:image/image.dart' as img;

class ImageUtils {
  static Uint8List compressJpeg(Uint8List input, {int maxWidth = 1600, int maxHeight = 1600, int quality = 80}) {
    final decoded = img.decodeImage(input);
    if (decoded == null) return input;
    final resized = img.copyResize(decoded, width: maxWidth, height: maxHeight, interpolation: img.Interpolation.cubic, maintainAspect: true);
    final out = img.encodeJpg(resized, quality: quality);
    return Uint8List.fromList(out);
  }
}
