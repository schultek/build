// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:path/path.dart' as p;

const ddcBootstrapExtension = '.dart.bootstrap.js';
const jsEntrypointExtension = '.dart.js';
const jsEntrypointSourceMapExtension = '.dart.js.map';
const jsEntrypointArchiveExtension = '.dart.js.tar.gz';
const digestsEntrypointExtension = '.digests';
const mergedMetadataExtension = '.dart.ddc_merged_metadata';

/// Which compiler to use when compiling web entrypoints.
enum WebCompiler {
  // ignore: constant_identifier_names
  Dart2Js,
  // ignore: constant_identifier_names
  DartDevc,
}

/// The top level keys supported for the `options` config for the
/// [WebEntrypointBuilder].
const _supportedOptions = [
  _compilerOption,
  _dart2jsArgsOption,
  _nativeNullAssertionsOption,
];

const _compilerOption = 'compiler';
const _dart2jsArgsOption = 'dart2js_args';
const _nativeNullAssertionsOption = 'native_null_assertions';

/// The deprecated keys for the `options` config for the [WebEntrypointBuilder].
const _deprecatedOptions = [
  'enable_sync_async',
  'ignore_cast_failures',
];

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
    var isAppEntrypoint = await _isAppEntryPoint(dartEntrypointId, buildStep);
    if (!isAppEntrypoint) return;

    var appEntrypoingId = dartEntrypointId.changeExtension('.app.dart');

    var hasWebPlugins = await buildStep.canRead(AssetId(dartEntrypointId.package, 'lib/web_plugin_registrant.dart'));

    await buildStep.writeAsString(appEntrypoingId, '''
import 'dart:ui' as ui;

import 'package:jaspr/browser.dart';
import '${p.basename(dartEntrypointId.path)}' as app;
${hasWebPlugins ? "import 'package:${dartEntrypointId.package}/web_plugin_registrant.dart';" : ''}

Future<void> main() async {
  BrowserAppBinding.warmupFlutterEngine = ui.webOnlyWarmupEngine;
  ${hasWebPlugins ? 'registerPlugins();' : ''}
  app.main();
}
    ''');
  }
}

/// Returns whether or not [dartId] is an app entrypoint (basically, whether
/// or not it has a `main` function).
Future<bool> _isAppEntryPoint(AssetId dartId, AssetReader reader) async {
  assert(dartId.extension == '.dart');
  // Skip reporting errors here, dartdevc will report them later with nicer
  // formatting.
  var parsed = parseString(content: await reader.readAsString(dartId), throwIfDiagnostics: false).unit;
  // Allow two or fewer arguments so that entrypoints intended for use with
  // [spawnUri] get counted.
  //
  // TODO: This misses the case where a Dart file doesn't contain main(),
  // but has a part that does, or it exports a `main` from another library.
  return parsed.declarations.any((node) {
    return node is FunctionDeclaration &&
        node.name.lexeme == 'main' &&
        node.functionExpression.parameters != null &&
        node.functionExpression.parameters!.parameters.length <= 2;
  });
}

/// Files copied from the SDK that are required at runtime to run a DDC
/// application.
final _ddcSdkResources = [
  AssetId('jaspr_web_compilers', 'lib/src/dev_compiler/dart_sdk.js'),
  AssetId('jaspr_web_compilers', 'lib/src/dev_compiler/require.js')
];
