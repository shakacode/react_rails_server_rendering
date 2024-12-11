import { renderToPipeableStream } from 'react-server-dom-webpack/server.node';
import { PassThrough, Readable } from 'stream';
import type { ReactElement } from 'react';
import fs from 'fs';

import { RenderParams } from './types';
import ReactOnRails from './ReactOnRails';
import buildConsoleReplay from './buildConsoleReplay';
import handleError from './handleError';
import {
  streamServerRenderedComponent,
  type StreamRenderState,
  transformRenderStreamChunksToResultObject,
  convertToError,
  createResultObject,
} from './serverRenderReactComponent';

const stringToStream = (str: string) => {
  const stream = new PassThrough();
  stream.push(str);
  stream.push(null);
  return stream;
};

const getBundleConfig = () => JSON.parse(fs.readFileSync('./public/webpack/development/react-client-manifest.json', 'utf8'))

const streamRenderRSCComponent = (reactElement: ReactElement, options: RenderParams): Readable => {
  const { throwJsErrors } = options;
  const renderState: StreamRenderState = {
    result: null,
    hasErrors: false,
    isShellReady: true
  };

  const { pipeToTransform, readableStream, emitError } = transformRenderStreamChunksToResultObject(renderState);
  try {
    const rscStream = renderToPipeableStream(
      reactElement,
      getBundleConfig(),
      {
        onError: (err) => {
          const error = convertToError(err);
          console.error("Error in RSC stream", error);
          if (throwJsErrors) {
            emitError(error);
          }
          renderState.hasErrors = true;
          renderState.error = error;
        }
      }
    );
    pipeToTransform(rscStream);
    return readableStream;
  } catch (e) {
    const error = convertToError(e);
    renderState.hasErrors = true;
    renderState.error = error;
    const htmlResult = handleError({ e: error, name: options.name, serverSide: true });
    const jsonResult = JSON.stringify(createResultObject(htmlResult, buildConsoleReplay(), renderState));
    return stringToStream(jsonResult);
  }
};

ReactOnRails.serverRenderRSCReactComponent = (options: RenderParams) => {
  try {
    return streamServerRenderedComponent(options, streamRenderRSCComponent);
  } finally {
    console.history = [];
  }
};

export * from './types';
export default ReactOnRails;
