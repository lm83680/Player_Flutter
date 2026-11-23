// The fd is owned by ArkTS after a successful createOutput.
export const createOutput: (path: string) => number;
export const openSurface: (surfaceId: string, width: number, height: number) => number;
export const writeFrame: (handle: number, rgba: ArrayBuffer, stride: number, bgra: boolean) => boolean;
export const closeSurface: (handle: number) => void;
