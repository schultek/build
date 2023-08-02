// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;

import 'web_entrypoint_builder.dart';

/// A builder which compiles entrypoints for the web.
///
/// Supports `dart2js` and `dartdevc`.
class WebEntrypointAppBuilder implements Builder {
  const WebEntrypointAppBuilder();

  @override
  final buildExtensions = const {
    '.dart': ['.app.dart'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    var dartEntrypointId = buildStep.inputId;
    var isAppEntrypoint = await isAppEntryPoint(dartEntrypointId, buildStep);
    if (!isAppEntrypoint) return;

    var appEntrypoingId = dartEntrypointId.changeExtension('.app.dart');

    var hasWebPlugins = await buildStep.canRead(
        AssetId(dartEntrypointId.package, 'lib/web_plugin_registrant.dart'));

    var packageConfig = await buildStep.packageConfig;
    var usesFlutterEmbed = packageConfig['jaspr_flutter_embed'] != null;

    await buildStep.writeAsString(appEntrypoingId, '''
import 'dart:ui' as ui;

import '${p.basename(dartEntrypointId.path)}' as app;
${usesFlutterEmbed ? "import 'package:jaspr_flutter_embed/jaspr_flutter_embed.dart';" : ''}
${hasWebPlugins ? "import 'package:${dartEntrypointId.package}/web_plugin_registrant.dart';" : ''}

Future<void> main() async {
  ${usesFlutterEmbed ? 'FlutterEmbedBinding.warmupFlutterEngine = ui.webOnlyWarmupEngine;' : ''}
  ${hasWebPlugins ? 'registerPlugins();' : ''}
  app.main();
}
    ''');
  }
}
