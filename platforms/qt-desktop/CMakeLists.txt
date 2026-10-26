cmake_minimum_required(VERSION 3.21)

project(UzTranslit
    VERSION 1.3.0
    DESCRIPTION "Uzbek script converter: Cyrillic, Latin 1995, Latin 2026"
    HOMEPAGE_URL "https://latin.jaybi.uz"
    LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(UZT_BUILD_TESTS "Build the tests (fixtures, differential, documents, CLI, GUI, translations)" ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Widgets LinguistTools)
if(UZT_BUILD_TESTS)
    find_package(Qt6 6.5 REQUIRED COMPONENTS Test)
endif()
qt_standard_project_setup()
include(GNUInstallDirs)

# The repository root holds spec/fixtures.json and build/differential.json.
get_filename_component(UZT_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." REALPATH)

add_library(uztranslit_warnings INTERFACE)
if(MSVC)
    target_compile_options(uztranslit_warnings INTERFACE /W4 /permissive-)
else()
    target_compile_options(uztranslit_warnings INTERFACE -Wall -Wextra -Wpedantic)
endif()

# ---------------------------------------------------------------- the engine (Qt Core only)
qt_add_library(uztranslit_core STATIC
    core/uztranslit.hpp
    core/uztranslit.cpp)
target_include_directories(uztranslit_core PUBLIC core)
target_link_libraries(uztranslit_core PUBLIC Qt6::Core PRIVATE uztranslit_warnings)
if(MSVC)
    target_compile_options(uztranslit_core PUBLIC /utf-8) # the sources are UTF-8 (letters in string literals)
endif()

# ---------------------------------------------------------------- files, documents, batch, command line (Qt Core)
qt_add_library(uztranslit_files STATIC
    src/textfile.hpp src/textfile.cpp
    src/documents.hpp src/documents.cpp
    src/batch.hpp src/batch.cpp
    src/cli.hpp src/cli.cpp)
target_include_directories(uztranslit_files PUBLIC src)
target_link_libraries(uztranslit_files PUBLIC uztranslit_core Qt6::Core PRIVATE uztranslit_warnings)

# ---------------------------------------------------------------- widgets
qt_add_library(uztranslit_gui STATIC
    src/settings.hpp src/settings.cpp
    src/language.hpp src/language.cpp
    src/mainwindow.hpp src/mainwindow.cpp
    src/batchdialog.hpp src/batchdialog.cpp
    src/qtstrings.cpp)
target_link_libraries(uztranslit_gui PUBLIC uztranslit_files Qt6::Widgets PRIVATE uztranslit_warnings)

set(UZT_ICON_SIZES 16 24 32 48 64 128 256)
set(UZT_ICON_FILES "")
foreach(size IN LISTS UZT_ICON_SIZES)
    list(APPEND UZT_ICON_FILES "resources/icons/uztranslit-${size}.png")
endforeach()

# The compiled translations and the icons go into every executable that shows the interface.
function(uzt_add_app_resources target)
    qt_add_resources(${target} "${target}_icons" PREFIX "/icons" BASE resources/icons FILES ${UZT_ICON_FILES})
    qt_add_resources(${target} "${target}_i18n" PREFIX "/i18n" BASE "${CMAKE_CURRENT_BINARY_DIR}" FILES ${uzt_qm_files})
endfunction()

# ---------------------------------------------------------------- the application
set(UZT_PLATFORM_SOURCES "")
if(WIN32)
    configure_file(packaging/windows/uztranslit.rc.in "${CMAKE_CURRENT_BINARY_DIR}/uztranslit.rc" @ONLY)
    list(APPEND UZT_PLATFORM_SOURCES "${CMAKE_CURRENT_BINARY_DIR}/uztranslit.rc")
elseif(APPLE)
    set(UZT_ICNS "${CMAKE_CURRENT_SOURCE_DIR}/packaging/macos/uztranslit.icns")
    set_source_files_properties("${UZT_ICNS}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    list(APPEND UZT_PLATFORM_SOURCES "${UZT_ICNS}")
endif()

qt_add_executable(uztranslit WIN32 MACOSX_BUNDLE src/main.cpp ${UZT_PLATFORM_SOURCES})
target_link_libraries(uztranslit PRIVATE uztranslit_gui uztranslit_warnings)
target_compile_definitions(uztranslit PRIVATE UZT_VERSION="${PROJECT_VERSION}")

# ---------------------------------------------------------------- translations (Qt Linguist)
# English is the source language of the strings; uz is Uzbek in Latin 1995, ru is Russian.
# `cmake --build build --target update_translations` runs lupdate on the sources.
set(UZT_TS_FILES translations/uztranslit_uz.ts translations/uztranslit_ru.ts)
if(Qt6_VERSION VERSION_GREATER_EQUAL 6.7)
    qt_add_translations(uztranslit
        SOURCE_TARGETS uztranslit_gui uztranslit_files
        TS_FILES ${UZT_TS_FILES}
        NO_GENERATE_PLURALS_TS_FILE
        IMMEDIATE_CALL
        QM_FILES_OUTPUT_VARIABLE uzt_qm_files
        LUPDATE_OPTIONS -no-obsolete -locations none)
else()
    qt_add_translations(uztranslit_gui
        TS_FILES ${UZT_TS_FILES}
        SOURCES src/textfile.cpp src/documents.cpp src/batch.cpp
        QM_FILES_OUTPUT_VARIABLE uzt_qm_files
        LUPDATE_OPTIONS -no-obsolete -locations none)
endif()

uzt_add_app_resources(uztranslit)
if(APPLE)
    set_target_properties(uztranslit PROPERTIES
        OUTPUT_NAME UzTranslit
        MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/packaging/macos/Info.plist.in"
        MACOSX_BUNDLE_BUNDLE_NAME UzTranslit
        MACOSX_BUNDLE_GUI_IDENTIFIER uz.jaybi.latin.UzTranslit
        MACOSX_BUNDLE_ICON_FILE uztranslit.icns
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}")
endif()

install(TARGETS uztranslit
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
if(UNIX AND NOT APPLE)
    install(FILES packaging/linux/uztranslit.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    foreach(size IN LISTS UZT_ICON_SIZES ITEMS 512)
        install(FILES resources/icons/uztranslit-${size}.png
            DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/${size}x${size}/apps
            RENAME uztranslit.png)
    endforeach()
endif()

# ---------------------------------------------------------------- tests
if(UZT_BUILD_TESTS)
    enable_testing()
    set(UZT_TESTDATA "${CMAKE_CURRENT_BINARY_DIR}/testdata")

    # spec/fixtures.json is copied into the build tree (configure_file copies it again whenever it changes) and
    # compiled into a resource; no test contains a hand-copied case.
    configure_file("${UZT_REPO_ROOT}/spec/fixtures.json" "${UZT_TESTDATA}/spec/fixtures.json" COPYONLY)
    function(uzt_add_fixtures_resource target)
        qt_add_resources(${target} "${target}_fixtures"
            PREFIX "/"
            BASE "${UZT_TESTDATA}"
            FILES "${UZT_TESTDATA}/spec/fixtures.json")
    endfunction()

    # every QtTest report also goes to Testing/Temporary/<test>.txt: on Windows the console output of a test
    # started by ctest can be lost, and CI uploads that folder when a test fails
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/Testing/Temporary")
    qt_add_executable(tst_fixtures tests/tst_fixtures.cpp)
    target_link_libraries(tst_fixtures PRIVATE uztranslit_core Qt6::Test uztranslit_warnings)
    uzt_add_fixtures_resource(tst_fixtures)
    add_test(NAME tst_fixtures COMMAND tst_fixtures -o "${CMAKE_BINARY_DIR}/Testing/Temporary/tst_fixtures.txt,txt" -o -,txt)

    # build/differential.json: `node tools/make_differential.mjs` at the repository root (CI runs it before CMake).
    set(UZT_DIFFERENTIAL "${UZT_REPO_ROOT}/build/differential.json")
    qt_add_executable(tst_differential tests/tst_differential.cpp)
    target_link_libraries(tst_differential PRIVATE uztranslit_core Qt6::Test uztranslit_warnings)
    if(EXISTS "${UZT_DIFFERENTIAL}")
        configure_file("${UZT_DIFFERENTIAL}" "${UZT_TESTDATA}/differential/differential.json" COPYONLY)
        qt_add_resources(tst_differential "differential_corpus"
            PREFIX "/"
            BASE "${UZT_TESTDATA}"
            FILES "${UZT_TESTDATA}/differential/differential.json")
        target_compile_definitions(tst_differential PRIVATE UZT_HAVE_DIFFERENTIAL)
    else()
        message(STATUS "build/differential.json not found: tst_differential will be skipped "
                       "(run `node tools/make_differential.mjs` at the repository root, then configure again)")
    endif()
    add_test(NAME tst_differential COMMAND tst_differential -o "${CMAKE_BINARY_DIR}/Testing/Temporary/tst_differential.txt,txt" -o -,txt)
    set_tests_properties(tst_differential PROPERTIES SKIP_REGULAR_EXPRESSION "SKIP   : ")

    qt_add_executable(tst_documents tests/tst_documents.cpp)
    target_link_libraries(tst_documents PRIVATE uztranslit_files Qt6::Test uztranslit_warnings)
    add_test(NAME tst_documents COMMAND tst_documents -o "${CMAKE_BINARY_DIR}/Testing/Temporary/tst_documents.txt,txt" -o -,txt)

    # the real binary in command-line mode, without a display
    qt_add_executable(tst_cli tests/tst_cli.cpp)
    target_link_libraries(tst_cli PRIVATE Qt6::Core Qt6::Test uztranslit_warnings)
    target_compile_definitions(tst_cli PRIVATE UZT_APP="$<TARGET_FILE:uztranslit>")
    uzt_add_fixtures_resource(tst_cli)
    add_dependencies(tst_cli uztranslit)
    add_test(NAME tst_cli COMMAND tst_cli -o "${CMAKE_BINARY_DIR}/Testing/Temporary/tst_cli.txt,txt" -o -,txt)

    qt_add_executable(tst_gui tests/tst_gui.cpp)
    target_link_libraries(tst_gui PRIVATE uztranslit_gui Qt6::Test uztranslit_warnings)
    uzt_add_app_resources(tst_gui)
    add_test(NAME tst_gui COMMAND tst_gui -o "${CMAKE_BINARY_DIR}/Testing/Temporary/tst_gui.txt,txt" -o -,txt)
    set_tests_properties(tst_gui PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    qt_add_executable(tst_translations tests/tst_translations.cpp)
    target_link_libraries(tst_translations PRIVATE Qt6::Core Qt6::Test uztranslit_warnings)
    target_compile_definitions(tst_translations PRIVATE UZT_TS_DIR="${CMAKE_CURRENT_SOURCE_DIR}/translations")
    add_test(NAME tst_translations COMMAND tst_translations -o "${CMAKE_BINARY_DIR}/Testing/Temporary/tst_translations.txt,txt" -o -,txt)

    # the real binary in GUI mode: starts, opens a file, converts, quits (offscreen)
    configure_file(tests/smoke.txt "${UZT_TESTDATA}/smoke.txt" COPYONLY)
    add_test(NAME gui_smoke
        COMMAND ${CMAKE_COMMAND}
            -DAPP=$<TARGET_FILE:uztranslit>
            -DINPUT=${UZT_TESTDATA}/smoke.txt
            -DRESULT=${CMAKE_CURRENT_BINARY_DIR}/smoke-result.txt
            -DCONFIG=${CMAKE_CURRENT_BINARY_DIR}/smoke-config
            -P ${CMAKE_CURRENT_SOURCE_DIR}/tests/gui_smoke.cmake)
endif()
