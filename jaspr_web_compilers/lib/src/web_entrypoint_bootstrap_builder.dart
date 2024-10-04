// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;

import 'web_entrypoint_builder.dart';

const bootstrapExtension = '.bootstrap';
const bootstrapDartExtension = '$bootstrapExtension.dart';

/// A builder which bootstraps entrypoints for the web.
class WebEntrypointBootstrapBuilder implements Builder {
  const WebEntrypointBootstrapBuilder();

  @override
  final buildExtensions = const {
    '.dart': [
      bootstrapDartExtension,
    ],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    var dartEntrypointId = buildStep.inputId;
    var isAppEntrypoint = await isAppEntryPoint(dartEntrypointId, buildStep);
    if (!isAppEntrypoint) return;

    var appEntrypointId =
        dartEntrypointId.changeExtension(bootstrapDartExtension);

    var hasWebPlugins = await buildStep.canRead(
        AssetId(dartEntrypointId.package, 'lib/web_plugin_registrant.dart'));

    await buildStep.writeAsString(appEntrypointId, '''

import '${p.basename(dartEntrypointId.path)}' as app;
${hasWebPlugins ? "import 'package:${dartEntrypointId.package}/web_plugin_registrant.dart';" : ''}

Future<void> main() async {
  ${hasWebPlugins ? 'registerPlugins();' : ''}
  return app.main();
}
    ''');
  }
}
