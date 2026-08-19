// Plan/30 — ImagePickerService pick + iterative size-ceiling logic, via the
// ImagePickerBackend seam (no plugins / device).

import 'dart:typed_data';

import 'package:app/data/images/image_picker_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBackend implements ImagePickerBackend {
  String? path = '/tmp/pic.jpg'; // null → user cancelled
  bool denied = false;

  /// Bytes returned per compress pass, in order. The last value repeats.
  List<int> sizes = [200 * 1024];
  final List<({int side, int quality})> calls = [];
  ImageSourceKind? pickedSource;

  Uint8List? clipboardBytes = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  ]);

  @override
  Future<String?> pick(ImageSourceKind source) async {
    pickedSource = source;
    if (denied) throw const ImagePermissionDeniedException();
    return path;
  }

  @override
  Future<Uint8List> compress(
    String path, {
    required int maxSide,
    required int quality,
  }) async {
    calls.add((side: maxSide, quality: quality));
    final idx = calls.length - 1;
    final n = idx < sizes.length ? sizes[idx] : sizes.last;
    return Uint8List(n);
  }

  @override
  Future<Uint8List?> pasteFromClipboard() async => clipboardBytes;

  @override
  Future<Uint8List> compressBytes(
    Uint8List bytes, {
    required int maxSide,
    required int quality,
  }) async {
    calls.add((side: maxSide, quality: quality));
    final idx = calls.length - 1;
    final n = idx < sizes.length ? sizes[idx] : sizes.last;
    return Uint8List(n);
  }
}

void main() {
  test('gallery pick under the ceiling compresses once', () async {
    final backend = _FakeBackend()..sizes = [180 * 1024];
    final svc = ImagePickerService(backend);

    final result = await svc.pickFromGallery();
    expect(result, isNotNull);
    expect(result!.mime, 'image/jpeg');
    expect(result.bytes.length, 180 * 1024);
    expect(backend.pickedSource, ImageSourceKind.gallery);
    expect(backend.calls, hasLength(1));
    expect(backend.calls.first.side, 1568);
    expect(backend.calls.first.quality, 80);
  });

  test('oversized result re-compresses with smaller side + quality', () async {
    final backend = _FakeBackend()
      // First two passes blow the 1.5MB ceiling, the third lands under.
      ..sizes = [2000 * 1024, 1700 * 1024, 300 * 1024];
    final svc = ImagePickerService(backend);

    final result = await svc.pickFromCamera();
    expect(result!.bytes.length, 300 * 1024);
    expect(backend.calls.length, 3);
    // Side + quality shrink monotonically across passes.
    expect(backend.calls[1].side, lessThan(backend.calls[0].side));
    expect(backend.calls[1].quality, lessThan(backend.calls[0].quality));
    expect(backend.calls[2].side, lessThan(backend.calls[1].side));
  });

  test('cancelled pick returns null and never compresses', () async {
    final backend = _FakeBackend()..path = null;
    final svc = ImagePickerService(backend);
    expect(await svc.pickFromGallery(), isNull);
    expect(backend.calls, isEmpty);
  });

  test('denied camera permission propagates as a typed exception', () async {
    final backend = _FakeBackend()..denied = true;
    final svc = ImagePickerService(backend);
    expect(
      () => svc.pickFromCamera(),
      throwsA(isA<ImagePermissionDeniedException>()),
    );
  });

  test('pasteFromClipboard compresses and returns PickedImage', () async {
    final backend = _FakeBackend()..sizes = [150 * 1024];
    final svc = ImagePickerService(backend);
    final result = await svc.pasteFromClipboard();
    expect(result, isNotNull);
    expect(result!.mime, 'image/jpeg');
    expect(result.bytes.length, 150 * 1024);
  });

  test('pasteFromClipboard returns null when clipboard is empty', () async {
    final backend = _FakeBackend()..clipboardBytes = null;
    final svc = ImagePickerService(backend);
    final result = await svc.pasteFromClipboard();
    expect(result, isNull);
  });
}
