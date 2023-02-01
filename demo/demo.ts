import { readFile } from "fs/promises";
import { create, Manager as M, Identity } from "C:\\Programming\\Zig\\wasm-pass\\zig-cache\\wasm-pass\\bindings";

class Manager implements M {
    handles: any[] = [];

    getHandle<T>(handle: number): T | null {
        return this.handles[handle];
    }
    createHandle(): number {
        this.handles.push(null);
        return this.handles.length - 1;
    }
    createIdentity(handle: number): void {
        this.handles[handle] = {id: new Uint8Array(32), name: "travis is watching my stream rn"};
    }
}

(async () => {
    const mod = await WebAssembly.compile(await readFile("C:\\Programming\\Zig\\wasm-pass\\zig-out\\lib\\demo.wasm"));
    let manager = new Manager();

    let memory = new WebAssembly.Memory({ initial: 17, maximum: 100 });
    let instance = new WebAssembly.Instance(mod, create(manager, memory, {
        logThis (ptr: number, len: number) {
            console.log(new TextDecoder().decode(memory.buffer.slice(ptr, ptr + len)));
        }
    }));

    if (instance.exports.init)
            (instance.exports.init as Function)();
})();
