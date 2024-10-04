// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:build/build.dart';
import 'package:package_config/package_config.dart';
import 'package:yaml/yaml.dart';

/// Copies the js from the sdk itself, into the
/// jaspr_web_compilers package at `lib/src/dev_compiler`.
class WebPluginsBuilder implements Builder {
  @override
  final buildExtensions = {
    r'$package$': ['lib/web_plugin_registrant.dart']
  };

  @override
  FutureOr<void> build(BuildStep buildStep) async {
    var packageConfig = await buildStep.packageConfig;
    final plugins = <Plugin>[];

    for (var package in packageConfig.packages) {
      final plugin = await _loadPluginForPackage(package, buildStep);
      if (plugin != null) {
        plugins.add(plugin);
      }
    }

    if (plugins.isEmpty) {
      return;
    }

    await buildStep.writeAsString(
      AssetId(buildStep.inputId.package, 'lib/web_plugin_registrant.dart'),
      _generateWebPluginsFile(plugins),
    );
  }

  Future<Plugin?> _loadPluginForPackage(
      Package package, BuildStep buildStep) async {
    var pubspecId = AssetId.resolve(package.root.resolve('pubspec.yaml'));
    Object? pubspec;
    try {
      pubspec = loadYaml(await buildStep.readAsString(pubspecId));
    } on YamlException catch (_) {
      // Do nothing, potentially not a plugin.
    }

    if (pubspec
        case {
          'flutter': {'plugin': {'platforms': {'web': YamlMap webPlatformYaml}}}
        }) {
      if (webPlatformYaml.containsKey('default_package')) {
        return null;
      }

      if (webPlatformYaml
          case {
            'pluginClass': String pluginClass,
            'fileName': String fileName
          }) {
        return Plugin(
          name: package.name,
          pluginClass: pluginClass,
          fileName: fileName,
        );
      }
    }

    return null;
  }

  String _generateWebPluginsFile(List<Plugin> plugins) {
    return '''
// Jaspr web plugin registrant file.
//
// Generated file. Do not edit.
//

// ignore_for_file: type=lint

${plugins.map((p) => "import 'package:${p.name}/${p.fileName}';\n").join()}
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void registerPlugins([final Registrar? pluginRegistrar]) {
  final Registrar registrar = pluginRegistrar ?? webPluginRegistrar;
${plugins.map((p) => "  ${p.pluginClass}.registerWith(registrar);\n").join()}
  registrar.registerMessageHandler();
}
    ''';
  }
}

class Plugin {
  Plugin(
      {required this.name, required this.pluginClass, required this.fileName});

  factory Plugin.fromJson(Map<String, dynamic> map) => switch (map) {
        {
          'name': String name,
          'pluginClass': String pluginClass,
          'fileName': String fileName
        } =>
          Plugin(name: name, pluginClass: pluginClass, fileName: fileName),
        _ => throw Exception('Cannot parse map to plugin.'),
      };

  final String name;
  final String pluginClass;
  final String fileName;

  Object toJson() =>
      {'name': name, 'pluginClass': pluginClass, 'fileName': fileName};
}
