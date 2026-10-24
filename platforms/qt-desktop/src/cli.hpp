// Command-line mode of the uztranslit binary. The flags mirror core/python/uztranslit.py:
//   uztranslit [-h] [--from {auto,cyr,lat,new}] --to {cyr,lat,new} [--ascii] [-o OUTPUT] [file]
// It runs on a QCoreApplication, so it never needs a display.
#pragma once

#include <QStringList>

namespace uzt {

// True when the arguments ask for the converter (--to, --from, --ascii, -o/--output, -h/--help, --version, or an
// unambiguous abbreviation of a long option, like argparse). Checked on the raw argv before any application object
// exists; a lone file argument opens the window instead.
bool isCliInvocation(int argc, char **argv);

// Runs the command line (arguments as QCoreApplication::arguments() returns them, program name first) and returns
// the exit code: 0 success, 1 input/output error, 2 usage error (as argparse).
int runCli(const QStringList &arguments);

} // namespace uzt
