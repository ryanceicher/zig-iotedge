# zig-iotedge

## Zig-first API policy

This repository adopts a “Zig-first API” principle:

- All C interop details (C strings, raw pointers, C enums/structs, callback signatures) are fully encapsulated inside `src/root.zig`.
- Consumers (e.g., `src/main.zig` and any other modules) must only use the Zig-native API provided by `root.zig`.
- No consumer should import or reference `@cImport` types/constants or call C functions directly.

### What `root.zig` provides

- Zig-native enums and function pointer types for callbacks
- High-level methods for options, connection status, twin registration/snapshot, and reported state
- JSON helpers that parse directly from Zig slices

### Benefits

- Simpler and safer APIs for app code
- Clear separation of interop boundaries
- Flexibility to swap or adjust C bindings without touching business logic

## Running in Docker

- Build the container:

```pwsh
docker build -t zig-iotedge .
```

- Run the module (without IoT Edge env) to observe baseline behavior:

```pwsh
docker rm -f zig-iotedge-test 2>$null
docker run -d --name zig-iotedge-test zig-iotedge
docker logs --tail 50 zig-iotedge-test
```

- Deploy under IoT Edge to validate twin handling and reported-state ack.
