// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;

import 'common.dart';

/// Copies the js from the sdk itself, into the
/// jaspr_web_compilers package at `lib/src/dev_compiler`.
class SdkJsCopyBuilder implements Builder {
  @override
  final buildExtensions = {
    r'$package$': [
      'lib/src/dev_compiler/require.js',
      'lib/src/dev_compiler/dart_sdk.js',
      'lib/src/dev_compiler/dart_sdk.js.map'
    ]
  };

  /// Path to the require.js file that should be used for all ddc web apps.
  final _sdkRequireJsLocation =
      p.join(sdkDir, 'lib', 'dev_compiler', 'amd', 'require.js');

  /// Path to the dart_sdk.js file that should be used for all ddc web apps.
  final _sdkJsLocation =
      p.join(webSdkDir, 'kernel', 'amd-canvaskit-sound', 'dart_sdk.js');

  /// Path to the dart_sdk.js.map file that should be used for all ddc web apps.
  final _sdkJsMapLocation =
      p.join(webSdkDir, 'kernel', 'amd-canvaskit-sound', 'dart_sdk.js.map');

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    if (buildStep.inputId.package != 'jaspr_web_compilers') {
      throw StateError('This builder should only be applied to the '
          'jaspr_web_compilers package');
    }
    await buildStep.writeAsBytes(
      AssetId('jaspr_web_compilers', 'lib/src/dev_compiler/require.js'),
      await File(_sdkRequireJsLocation).readAsBytes(),
    );
    await buildStep.writeAsBytes(
      AssetId('jaspr_web_compilers', 'lib/src/dev_compiler/dart_sdk.js'),
      await File(_sdkJsLocation).readAsBytes(),
    );
    await buildStep.writeAsBytes(
      AssetId('jaspr_web_compilers', 'lib/src/dev_compiler/dart_sdk.js.map'),
      await File(_sdkJsMapLocation).readAsBytes(),
    );
  }
}
