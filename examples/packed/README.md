# Packed App Demo

Demonstrates how to create a single executable with embedded frontend resources using V's `$embed_file`.

## Features

- **Single Executable**: All assets compiled into binary
- **No External Files**: Self-contained application
- **Easy Distribution**: Just one file to share
- **Resource Embedding**: Uses V's compile-time `$embed_file`

## How to Run

```sh
# From this directory
v run main.v
```

Or build for distribution:

```sh
# Production build
v -prod -o myapp main.v

# Compressed build (smaller)
v -prod -compress -o myapp main.v

# Run the single executable
./myapp
```

## What It Demonstrates

This example shows how to:
- Use `$embed_file()` to embed files at compile time
- Create a `PackedApp` with embedded resources
- Run application with `run_packed()` instead of `run()`
- Distribute as single binary (~1.4 MB typical)

## How It Works

1. **Embed**: Use `$embed_file('path')` to include files in binary
2. **Pack**: Create `PackedApp` and add embedded files
3. **Extract**: At runtime, files are extracted to temp directory
4. **Serve**: WebSocket server serves from temp directory
5. **Cleanup**: Temp files cleaned up on exit

## Use Cases

- Desktop applications for end users
- Distribution without dependencies
- Portable applications
- CI/CD tooling

## Build Sizes

- Default build: ~1.4 MB
- Compressed build: ~0.9 MB

Actual size depends on embedded assets.
