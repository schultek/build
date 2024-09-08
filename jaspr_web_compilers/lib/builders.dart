// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:build/build.dart';
import 'package:build_modules/build_modules.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'jaspr_web_compilers.dart';
import 'src/common.dart';
import 'src/sdk_js_copy_builder.dart';
import 'src/web_entrypoint_bootstrap_builder.dart';
import 'src/web_plugins_builder.dart';

// Shared entrypoint bootstrap builder
Builder webEntrypointBootstrapBuilder(BuilderOptions options) =>
    const WebEntrypointBootstrapBuilder();

// Shared entrypoint builder
Builder webEntrypointBuilder(BuilderOptions options) =>
    WebEntrypointBuilder.fromOptions(options);

Builder webPluginsBuilder(_) => WebPluginsBuilder();

// Ddc related builders
Builder ddcMetaModuleBuilder(BuilderOptions options) =>
    MetaModuleBuilder.forOptions(ddcPlatform, options);
Builder ddcMetaModuleCleanBuilder(_) => MetaModuleCleanBuilder(ddcPlatform);
Builder ddcModuleBuilder([_]) => ModuleBuilder(ddcPlatform);

Builder ddcBuilder(BuilderOptions options) {
  validateOptions(options.config, _supportedOptions, 'jaspr_web_compilers:ddc');
  _ensureSameDdcOptions(options);

  return DevCompilerBuilder(
    useIncrementalCompiler: _readUseIncrementalCompilerOption(options),
    generateFullDill: _readGenerateFullDillOption(options),
    emitDebugSymbols: _readEmitDebugSymbolsOption(options),
    canaryFeatures: _readCanaryOption(options),
    platformSdk: webSdkDir,
    sdkKernelPath: p.url.join('kernel', 'ddc_outline_sound.dill'),
    trackUnusedInputs: _readTrackInputsCompilerOption(options),
    platform: ddcPlatform,
    environment: _readEnvironmentOption(options),
    librariesPath: p.join(webSdkDir, 'libraries.json'),
  );
}

final ddcKernelExtension = '.ddc.dill';

Builder ddcKernelBuilder(BuilderOptions options) {
  validateOptions(options.config, _supportedOptions, 'jaspr_web_compilers:ddc');
  _ensureSameDdcOptions(options);

  return KernelBuilder(
      summaryOnly: true,
      platformSdk: webSdkDir,
      sdkKernelPath: p.url.join('kernel', 'ddc_outline_sound.dill'),
      outputExtension: ddcKernelExtension,
      platform: ddcPlatform,
      useIncrementalCompiler: _readUseIncrementalCompilerOption(options),
      librariesPath: p.join(webSdkDir, 'libraries.json'),
      trackUnusedInputs: _readTrackInputsCompilerOption(options));
}

Builder sdkJsCopy(_) => SdkJsCopyBuilder();

// Dart2js related builders
Builder dart2jsMetaModuleBuilder(BuilderOptions options) =>
    MetaModuleBuilder.forOptions(dart2jsPlatform, options);
Builder dart2jsMetaModuleCleanBuilder(_) =>
    MetaModuleCleanBuilder(dart2jsPlatform);
Builder dart2jsModuleBuilder([_]) => ModuleBuilder(dart2jsPlatform);
PostProcessBuilder dart2jsArchiveExtractor(BuilderOptions options) =>
    Dart2JsArchiveExtractor.fromOptions(options);

// Dart2wasm related builders
Builder dart2wasmMetaModuleBuilder(BuilderOptions options) =>
    MetaModuleBuilder.forOptions(dart2wasmPlatform, options);
Builder dart2wasmMetaModuleCleanBuilder(_) =>
    MetaModuleCleanBuilder(dart2wasmPlatform);
Builder dart2wasmModuleBuilder([_]) => ModuleBuilder(dart2wasmPlatform);

// General purpose builders
PostProcessBuilder dartSourceCleanup(BuilderOptions options) =>
    (options.config['enabled'] as bool? ?? false)
        ? const FileDeletingBuilder(
            ['.dart', '.js.map', '.ddc.js.metadata', '.ddc_merged_metadata'])
        : const FileDeletingBuilder(
            ['.dart', '.js.map', '.ddc.js.metadata', '.ddc_merged_metadata'],
            isEnabled: false);

/// Throws if it is ever given different options.
void _ensureSameDdcOptions(BuilderOptions options) {
  if (_previousDdcConfig != null) {
    if (!const MapEquality<String, Object?>()
        .equals(_previousDdcConfig, options.config)) {
      throw ArgumentError(
          'The jaspr_web_compilers:ddc builder must have the same '
          'configuration in all packages. Saw $_previousDdcConfig and '
          '${options.config} which are not equal.\n\n '
          'Please use the `global_options` section in '
          '`build.yaml` or the `--define` flag to set global options.');
    }
  } else {
    _previousDdcConfig = options.config;
  }
}

bool _readUseIncrementalCompilerOption(BuilderOptions options) {
  return options.config[_useIncrementalCompilerOption] as bool? ?? true;
}

bool _readGenerateFullDillOption(BuilderOptions options) {
  return options.config[_generateFullDillOption] as bool? ?? false;
}

bool _readEmitDebugSymbolsOption(BuilderOptions options) {
  return options.config[_emitDebugSymbolsOption] as bool? ?? false;
}

bool _readCanaryOption(BuilderOptions options) {
  return options.config[_canaryOption] as bool? ?? false;
}

bool _readTrackInputsCompilerOption(BuilderOptions options) {
  return options.config[_trackUnusedInputsCompilerOption] as bool? ?? true;
}

Map<String, String> _readEnvironmentOption(BuilderOptions options) {
  final environment = options.config[_environmentOption] as Map? ?? const {};
  return environment.map((key, value) => MapEntry('$key', '$value'));
}

Map<String, dynamic>? _previousDdcConfig;
const _useIncrementalCompilerOption = 'use-incremental-compiler';
const _generateFullDillOption = 'generate-full-dill';
const _emitDebugSymbolsOption = 'emit-debug-symbols';
const _canaryOption = 'canary';
const _trackUnusedInputsCompilerOption = 'track-unused-inputs';
const _environmentOption = 'environment';

const _supportedOptions = [
  _environmentOption,
  _useIncrementalCompilerOption,
  _generateFullDillOption,
  _emitDebugSymbolsOption,
  _canaryOption,
  _trackUnusedInputsCompilerOption,
];
