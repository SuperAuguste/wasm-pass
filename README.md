# wasm-pass

## Demo

NOTE: Binding generation must be compiled to a 32-bit target to match WebAssembly's 32-bit exclusivity.

```bash
zig build bindings -Dtarget=i386-windows-gnu
node demo/demo.js
```
