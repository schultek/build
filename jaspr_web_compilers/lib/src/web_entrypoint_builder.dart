// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:build/build.dart';
import 'package:build_modules/build_modules.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

import 'common.dart';
import 'dart2js_bootstrap.dart';
import 'dart2wasm_bootstrap.dart';
import 'dev_compiler_bootstrap.dart';
import 'web_entrypoint_bootstrap_builder.dart';

const ddcBootstrapExtension = '.dart.bootstrap.js';
const jsEntrypointExtension = '.dart.js';
const wasmExtension = '.wasm';
const moduleJsExtension = '.mjs';
const wasmSourceMapExtension = '.wasm.map';
const jsEntrypointSourceMapExtension = '.dart.js.map';
const jsEntrypointArchiveExtension = '.dart.js.tar.gz';
const digestsEntrypointExtension = '.digests';
const mergedMetadataExtension = '.dart.ddc_merged_metadata';

/// Which compiler to use when compiling web entrypoints.
enum WebCompiler {
  // ignore: constant_identifier_names
  Dart2Js(
    'dart2js',
    entrypointExtensionWhenOnlyCompiler: jsEntrypointExtension,
    entrypointExtension: '.dart2js.js',
  ),
  // ignore: constant_identifier_names
  DartDevc(
    'dartdevc',
    entrypointExtensionWhenOnlyCompiler: jsEntrypointExtension,
    entrypointExtension: '.ddc.js',
  ),
  // ignore: constant_identifier_names
  Dart2Wasm(
    'dart2wasm',
    entrypointExtensionWhenOnlyCompiler: moduleJsExtension,
    entrypointExtension: moduleJsExtension,
  );

  /// The name of this compiler used when identifying it in builder options.
  final String optionName;

  /// The [EnabledEntrypointCompiler.extension] to use when this compiler is the
  /// only compiler enabled.
  /// This defaults to `.dart.js` for compilers targeting JavaScript and `.mjs`
  /// for the module file emitted by `dart2wasm`.
  final String entrypointExtensionWhenOnlyCompiler;

  /// The [EnabledEntrypointCompiler.extension] to use by default when multiple
  /// compilers are enabled.
  ///
  /// This can't be `.dart.js` for multiple web compilers because we'd then run
  /// into duplicate outputs being generated.
  final String entrypointExtension;

  const WebCompiler(
    this.optionName, {
    required this.entrypointExtensionWhenOnlyCompiler,
    required this.entrypointExtension,
  });

  static WebCompiler fromOptionName(String name) {
    for (final compiler in values) {
      if (compiler.optionName == name) {
        return compiler;
      }
    }

    final supported = values.map((e) => '`${e.optionName}`').join(', ');

    throw ArgumentError.value(
      name,
      null,
      'Unknown web compiler, supported are: $supported.',
    );
  }
}

final class EnabledEntrypointCompiler {
  final WebCompiler compiler;
  final String extension;
  final List<String> compilerArguments;

  EnabledEntrypointCompiler({
    required this.compiler,
    required this.extension,
    required this.compilerArguments,
  });
}

final class EntrypointBuilderOptions {
  final List<EnabledEntrypointCompiler> compilers;

  /// Whether or not to enable runtime non-null assertions for values returned
  /// from browser apis.
  ///
  /// If `null` then no flag will be provided to the compiler, and the default
  /// will be used.
  final bool? nativeNullAssertions;

  /// dart2wasm emits a WebAssembly module and a `.mjs` file exporting symbols
  /// to instantiate that module.
  ///
  /// To generate a runnable entrypoint file, a loader will have to load the
  /// `.mjs` module and invoke the exported methods.
  /// This loader can be generated by `jaspr_web_compilers` (and is by default
  /// if dart2wasm is enabled), but this can be turned off for users which need
  /// a custom way to load WebAssembly modules (e.g. to target Node.JS).
  /// When multiple compilers are enabled (typically dart2js + dart2wasm) for
  /// release builds, the loader file is also responsible for running a feature
  /// detection, preferring WebAssembly but falling back to JavaScript if
  /// necessary.
  final String? loaderExtension;

  EntrypointBuilderOptions({
    required this.compilers,
    this.nativeNullAssertions,
    this.loaderExtension,
  });

  factory EntrypointBuilderOptions.fromOptions(BuilderOptions options) {
    const deprecatedOptions = [
      'enable_sync_async',
      'ignore_cast_failures',
    ];

    const compilerOption = 'compiler';
    const compilersOption = 'compilers';
    const dart2jsArgsOption = 'dart2js_args';
    const dart2wasmArgsOption = 'dart2wasm_args';
    const nativeNullAssertionsOption = 'native_null_assertions';
    const loaderOption = 'loader';
    String? defaultLoaderOption;

    const supportedOptions = [
      compilersOption,
      compilerOption,
      dart2jsArgsOption,
      nativeNullAssertionsOption,
      dart2wasmArgsOption,
      loaderOption,
    ];

    var config = options.config;
    var nativeNullAssertions =
        options.config[nativeNullAssertionsOption] as bool?;
    var compilers = <EnabledEntrypointCompiler>[];

    validateOptions(config, supportedOptions, 'jaspr_web_compilers:entrypoint',
        deprecatedOptions: deprecatedOptions);

    // The compilers option is a map of compiler names to options only applying
    // to that compiler, which allows compiling with multiple compilers (e.g.
    // dart2js + dart2wasm). Since the default builder configuration doesn't
    // use the compilers key, we preserve backwards compatibility.
    if (config.containsKey(compilersOption)) {
      var configuredCompilers =
          (config[compilersOption] as Map?)?.cast<String, Map?>() ?? const {};
      var hasDart2Wasm = false;

      for (var MapEntry(:key, :value) in configuredCompilers.entries) {
        const extensionOption = 'extension';
        const argsOption = 'args';
        const supportedOptions = [extensionOption, argsOption];
        validateOptions(Map<String, dynamic>.from(value ?? const {}),
            supportedOptions, 'jaspr_web_compilers:entrypoint');

        var compiler = WebCompiler.fromOptionName(key);
        compilers.add(EnabledEntrypointCompiler(
          compiler: compiler,
          extension: value?[extensionOption] as String? ??
              (configuredCompilers.length == 1
                  ? compiler.entrypointExtensionWhenOnlyCompiler
                  : compiler.entrypointExtension),
          compilerArguments: _parseCompilerOptions(
              value?[argsOption], '$compilersOption.$key'),
        ));

        hasDart2Wasm |= compiler == WebCompiler.Dart2Wasm;
      }

      if (hasDart2Wasm) {
        defaultLoaderOption = '.dart.js';
      }
    } else {
      var compilerName = config[compilerOption] as String? ?? 'dartdevc';

      var compiler = WebCompiler.fromOptionName(compilerName);
      compilers.add(EnabledEntrypointCompiler(
        compiler: compiler,
        extension: compiler.entrypointExtensionWhenOnlyCompiler,
        compilerArguments: switch (compiler) {
          WebCompiler.DartDevc => const [],
          WebCompiler.Dart2Js =>
            _parseCompilerOptions(config[dart2jsArgsOption], dart2jsArgsOption),
          WebCompiler.Dart2Wasm => _parseCompilerOptions(
              config[dart2wasmArgsOption], dart2wasmArgsOption),
        },
      ));

      if (compiler == WebCompiler.Dart2Wasm) {
        // dart2wasm needs a custom loader script to work as an entrypoint, so
        // enable one by default if dart2wasm is configured as compiler.
        defaultLoaderOption = '.dart.js';
      }
    }

    return EntrypointBuilderOptions(
      compilers: compilers,
      nativeNullAssertions: nativeNullAssertions,
      loaderExtension: config.containsKey(loaderOption)
          ? config[loaderOption] as String?
          : defaultLoaderOption,
    );
  }

  EnabledEntrypointCompiler? optionsFor(WebCompiler compiler) {
    return compilers.firstWhereOrNull((c) => c.compiler == compiler);
  }

  Map<String, List<String>> get buildExtensions {
    return {
      bootstrapDartExtension: [
        if (optionsFor(WebCompiler.DartDevc) case final ddc?) ...[
          ddcBootstrapExtension,
          mergedMetadataExtension,
          digestsEntrypointExtension,
          ddc.extension,
        ],
        if (optionsFor(WebCompiler.Dart2Js) case final dart2js?) ...[
          dart2js.extension,
          jsEntrypointSourceMapExtension,
          jsEntrypointArchiveExtension,
        ],
        if (optionsFor(WebCompiler.Dart2Wasm) case final dart2wasm?) ...[
          dart2wasm.extension,
          wasmExtension,
          wasmSourceMapExtension,
        ],
        if (loaderExtension case final loader?) loader,
      ]
    };
  }

  static List<String> _parseCompilerOptions(Object? from, String key) {
    return switch (from) {
      null => const [],
      List list => list.map((arg) => '$arg').toList(),
      String other => throw ArgumentError.value(
          other,
          key,
          'There may have been a failure decoding as JSON, expected a list.',
        ),
      var other => throw ArgumentError.value(other, key, 'Expected a list'),
    };
  }
}

/// The deprecated keys for the `options` config for the [WebEntrypointBuilder].

/// A builder which compiles entrypoints for the web.
///
/// Supports `dart2js` and `dartdevc`.
class WebEntrypointBuilder implements Builder {
  final EntrypointBuilderOptions options;

  const WebEntrypointBuilder(this.options);

  factory WebEntrypointBuilder.fromOptions(BuilderOptions options) {
    return WebEntrypointBuilder(EntrypointBuilderOptions.fromOptions(options));
  }

  @override
  Map<String, List<String>> get buildExtensions => options.buildExtensions;

  @override
  Future<void> build(BuildStep buildStep) async {
    var dartEntrypointId = buildStep.inputId;
    var isAppEntrypoint = await isAppEntryPoint(dartEntrypointId, buildStep);
    if (!isAppEntrypoint) return;

    final compilationSteps = <Future>[];

    for (final compiler in options.compilers) {
      switch (compiler.compiler) {
        case WebCompiler.DartDevc:
          compilationSteps.add(Future(() async {
            try {
              await bootstrapDdc(buildStep,
                  nativeNullAssertions: options.nativeNullAssertions,
                  requiredAssets: _ddcSdkResources);
            } on MissingModulesException catch (e) {
              log.severe('$e');
            }
          }));
        case WebCompiler.Dart2Js:
          compilationSteps.add(bootstrapDart2Js(
            buildStep,
            compiler.compilerArguments,
            nativeNullAssertions: options.nativeNullAssertions,
            entrypointExtension: compiler.extension,
          ));
        case WebCompiler.Dart2Wasm:
          compilationSteps.add(bootstrapDart2Wasm(
              buildStep, compiler.compilerArguments, compiler.extension));
      }
    }
    await Future.wait(compilationSteps);
    if (_generateLoader(buildStep.inputId.changeExtension(''))
        case (var id, var loader)?) {
      await buildStep.writeAsString(id, loader);
    }
  }

  (AssetId, String)? _generateLoader(AssetId input) {
    var loaderExtension = options.loaderExtension;
    var wasmCompiler = options.optionsFor(WebCompiler.Dart2Wasm);
    if (loaderExtension == null || wasmCompiler == null) {
      // Generating the loader has been disabled or no loader is necessary.
      return null;
    }

    var loaderId = input.changeExtension(options.loaderExtension!);
    var basename = p.url.basenameWithoutExtension(input.path);

    // Are we compiling to JavaScript in addition to wasm?
    var jsCompiler = options.optionsFor(WebCompiler.Dart2Js) ??
        options.optionsFor(WebCompiler.DartDevc);

    var loaderResult = StringBuffer('''
(async () => {
const thisScript = document.currentScript;

function relativeURL(ref) {
  const base = thisScript?.src ?? document.baseURI;
  return new URL(ref, base).toString();
}

''');

    // If we're compiling to JS, start a feature detection to prefer wasm but
    // fall back to JS if necessary.
    if (jsCompiler != null) {
      loaderResult.writeln('''
function supportsWasmGC() {
  // This attempts to instantiate a wasm module that only will validate if the
  // final WasmGC spec is implemented in the browser.
  //
  // Copied from https://github.com/GoogleChromeLabs/wasm-feature-detect/blob/main/src/detectors/gc/index.js
  const bytes = [0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 95, 1, 120, 0];
  return 'WebAssembly' in self && WebAssembly.validate(new Uint8Array(bytes));
}

if (supportsWasmGC()) {
''');
    }

    loaderResult.writeln('''
let { compileStreaming } = await import("./$basename${wasmCompiler.extension}");

let app = await compileStreaming(fetch(relativeURL("$basename.wasm")));
let module = await app.instantiate({});
module.invokeMain();
''');

    if (jsCompiler != null) {
      loaderResult.writeln('''
} else {
const scriptTag = document.createElement("script");
scriptTag.type = "application/javascript";
scriptTag.src = relativeURL("./$basename${jsCompiler.extension}");
document.head.append(scriptTag);
}
''');
    }

    loaderResult.writeln('})();');
    return (loaderId, loaderResult.toString());
  }
}

/// Returns whether or not [dartId] is an app entrypoint (basically, whether
/// or not it has a `main` function).
Future<bool> isAppEntryPoint(AssetId dartId, AssetReader reader) async {
  assert(dartId.extension == '.dart');
  // Skip reporting errors here, dartdevc will report them later with nicer
  // formatting.
  var parsed = parseString(
          content: await reader.readAsString(dartId), throwIfDiagnostics: false)
      .unit;
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
