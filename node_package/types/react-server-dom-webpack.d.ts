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

declare module 'react-server-dom-webpack/client' {
  export const createFromFetch: (promise: Promise<Response>) => Promise<unknown>;

  export const createFromReadableStream: (stream: ReadableStream) => Promise<unknown>;
}
