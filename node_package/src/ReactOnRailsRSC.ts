// @ts-expect-error will define this module types later
import { renderToReadableStream } from 'react-server-dom-webpack/server.edge';
import { PassThrough } from 'stream';
import fs from 'fs';

import { RenderParams } from './types';
import ComponentRegistry from './ComponentRegistry';
import createReactOutput from './createReactOutput';
import { isPromise, isServerRenderHash } from './isServerRenderResult';
import ReactOnRails from './ReactOnRails';

const stringToStream = (str: string) => {
  const stream = new PassThrough();
  stream.push(str);
  stream.push(null);
  return stream;
};

const getBundleConfig = () => {
  const bundleConfig = JSON.parse(fs.readFileSync('./public/webpack/development/react-client-manifest.json', 'utf8'));
  // remove file:// from keys
  const newBundleConfig: { [key: string]: unknown } = {};
  for (const [key, value] of Object.entries(bundleConfig)) {
    newBundleConfig[key.replace('file://', '')] = value;
  }
  return newBundleConfig;
}

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
    let finalValue = "";
    const streamReader = renderToReadableStream(reactRenderingResult, getBundleConfig()).getReader();
    const decoder = new TextDecoder();
    const processStream = async () => {
      const { done, value } = await streamReader.read();
      if (done) {
        renderResult?.push(null);
        // @ts-expect-error value is not typed
        debugConsole.log('value', finalValue);
        return;
      }

      finalValue += decoder.decode(value);
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
