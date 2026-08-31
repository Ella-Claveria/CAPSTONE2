import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:image_picker/image_picker.dart';

class CloudinaryService {
  final _cloudinary =
      CloudinaryPublic('gxir71bo', 'agritrade_unsigned', cache: false);

  Future<String?> uploadImage(
    XFile file, {
    String folder = 'agritrade/listings',
  }) async {
    try {
      final res = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          file.path,
          resourceType: CloudinaryResourceType.Image,
          folder: folder,
        ),
      );
      return res.secureUrl;
    } catch (e) {
      return null;
    }
  }
}