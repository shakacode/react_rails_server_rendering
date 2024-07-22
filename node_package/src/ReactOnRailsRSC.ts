import type { ReactElement } from 'react';
// @ts-expect-error will define this module types later
import { renderToReadableStream } from 'react-server-dom-webpack/server.edge';
import { PassThrough } from 'stream';

import { RenderParams } from './types';
import ComponentRegistry from './ComponentRegistry';
import createReactOutput from './createReactOutput';
import { isPromise, isServerRenderHash } from './isServerRenderResult';
import handleError from './handleError';
import ReactOnRails from './ReactOnRails';

(async () => {
  try {
    // @ts-expect-error AsyncLocalStorage is not in the node types
    globalThis.AsyncLocalStorage = (await import('node:async_hooks')).AsyncLocalStorage;
  } catch (e) {
    console.log('AsyncLocalStorage not found');
  }
})();

const stringToStream = (str: string) => {
  const stream = new PassThrough();
  stream.push(str);
  stream.push(null);
  return stream;
};

ReactOnRails.serverRenderRSCReactComponent = (options: RenderParams) => {
  const { name, domNodeId, trace, props, railsContext, throwJsErrors } = options;

  let renderResult: null | PassThrough = null;

  try {
    const componentObj = ComponentRegistry.get(name);
    if (componentObj.isRenderer) {
      throw new Error(`\
Detected a renderer while server rendering component '${name}'. \
See https://github.com/shakacode/react_on_rails#renderer-functions`);
    }

    const reactRenderingResult = createReactOutput({
      componentObj,
      domNodeId,
      trace,
      props,
      railsContext,
    });

    if (isServerRenderHash(reactRenderingResult) || isPromise(reactRenderingResult)) {
      throw new Error('Server rendering of streams is not supported for server render hashes or promises.');
    }

    renderResult = new PassThrough();
    const streamReader = renderToReadableStream(reactRenderingResult as ReactElement).getReader();
    const processStream = async () => {
      const { done, value } = await streamReader.read();
      if (done) {
        renderResult?.push(null);
        return;
      }

      renderResult?.push(value);
      processStream();
    }
    processStream();
  } catch (e: unknown) {
    if (throwJsErrors) {
      throw e;
    }

    renderResult = stringToStream(`Error: ${e}`);
  }

  return renderResult;
};

export * from './types';
export default ReactOnRails;