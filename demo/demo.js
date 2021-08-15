const bindings = require("./bindings");

const imports = {
    fun: {
        decodeStruct(ptr) {
            // bindings.MyStruct.superJoe2(wasmInstance.exports, ptr);
            const st = bindings.MyStruct.decode(new DataView(wasmInstance.exports.memory.buffer), ptr);
            console.log(st);
            st.a = 20;
            st.b = 420;
            st.c = true;
            st.d = bindings.MyEnum.mama;
            st.encode(new DataView(wasmInstance.exports.memory.buffer), ptr);
            console.log(st);
        },

        decodeStruct2(ptr) {
            const st = bindings.MyStruct.decode(new DataView(wasmInstance.exports.memory.buffer), ptr);
            console.log(st);
        }
    }
};

const wasmModule = new WebAssembly.Module(require("fs").readFileSync(require("path").join(__dirname, "../zig-out/lib/demo.wasm")));
const wasmInstance = new WebAssembly.Instance(wasmModule, imports);
// console.log(bindings.Allocator);
const allocator = new bindings.Allocator(wasmInstance.exports);

// console.log(wasmInstance.exports);

// console.log(dataView.getUint32(0, true));
// console.log(new DataView(wasmInstance.exports.memory.buffer, slice.ptr, 20).getUint8(0, true));

wasmInstance.exports.joe();
