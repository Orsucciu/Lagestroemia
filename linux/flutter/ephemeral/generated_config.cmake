# Generated code do not commit.
file(TO_CMAKE_PATH "/home/z/.local/opt/flutter" FLUTTER_ROOT)
file(TO_CMAKE_PATH "/home/z/my-project/lagestroemia" PROJECT_DIR)

set(FLUTTER_VERSION "0.1.0+1" PARENT_SCOPE)
set(FLUTTER_VERSION_MAJOR 0 PARENT_SCOPE)
set(FLUTTER_VERSION_MINOR 1 PARENT_SCOPE)
set(FLUTTER_VERSION_PATCH 0 PARENT_SCOPE)
set(FLUTTER_VERSION_BUILD 1 PARENT_SCOPE)

# Environment variables to pass to tool_backend.sh
list(APPEND FLUTTER_TOOL_ENVIRONMENT
  "FLUTTER_ROOT=/home/z/.local/opt/flutter"
  "PROJECT_DIR=/home/z/my-project/lagestroemia"
  "DART_OBFUSCATION=false"
  "TRACK_WIDGET_CREATION=true"
  "TREE_SHAKE_ICONS=true"
  "PACKAGE_CONFIG=/home/z/my-project/lagestroemia/.dart_tool/package_config.json"
  "FLUTTER_TARGET=lib/main.dart"
)
