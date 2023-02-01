type Handle = number;

interface HandleManager {
    getHandle<T>(handle: Handle): T | null;
    createHandle(): Handle;
};
