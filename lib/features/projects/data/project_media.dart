import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class ProjectMedia {
  static const maxBytes = 10 * 1024 * 1024;
  static Future<List<PlatformFile>> pickPhotos() => FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  );
  static Future<PlatformFile?> pickDocument() => FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
  );
  static Future<String> upload(String projectId, PlatformFile file) async {
    final size = await file.length();
    if (size == null || size <= 0 || size > maxBytes) {
      throw StateError('Choose a file under 10 MB.');
    }
    final extension = file.name.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'jpg' || 'jpeg' => 'image/jpeg',
      _ => throw StateError('Choose a PDF, JPG, PNG or WebP file.'),
    };
    final path =
        'projects/$projectId/${DateTime.now().microsecondsSinceEpoch}-${file.name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')}';
    final bytes = await file.readAsBytes();
    if (bytes.length > maxBytes) throw StateError('Choose a file under 10 MB.');
    await FirebaseStorage.instance
        .ref(path)
        .putData(bytes, SettableMetadata(contentType: mime));
    return path;
  }

  static Future<void> open(String path) async {
    final url = path.startsWith('projects/')
        ? await FirebaseStorage.instance.ref(path).getDownloadURL()
        : path;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || !await launchUrl(uri)) {
      throw StateError('Could not open the file.');
    }
  }
}

/// Storage bytes are read with the signed-in user's permissions. Permanent
/// public download tokens are never stored in project records.
class ProjectPhoto extends StatefulWidget {
  const ProjectPhoto({super.key, required this.path});
  final String path;
  @override
  State<ProjectPhoto> createState() => _ProjectPhotoState();
}

class _ProjectPhotoState extends State<ProjectPhoto> {
  Future<Uint8List?>? _bytes;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProjectPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _load();
  }

  void _load() {
    _bytes = widget.path.startsWith('projects/')
        ? FirebaseStorage.instance
              .ref(widget.path)
              .getData(ProjectMedia.maxBytes)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    Widget failure() => const Center(child: Icon(Icons.broken_image_outlined));
    if (_bytes == null) {
      return Image.network(
        widget.path,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => failure(),
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) return failure();
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => failure(),
        );
      },
    );
  }
}
