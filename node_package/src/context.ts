import type { ReactOnRails as ReactOnRailsType } from './types';

declare global {
  interface Window {
    ReactOnRails: ReactOnRailsType;
    __REACT_ON_RAILS_EVENT_HANDLERS_RAN_ONCE__?: boolean;
  }

  namespace NodeJS {
    interface Global {
      ReactOnRails: ReactOnRailsType;
    }
  }
  namespace Turbolinks {
    interface TurbolinksStatic {
      controller?: unknown;
    }
  }
}

export type Context = Window | NodeJS.Global;

/**
 * Get the context, be it window or global
 * @returns {boolean|Window|*|context}
 */
export default function context(this: void): Context | void {
  return ((typeof window !== 'undefined') && window) ||
    ((typeof global !== 'undefined') && global) ||
    this;
}


export function reactOnRailsContext(): Context {
  const ctx = context();
  if (ctx === undefined || typeof ctx.ReactOnRails === 'undefined') {
    throw new Error('ReactOnRails is undefined in both global and window namespaces.');
  }
  return ctx;
}
