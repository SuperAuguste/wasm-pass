// Generated by wasm-pass; edit at your own risk!

const util = require("util");

/**
 * @template T
 * @param {T} EnumType
 * @param {number} value
 * @returns {T}
 */
function createEnumValue(EnumType, value) {
    const lit = new EnumType();
    lit.value = value;
    return lit;
}

function sizeOf(value) {
    if (typeof value === "object" || typeof value === "function") {
        return value.meta.size;
    }

    throw new Error("Value has unknown size!");
}

const u8 = {
    meta: {
        size: 1
    }
};

class Enum {
    /**
     * @type {number}
     */
    value;
    
    constructor() {
        if (arguments.length !== 0)
            throw new Error(`Use ${this.constructor.name}.from(number)!`);
    }

    /**
     * @param {number} value
     * @returns {Enum}
     */
    static from(value) {
        for (const tag of Object.values(this).slice(1)) {
            if (tag.value === value)
                return tag;
        }

        const val = new this();
        val.value = value;
        return val;
    }

    toString() {
        for (const [name, tag] of Object.entries(this.constructor).slice(1)) {
            if (tag.value === this.value)
                return `${this.constructor.name.slice(5)}.${name}`;
        }

        return `${this.constructor.name.slice(5)}(${this.value})`;
    }

    [util.inspect.custom]() {
        return this.toString();
    }
}

class Struct {}

class Slice {
    /**
     * Type of the slice
     * @type {Object} type
     */
    type;

    /**
     * Length of the slice
     * @type {number} u32
     */
    len;

    /**
     * Pointer to the first element of the slice
     * @type {number} u32
     */
    ptr;

    constructor(type, len, ptr) {
        this.type = type;
        this.len = len;
        this.ptr = ptr;
    } 

    /**
     * Decodes a `Slice`
     * @param {Object} type Type of slice items
     * @param {DataView} dataView DataView representing WASM memory
     * @param {number} offset The offset at which the struct starts
     * @returns {Slice}
     */
    static decode(type, dataView, offset = 0) {
        const len = dataView.getUint32(offset);
        const ptr = dataView.getUint32(offset + 4);

        return new this(type, len, ptr);
    }

    get(dataView, index) {
        return this.type.decode(dataView, this.ptr + index * sizeOf(this.type));
    }

    set(dataView, index, value) {
        return value.encode(dataView, this.ptr + index * sizeOf(this.type));
    }
}

class Allocator {
    /**
     * @param {number} size
     */
    allocBytes;
    freeBytes;

    /**
     * @param {WebAssembly.Exports} exp
     */
    constructor(exp) {
        this.allocBytes = exp.allocBytes;
        this.freeBytes = exp.freeBytes;
    }

    /**
     * @param {Object} type
     * @param {number} len
     * @returns {Slice}
     */
    alloc(type, len) {
        // @ts-ignore
        return new Slice(type, len, this.allocBytes(sizeOf(type) * len));
    }

    /**
     * @param {Slice} slice
     */
    free(slice) {
        // @ts-ignore
        this.freeBytes(slice.ptr, sizeOf(slice.type) * slice.len);
    }
}

