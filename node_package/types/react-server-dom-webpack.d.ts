declare module 'react-server-dom-webpack/node-loader' {
  interface LoadOptions {
    format: 'module';
    source: string;
  }

  interface LoadResult {
    source: string;
  }

  export function load(
    url: string,
    context: null | object,
    defaultLoad: () => Promise<LoadOptions>
  ): Promise<LoadResult>;
}

declare module 'react-server-dom-webpack/server.node' {
  export interface Options {
    environmentName?: string;
    onError?: (error: unknown) => void;
    onPostpone?: (reason: string) => void;
    identifierPrefix?: string;
  }

  export interface PipeableStream {
    abort(reason: unknown): void;
    pipe<Writable extends NodeJS.WritableStream>(destination: Writable): Writable;
  }

  // Note: ReactClientValue is likely what React uses internally for RSC
  // We're using 'unknown' here as it's the most accurate type we can use
  // without accessing React's internal types
  export function renderToPipeableStream(
    model: unknown,
    webpackMap: { [key: string]: unknown },
    options?: Options
  ): PipeableStream;
}

declare module 'react-server-dom-webpack/client' {
  export const createFromFetch: (promise: Promise<Response>) => Promise<unknown>;

  export const createFromReadableStream: (stream: ReadableStream) => Promise<unknown>;
}
