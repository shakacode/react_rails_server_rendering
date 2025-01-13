import * as React from 'react';
import RSDWClient from 'react-server-dom-webpack/client';

if (!('use' in React)) {
  throw new Error('React.use is not defined. Please ensure you are using React 18 with experimental features enabled or React 19+ to use server components.');
}

const { use } = React;

const renderCache: Record<string, Promise<React.ReactNode>> = {};

export type RSCClientRootProps = {
  componentName: string;
  rscRenderingUrlPath: string;
}

const fetchRSC = ({ componentName, rscRenderingUrlPath }: RSCClientRootProps) => {
  if (!renderCache[componentName]) {
    renderCache[componentName] = RSDWClient.createFromFetch(fetch(`${rscRenderingUrlPath}/${componentName}`)) as Promise<React.ReactNode>;
  }
  return renderCache[componentName];
}

const RSCClientRoot = ({
  componentName,
  rscRenderingUrlPath,
}: RSCClientRootProps) => use(fetchRSC({ componentName, rscRenderingUrlPath }));

export default RSCClientRoot;
