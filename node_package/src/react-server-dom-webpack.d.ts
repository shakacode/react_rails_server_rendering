declare module 'react-server-dom-webpack/client' {
  // eslint-disable-next-line import/prefer-default-export
  export const createFromFetch: (promise: Promise<Response>) => Promise<unknown>;
}
