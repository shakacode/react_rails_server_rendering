import * as React from 'react';
import RSDWClient from 'react-server-dom-webpack/client';

if (!('use' in React)) {
  throw new Error('React.use is not defined. Please ensure you are using React 18.3.0-canary-670811593-20240322 or later to use server components.');
}

// It's not the exact type, but it's close enough for now
type Use = <T>(promise: Promise<T>) => T;
const { use } = React as { use: Use };

const renderCache: Record<string, Promise<unknown>> = {};

const fetchRSC = ({ componentName }: { componentName: string }) => {
  if (!renderCache[componentName]) {
    renderCache[componentName] = RSDWClient.createFromFetch(fetch(`/rsc/${componentName}`));
  }
  return renderCache[componentName];
}

const RSCClientRoot = ({ componentName }: { componentName: string }) => use(fetchRSC({ componentName }));

export default RSCClientRoot;
