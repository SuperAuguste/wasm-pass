const imports = {
    fun: {
        decodeStruct(ptr) {
            let st = bindings.MyStruct.decode(ptr);
            console.log("Struct decoded from Zig", st);

            console.log("Value pointed to by `f` is", new DataView(wasmInstance.exports.memory.buffer).getUint16(st.f, true));

            bindings.joeManipulatesStructFromZig(ptr);
            st = bindings.MyStruct.decode(ptr);
            console.log("Struct after being manipulated by Zig", st);

            st.a = 20;
            st.b = 420;
            st.c = true;
            st.d = bindings.MyEnum.mama;

            st.encode(ptr);
            console.log(st);
        },

        decodeStruct2(ptr) {
            const st = bindings.MyStruct.decode(ptr);
            console.log("Final decode", st);
        },
    },
};

const wasmModule = new WebAssembly.Module(require("fs").readFileSync(require("path").join(__dirname, "../zig-out/lib/demo.wasm")));
const wasmInstance = new WebAssembly.Instance(wasmModule, imports);

const bindings = require("./bindings")(wasmInstance);

bindings.joe();
