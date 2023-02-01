type Handle = number;

interface HandleManager {
    get<T>(handle: Handle): T | null;
}
