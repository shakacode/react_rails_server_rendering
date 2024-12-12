import { renderToPipeableStream } from 'react-server-dom-webpack/server.node';
import { PassThrough, Readable } from 'stream';
import type { ReactElement } from 'react';

import { RSCRenderParams } from './types';
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
import loadReactClientManifest from './loadReactClientManifest';

const stringToStream = (str: string) => {
  const stream = new PassThrough();
  stream.push(str);
  stream.push(null);
  return stream;
};

const streamRenderRSCComponent = (reactElement: ReactElement, options: RSCRenderParams): Readable => {
  const { throwJsErrors, reactClientManifestFileName } = options;
  const renderState: StreamRenderState = {
    result: null,
    hasErrors: false,
    isShellReady: true
  };

  const { pipeToTransform, readableStream, emitError } = transformRenderStreamChunksToResultObject(renderState);
  try {
    const rscStream = renderToPipeableStream(
      reactElement,
      loadReactClientManifest(reactClientManifestFileName),
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

ReactOnRails.serverRenderRSCReactComponent = (options: RSCRenderParams) => {
  try {
    return streamServerRenderedComponent(options, streamRenderRSCComponent);
  } finally {
    console.history = [];
  }
};

export * from './types';
export default ReactOnRails;
