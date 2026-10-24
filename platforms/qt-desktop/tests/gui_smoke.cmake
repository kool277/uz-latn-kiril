# Runs the real application in GUI mode on the offscreen platform: it opens INPUT (Latin 1995), converts it to the
# default target (Latin 2026), writes the result to RESULT and quits. Testing aids of src/main.cpp:
# UZTRANSLIT_QUIT_AFTER_MS, UZTRANSLIT_SMOKE_RESULT, UZTRANSLIT_SETTINGS_DIR (fresh settings).
#   cmake -DAPP=… -DINPUT=… -DRESULT=… -DCONFIG=… -P gui_smoke.cmake
file(REMOVE "${RESULT}")
file(REMOVE_RECURSE "${CONFIG}")
set(ENV{QT_QPA_PLATFORM} offscreen)
set(ENV{UZTRANSLIT_QUIT_AFTER_MS} 1000)
set(ENV{UZTRANSLIT_SMOKE_RESULT} "${RESULT}")
set(ENV{UZTRANSLIT_SETTINGS_DIR} "${CONFIG}")
execute_process(COMMAND "${APP}" "${INPUT}" RESULT_VARIABLE rc TIMEOUT 120)
if(NOT rc EQUAL 0)
    message(FATAL_ERROR "the application exited with ${rc}")
endif()
if(NOT EXISTS "${RESULT}")
    message(FATAL_ERROR "no result was written")
endif()
file(READ "${RESULT}" got)
set(want "Özbekiston Respublikasi, Toşkent şahri.\n")
if(NOT got STREQUAL want)
    message(FATAL_ERROR "result:\n${got}\nexpected:\n${want}")
endif()
message(STATUS "GUI smoke test: started, opened the file, converted it, quit: ${got}")
