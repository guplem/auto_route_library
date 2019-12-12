import 'package:auto_route_generator/route_config_visitor.dart';
import 'package:auto_route_generator/string_utils.dart';

class RouterClassGenerator {
  final List<RouteConfig> allRoutes;

  final StringBuffer _stringBuffer = StringBuffer();

  RouterClassGenerator(this.allRoutes);

  // helper functions
  void _write(Object obj) => _stringBuffer.write(obj);

  void _writeln([Object obj]) => _stringBuffer.writeln(obj);

  void _newLine() => _stringBuffer.writeln();

  String generate() {
    _generateBoxed("GENERATED BY AutoRoute LIBRARY - DO NOT MODIFY BY HAND");
    _generateImports();

    final routeNames = allRoutes.map((r) => r.navigatorName);

    routeNames.toSet().forEach((navName) {
      _generateRouterClass(navName, allRoutes.where((r) => r.navigatorName == navName).toList());
    });

    _generateArgumentHolders();
    return _stringBuffer.toString();
  }

  void _generateImports() {
    // write route imports
    final imports = List<String>();
    imports.add("'package:flutter/material.dart'");
    imports.add("'package:flutter/cupertino.dart'");
    imports.add("'package:auto_route/router_utils.dart'");
    allRoutes.forEach((r) {
      imports.add(r.import);
      if (r.transitionBuilder != null) imports.add(r.transitionBuilder.import);
      if (r.parameters != null) {
        r.parameters.forEach((param) {
          if (param.imports != null) imports.addAll(param.imports);
        });
      }
    });
    imports.toSet().forEach((import) => _writeln("import $import;"));
  }

  void _generateRouteNames(List<RouteConfig> routes) {
    _newLine();
    routes.forEach((r) {
      if (r.initial != null && r.initial) {
        _writeln("static const initialRoute = '/';");
      } else {
        final routeName = _generateRouteName(r);
        return _writeln("static const $routeName = '/$routeName';");
      }
    });
  }

  String _generateRouteName(RouteConfig r) {
    String routeName = _routeNameFromClassName(r.className);
    if (r.name != null) {
      final strippedName = r.name.replaceAll(r"\s", "");
      if (strippedName.isNotEmpty) routeName = strippedName;
    }
    return routeName;
  }

  String _routeNameFromClassName(String className) {
    final name = toLowerCamelCase(className);
    return "${name}Route";
  }

  void _generateRouteGeneratorFunction(List<RouteConfig> routes) {
    _newLine();
    _writeln("static Route<dynamic> onGenerateRoute(RouteSettings settings) {");
    _writeln("final args = settings.arguments;");
    _writeln("switch (settings.name) {");

    routes.forEach((r) => generateRoute(r));

    // build unknown route error page if route is not found
    _writeln("default: return unknownRoutePage(settings.name);");
    // close switch case
    _writeln("}");
    _newLine();

    // close onGenerateRoute function
    _writeln("}");
  }

  void generateRoute(RouteConfig r) {
    final caseName = (r.initial != null && r.initial) ? "initialRoute" : _generateRouteName(r);
    _writeln("case $caseName:");

    StringBuffer constructorParams = StringBuffer("");

    if (r.parameters != null && r.parameters.isNotEmpty) {
      if (r.parameters.length == 1) {
        final param = r.parameters[0];

        // show an error page if passed args are not the same as declared args
        _writeln("if(hasInvalidArgs<${param.type}>(args");
        if (param.isRequired) {
          _write(",isRequired:true");
        }
        _write("))");
        _writeln("return misTypedArgsRoute<${param.type}>(args);");

        _writeln("final typedArgs = args as ${param.type};");

        if (param.isPositional) {
          constructorParams.write("typedArgs");
        } else {
          constructorParams.write("${param.name}: typedArgs");
          if (param.defaultValueCode != null) {
            constructorParams.write(" ?? ${param.defaultValueCode}");
          }
        }
      } else {
        // if router has any required params the argument class holder becomes required.
        final hasRequiredParams = r.parameters.where((p) => p.isRequired).isNotEmpty;
        // show an error page  if passed args are not the same as declared args
        _writeln("if(hasInvalidArgs<${r.className}Arguments>(args");
        if (hasRequiredParams) {
          _write(",isRequired:true");
        }
        _write("))");
        _writeln("return misTypedArgsRoute<${r.className}Arguments>(args);");

        _writeln("final typedArgs = args as ${r.className}Arguments");
        if (!hasRequiredParams) {
          _write(" ?? ${r.className}Arguments()");
        }
        _write(";");

        r.parameters.asMap().forEach((i, param) {
          if (param.isPositional) {
            constructorParams.write("typedArgs.${param.name}");
          } else {
            constructorParams.write("${param.name}:typedArgs.${param.name}");
          }
          if (i != r.parameters.length - 1) {
            constructorParams.write(",");
          }
        });
      }
    }

    final widget = "${r.className}(${constructorParams.toString()})";
    if (r.transitionBuilder == null) {
      _write("return MaterialPageRoute(builder: (_) => $widget, settings: settings,");
      if (r.fullscreenDialog != null) _write("fullscreenDialog:${r.fullscreenDialog.toString()},");
      if (r.maintainState != null) _write("maintainState:${r.maintainState.toString()},");
    } else {
      _write(
          "return PageRouteBuilder(pageBuilder: (ctx, animation, secondaryAnimation) => $widget, settings: settings,");
      if (r.maintainState != null) _write(",maintainState:${r.maintainState.toString()}");
      _write("transitionsBuilder: ${r.transitionBuilder.name},");
      if (r.durationInMilliseconds != null)
        _write("transitionDuration: Duration(milliseconds: ${r.durationInMilliseconds}),");
    }
    _writeln(");");
  }

  void _generateArgumentHolders() {
    final routesWithArgsHolders = allRoutes.where((r) => r.parameters != null && r.parameters.length > 1);
    if (routesWithArgsHolders.isNotEmpty) _generateBoxed("Arguments holder classes");
    routesWithArgsHolders.forEach((r) {
      _generateArgsHolder(r);
    });
  }

  void _generateArgsHolder(RouteConfig r) {
    _writeln("//${r.className} arguments holder class");
    final argsClassName = "${r.className}Arguments";

    // generate fields
    _writeln("class $argsClassName{");
    r.parameters.forEach((param) {
      _writeln("final ${param.type} ${param.name};");
    });

    // generate constructor
    _writeln("$argsClassName({");
    r.parameters.asMap().forEach((i, param) {
      if (param.isRequired) {
        _write("@required ");
      }
      _write("this.${param.name}");
      if (param.defaultValueCode != null) _write(" = ${param.defaultValueCode}");
      if (i != r.parameters.length - 1) _write(",");
    });
    _writeln("});");

    _writeln("}");
  }

  void _generateBoxed(String message) {
    _writeln("\n//".padRight(77, "-"));
    _writeln("// $message");
    _writeln("//".padRight(77, "-"));
    _newLine();
  }

  void _generateRouterClass(String navigatorName, List<RouteConfig> routes) {
//  throw an exception if there's more than one class with the same navigatorName annotated with @InitialRoute()
    final routerClassName = navigatorName == "root" ? "Router" : "${capitalize(navigatorName)}";

    if (routes.where((r) => r.initial != null).length > 1) {
      throw ("\n ------------ There can be only one initial route per navigator ------------ \n");
    }

    _writeln("\nclass $routerClassName {");
    _generateRouteNames(routes);
    _generateHelperFunctions(navigatorName);
    _generateRouteGeneratorFunction(routes);

    // close router class
    _writeln("}");
  }

  void _generateHelperFunctions(String navigatorName) {
    String navVarName = navigatorName == "root" ? "" : "'$navigatorName'";
    _writeln("static GlobalKey<NavigatorState> get navigatorKey => getNavigatorKey($navVarName);");
    _writeln("static NavigatorState get navigator => navigatorKey.currentState;");
  }
}
