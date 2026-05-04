# Hello World CLI Spec

## Motivation

A 30-line educational example: print "Hello, World!" to stdout and exit 0.

## Architecture

A single file `hello.py` containing a `main()` function. Entry point invoked via `if __name__ == "__main__": main()`.

## Success criteria

- `python hello.py` prints exactly `Hello, World!\n` to stdout
- Exit status 0
- No stderr output

## Out of scope

- CLI flags
- Internationalization
- Configuration

## Test

`python hello.py | diff - <(echo "Hello, World!")` produces empty output.
