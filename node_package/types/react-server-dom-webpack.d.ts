declare module 'react-server-dom-webpack/node-loader' {
  interface LoadOptions {
    format: 'module';
    source: string;
  }

  interface LoadResult {
    source: string;
  }

  // eslint-disable-next-line import/prefer-default-export
  export function load(
    url: string,
    context: null | object,
    defaultLoad: () => Promise<LoadOptions>
  ): Promise<LoadResult>;
}
