import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luuqapp/menu/menu_image_view.dart';

void main() {
  testWidgets('renders a cached absolute path with Image.file', (tester) async {
    Widget? rendered;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            rendered = const MenuImageView(
              fallbackIcon: Icons.local_cafe,
              fallbackColor: Colors.amber,
              assetPath: r'C:\cache\latte.png',
            ).build(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(rendered, isA<Image>());
    final image = rendered! as Image;
    expect(image.image, isA<FileImage>());
    expect((image.image as FileImage).file.path, r'C:\cache\latte.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('falls back to the icon when both image sources are missing', (
    tester,
  ) async {
    Widget? rendered;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            rendered = const MenuImageView(
              fallbackIcon: Icons.local_cafe,
              fallbackColor: Colors.amber,
            ).build(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(rendered, isA<Icon>());
    expect((rendered! as Icon).icon, Icons.local_cafe);
    expect(tester.takeException(), isNull);
  });
}
