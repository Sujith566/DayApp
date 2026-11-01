import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'journal_database.dart';

class JournalPhotos {
  static Future<Directory> directory() async {
    final root = await getApplicationDocumentsDirectory();

    return Directory(
      p.join(root.path, 'journal_photos'),
    ).create(recursive: true);
  }

  static Future<JournalPhoto> importPhoto(
      XFile source,
      ) async {
    final folder = await directory();
    final ext = p.extension(source.name).toLowerCase();

    final safeExt = [
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
    ].contains(ext)
        ? ext
        : '.jpg';

    final name =
        '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random.secure().nextInt(1 << 30)}$safeExt';

    await source.saveTo(p.join(folder.path, name));

    return JournalPhoto(name);
  }

  static Future<File> resolve(String name) async {
    if (p.basename(name) != name) {
      throw const FormatException('Invalid photo name');
    }

    return File(
      p.join((await directory()).path, name),
    );
  }

  // Android may destroy the activity while its photo picker is open.
  static Future<void> recoverPicker() async {
    final db = JournalDatabase.instance;
    final key = await db.pickerDraft();
    final lost = await ImagePicker().retrieveLostData();

    if (lost.exception != null) {
      throw lost.exception!;
    }

    if (lost.files != null && lost.files!.isNotEmpty) {
      if (key == null) {
        throw StateError(
          'Recovered photos have no draft destination',
        );
      }

      final draft = await db.draft(key);

      if (draft == null) {
        throw StateError('Photo draft is missing');
      }

      final data = Map<String, dynamic>.from(draft.data);

      final photos = List<dynamic>.from(
        data['photos'] as List? ?? [],
      );

      for (final file in lost.files!) {
        photos.add(
          (await importPhoto(file)).toJson(),
        );
      }

      data['photos'] = photos;
      await db.saveDraft(key, data);
    }

    await db.setPickerDraft(null);
  }

  // Call only while no editor or import is active.
  static Future<void> removeUnused() async {
    final db = JournalDatabase.instance;
    final active = await db.getEntries();
    final trash = await db.getEntries(trash: true);
    final drafts = await db.drafts();

    final used = <String>{
      for (final entry in [...active, ...trash])
        for (final photo in entry.photos) photo.file,
      for (final draft in drafts)
        for (final photo in draft.data['photos'] as List? ?? [])
          (photo as Map)['file'] as String,
    };

    await for (final file in (await directory()).list()) {
      if (file is File &&
          !used.contains(p.basename(file.path))) {
        await file.delete();
      }
    }
  }
}

class JournalPhotoView extends StatelessWidget {
  final JournalPhoto photo;
  final double height;
  final bool fullScreen;

  const JournalPhotoView({
    super.key,
    required this.photo,
    this.height = 160,
    this.fullScreen = false,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: JournalPhotos.resolve(photo.file),
      builder: (context, snapshot) {
        Widget image;

        if (snapshot.hasError) {
          image = const Center(
            child: Text('Photo unavailable'),
          );
        } else if (!snapshot.hasData) {
          image = const Center(
            child: CircularProgressIndicator(),
          );
        } else {
          image = Image.file(
            snapshot.data!,
            height: fullScreen ? null : height,
            width: fullScreen ? null : double.infinity,
            fit: fullScreen
                ? BoxFit.contain
                : BoxFit.cover,
            cacheWidth: fullScreen ? null : 800,
            errorBuilder: (_, _, _) {
              return const Center(
                child: Text('Photo unavailable'),
              );
            },
          );
        }

        if (fullScreen) {
          return InteractiveViewer(child: image);
        }

        return SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: image,
          ),
        );
      },
    );
  }
}

void openJournalPhoto(
    BuildContext context,
    JournalPhoto photo,
    ) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Photo')),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: JournalPhotoView(
                  photo: photo,
                  fullScreen: true,
                ),
              ),
            ),
            if (photo.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(20),
                child: Text(photo.caption),
              ),
          ],
        ),
      ),
    ),
  );
}