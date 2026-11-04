#pragma once

/// Perl XSUB entry point. `/usr/bin/perl` loads this library because macOS only
/// answers MediaRemote now-playing queries for Apple-signed processes.
/// Writes one JSON object per line to stdout and reads commands from stdin;
/// never returns, and exits when stdin closes.
void notch_media_stream(void *interpreter, void *cv);
